require "inotify"
require "./watcher/event"
require "./storage_backend"

module Sepia
  # File system watcher for monitoring changes to Sepia objects.
  #
  # The Watcher monitors the storage directory and generates events when
  # objects are created, modified, or deleted. It uses inotify on Linux
  # to efficiently monitor file system changes.
  #
  # ⚠️ **WARNING**: The Watcher API is subject to change and currently
  # only supports Linux systems with inotify.
  #
  # ### Example
  #
  # ```crystal
  # # Configure storage
  # Sepia::Storage.configure(:filesystem, {"path" => "./data"})
  #
  # # Create watcher
  # watcher = Sepia::Watcher.new(Sepia::Storage.backend.as(FileStorage))
  #
  # # Register callback
  # watcher.on_change do |event|
  #   puts "#{event.type}: #{event.object_class} #{event.object_id}"
  #
  #   # Load the modified object
  #   if event.type.modified?
  #     begin
  #       obj = Sepia::Storage.load(event.object_class.constantize(typeof(Object)), event.object_id)
  #       handle_object_change(obj)
  #     rescue ex
  #       puts "Failed to load object: #{ex.message}"
  #     end
  #   end
  # end
  #
  # # Start watching
  # watcher.start
  # ```
  class Watcher
    # Storage backend being watched
    getter storage : FileStorage

    # Callback for file system events
    property callback : (Event ->)?

    # Internal file tracking to avoid callback loops
    @@internal_files = Set(String).new
    @@internal_files_mutex = Mutex.new

    # Inotify watcher instance
    @inotify : Inotify::Watcher

    # Creates a new Watcher instance.
    #
    # ### Parameters
    #
    # - *storage* : The FileStorage backend to monitor
    #
    # ### Example
    #
    # ```crystal
    # storage = Sepia::Storage.backend.as(FileStorage)
    # watcher = Sepia::Watcher.new(storage)
    # ```
    def initialize(@storage : FileStorage)
      @inotify = Inotify.watcher
      @watching = false
    end

    # Registers a callback for file system change events.
    #
    # Only one callback can be registered per watcher instance.
    # Calling this multiple times will replace the previous callback.
    #
    # ### Parameters
    #
    # - *callback* : A proc that receives an Event object
    #
    # ### Example
    #
    # ```crystal
    # watcher.on_change do |event|
    #   puts "Change detected: #{event.type} #{event.object_class}"
    # end
    # ```
    def on_change(&@callback : Event ->)
    end

    # Starts monitoring the storage directory for changes.
    #
    # This method starts a background fiber that monitors file system
    # events and calls the registered callback. It returns immediately.
    #
    # ### Example
    #
    # ```crystal
    # watcher.on_change { |event| puts event }
    # watcher.start
    # # watcher now monitoring in background
    # ```
    def start
      return if @watching

      @watching = true

      # Set up event handler
      @inotify.on_event do |inotify_event|
        handle_inotify_event(inotify_event)
      end

      # Start watching the storage directory
      @inotify.watch(@storage.path)
    end

    # Stops monitoring the storage directory.
    #
    # This stops the inotify watcher and stops generating events.
    # The watcher can be started again with `start`.
    #
    # ### Example
    #
    # ```crystal
    # watcher.start
    # # ... monitor changes ...
    # watcher.stop
    # ```
    def stop
      @watching = false
      @inotify.close
    end

    # Checks if the watcher is currently monitoring.
    #
    # ### Returns
    #
    # `true` if the watcher is actively monitoring, `false` otherwise.
    #
    # ### Example
    #
    # ```crystal
    # puts watcher.running? # => false
    # watcher.start
    # puts watcher.running? # => true
    # ```
    def running? : Bool
      @watching
    end

    # Adds a file to the internal operation tracking set.
    #
    # This is used by storage backends to mark files that are being
    # modified by Sepia itself, so the watcher doesn't generate events
    # for internal operations.
    #
    # This method is thread-safe.
    #
    # ### Parameters
    #
    # - *path* : The file path to track
    #
    # ### Example
    #
    # ```crystal
    # # Used internally by storage backends
    # Sepia::Watcher.add_internal_file("/storage/MyDocument/doc-123.tmp")
    # # ... perform save operation ...
    # Sepia::Watcher.remove_internal_file("/storage/MyDocument/doc-123.tmp")
    # ```
    def self.add_internal_file(path : String)
      @@internal_files_mutex.synchronize do
        @@internal_files.add(path)
      end
    end

    # Removes a file from the internal operation tracking set.
    #
    # This method is thread-safe.
    #
    # ### Parameters
    #
    # - *path* : The file path to remove from tracking
    def self.remove_internal_file(path : String)
      @@internal_files_mutex.synchronize do
        @@internal_files.delete(path)
      end
    end

    # Checks if a file is currently being tracked as an internal operation.
    #
    # This method is thread-safe.
    #
    # ### Parameters
    #
    # - *path* : The file path to check
    #
    # ### Returns
    #
    # `true` if the file is being tracked as an internal operation.
    def self.internal_file?(path : String) : Bool
      @@internal_files_mutex.synchronize do
        @@internal_files.includes?(path)
      end
    end

    private def handle_inotify_event(inotify_event : Inotify::Event)
      # Skip events without a name
      return unless inotify_event.name

      # Skip temporary files from atomic writes
      return if inotify_event.name.ends_with?(".tmp")

      # Skip internal operations
      full_path = File.join(@storage.path, inotify_event.name)
      return if Watcher.internal_file?(full_path)

      # Parse the path to extract object class and ID
      path_result = parse_path(inotify_event.name)
      if path_result
        object_class, object_id = path_result
        event_type = convert_event_type(inotify_event.type)

        if event_type
          event = Event.new(
            type: event_type,
            object_class: object_class,
            object_id: object_id,
            path: full_path
          )

          # Call the callback if one is registered
          if callback = @callback
            callback.call(event)
          end
        end
      end
    end

    private def parse_path(relative_path : String) : Tuple(String, String)?
      # Path format: ClassName/object_id or ClassName/object_id/...
      parts = relative_path.split('/', 3)
      return nil if parts.size < 2

      object_class = parts[0]
      object_id = parts[1]

      # Skip system directories
      return nil if object_class.starts_with?('.')
      return nil if object_id.starts_with?('.')

      {object_class, object_id}
    end

    private def convert_event_type(event_type : Inotify::Event::Type) : EventType?
      # Convert inotify type to our EventType
      case event_type
      when .create?
        EventType::Created
      when .modify?
        EventType::Modified
      when .delete?
        EventType::Deleted
      when .moved_to?
        EventType::Modified
      when .moved_from?
        EventType::Deleted
      else
        nil
      end
    end
  end
end
{% begin %}
  {% if flag?(:inotify) %}
    require "inotify"
  {% else %}
    require "fswatch"
  {% end %}
{% end %}

require "set"
require "./file_storage"
require "./storage_backend"
require "./path_resolver"
require "./cache_manager"

module Sepia
  # File system event types for Sepia objects.
  enum EventType
    Created
    Modified
    Deleted
  end

  # Represents a file system event for a Sepia object.
  struct Event
    property type : EventType
    property object_class : String
    property object_id : String
    property path : String
    property timestamp : Time
    property object_info : PathResolver::ObjectInfo?

    def initialize(@type : EventType, @object_class : String, @object_id : String, @path : String, @object_info : PathResolver::ObjectInfo? = nil)
      @timestamp = Time.local
    end

    # Get the resolved object information for this event
    def object_info?
      @object_info
    end

    # Load the actual Sepia object from this event
    #
    # ```
    # obj = event.object(MyDocument)
    # if obj
    #   puts "Loaded object: #{obj.class.name}"
    # end
    # ```
    def object(klass : Class) : Object?
      info = @object_info
      return nil unless info

      info.object(klass)
    end
  end

  {% if flag?(:inotify) %}
    # File system watcher for Sepia objects using inotify.cr.
    #
    # This implementation uses Linux-native inotify for file system monitoring
    # and provides the same API as the fswatch-based watcher.
    #
    # ### Build Instructions
    #
    # To use this implementation, compile with the `inotify` flag:
    #
    # ```bash
    # crystal build src/your_app.cr -D inotify
    # ```
    #
    # ### Platform Notes
    #
    # - Linux-only (inotify is a Linux-specific feature)
    # - Better static compilation support
    # - Lower memory footprint
    # - More efficient event processing
    class Watcher
      # Class-level internal file tracking for thread safety
      @@internal_files = Set(String).new
      @@internal_files_mutex = Mutex.new

      # Storage backend being watched
      getter storage : FileStorage

      # Path resolver for converting file paths to Sepia object information
      getter path_resolver : PathResolver

      # Whether the watcher is currently running
      property running : Bool = false

      # The inotify watcher instance
      @inotify_watcher : Inotify::Watcher?

      # Event counter for debugging
      @event_count : Int32 = 0

      # Callback block for event handling
      getter callback_block : (Event ->)?
      @callback_block : (Event ->)?

      # Alias for callback_block to match spec expectations
      def callback
        @callback_block
      end

      # Class methods for internal file tracking
      def self.internal_file?(path : String) : Bool
        @@internal_files_mutex.synchronize do
          @@internal_files.includes?(path)
        end
      end

      def self.add_internal_file(path : String) : Nil
        @@internal_files_mutex.synchronize do
          @@internal_files.add(path)
        end
      end

      def self.remove_internal_file(path : String) : Nil
        @@internal_files_mutex.synchronize do
          @@internal_files.delete(path)
        end
      end

      def initialize(@storage : FileStorage)
        @path_resolver = PathResolver.new(@storage.path)
      end

      # Register a callback to be called when events occur
      def on_change(&block : Event ->)
        @callback_block = block

        # If inotify watcher is already created, set up the callback immediately
        if watcher = @inotify_watcher
          setup_watcher_callback(watcher, block)
        end

        spawn do
          # Keep the callback fiber alive while watcher is running
          while @running
            sleep 0.1.seconds
          end
        end
      end

      # Start watching the storage directory for changes
      def start
        return if @running

        @running = true
        watch_path = @storage.path

        # Create and configure the inotify watcher
        @inotify_watcher = Inotify::Watcher.new(recursive: true)

        # Set up callback if one was registered
        if callback = @callback_block
          setup_watcher_callback(@inotify_watcher.not_nil!, callback)
        end

        # Add the storage path to monitor
        @inotify_watcher.not_nil!.watch(watch_path)
      end

      # Stop watching for file system changes
      def stop
        return unless @running

        @running = false

        # Stop the inotify watcher
        if watcher = @inotify_watcher
          watcher.close
          @inotify_watcher = nil
        end
      end

      # Check if the watcher is currently running
      def running?
        @running
      end

      # Get the number of events processed (for debugging)
      def event_count
        @event_count
      end

      # Set up the inotify watcher callback
      private def setup_watcher_callback(watcher : Inotify::Watcher, block : Event ->)
        watcher.on_event do |inotify_event|
          sepia_event = convert_inotify_event(inotify_event)
          if sepia_event
            # Automatically invalidate cache entry for this event
            invalidate_cache_for_event(sepia_event)

            block.call(sepia_event)
            @event_count += 1
          end
        end
      end

      # Create standardized cache key for an event
      private def cache_key_for_event(event : Event) : String
        "#{event.object_class}:#{event.object_id}"
      end

      # Invalidate cache entry for a Sepia event
      private def invalidate_cache_for_event(event : Event) : Bool
        cache_key = cache_key_for_event(event)
        CacheManager.instance.invalidate(cache_key)
      end

      # Convert inotify events to Sepia events
      private def convert_inotify_event(event : Inotify::Event) : Event?
        # Get the full path for the event
        full_path = if event_name = event.name
                      if event_path = event.path
                        File.join(event_path, event_name)
                      else
                        event_name
                      end
                    else
                      event.path
                    end

        return nil unless full_path

        # Skip hidden files but NOT .tmp files (they indicate real changes)
        filename = File.basename(full_path)
        return nil if filename.starts_with?(".")

        # Handle .tmp files by waiting for the real file
        if filename.ends_with?(".tmp")
          # For .tmp files, try to resolve the non-tmp version
          real_path = full_path.gsub(/\.tmp$/, "")
          object_info = @path_resolver.resolve_path(real_path)
          return nil unless object_info

          # Create an event for the real file that will be created
          return Event.new(
            type: EventType::Created,
            object_class: object_info.class_name,
            object_id: object_info.object_id,
            path: real_path,
            object_info: object_info
          )
        end

        # Use PathResolver to parse the path and get object information
        object_info = @path_resolver.resolve_path(full_path)

        # If direct resolution fails, check if this is a directory event
        # and we should be looking for files within it
        unless object_info
          if event.directory?
            # For directory events, we don't generate Sepia events directly
            # but they indicate that files within might be changing
            return nil
          end
        end

        return nil unless object_info

        # Map inotify event types to Sepia event types
        event_type = case
                     when event.type.create?
                       EventType::Created
                     when event.type.modify?
                       EventType::Modified
                     when event.type.delete?, event.type.moved_from?
                       EventType::Deleted
                     else
                       return nil # Skip unknown event types
                     end

        # Create and return the Sepia event with object information
        Event.new(
          type: event_type,
          object_class: object_info.class_name,
          object_id: object_info.object_id,
          path: full_path,
          object_info: object_info
        )
      end
    end
  {% else %}
    # File system watcher for Sepia objects using crystal-fswatch.
    #
    # This watcher monitors file system changes in a Sepia storage directory
    # and emits events for created, modified, or deleted objects.
    #
    # ### Basic Usage
    #
    # ```
    # storage = Sepia::FileStorage.new("./data")
    # watcher = Sepia::Watcher.new(storage)
    #
    # # Register a callback to receive events
    # watcher.on_change do |event|
    #   puts "Event: #{event.type} for #{event.object_class}:#{event.object_id}"
    # end
    #
    # # Start watching (this is non-blocking)
    # watcher.start
    #
    # # When done, stop watching
    # watcher.stop
    # ```
    #
    # ### Design Principles
    #
    # This watcher uses **crystal-fswatch** for reliable file system monitoring:
    # - Cross-platform support (Linux, macOS, Windows)
    # - No hanging issues in spec environments
    # - Clean lifecycle management
    # - Thread-safe event handling
    #
    # ### Path Structure
    #
    # The watcher expects paths in the format: `storage_path/ClassName/object_id`
    # It will parse these paths and extract the class name and object ID for each event.
    class Watcher
      # Class-level internal file tracking for thread safety
      @@internal_files = Set(String).new
      @@internal_files_mutex = Mutex.new

      # Storage backend being watched
      getter storage : FileStorage

      # Path resolver for converting file paths to Sepia object information
      getter path_resolver : PathResolver

      # Whether the watcher is currently running
      property running : Bool = false

      # The fswatch session instance
      @session : FSWatch::Session?

      # Event counter for debugging
      @event_count : Int32 = 0

      # Callback block for event handling
      getter callback_block : (Event ->)?
      @callback_block : (Event ->)?

      # Alias for callback_block to match spec expectations
      def callback
        @callback_block
      end

      # Class methods for internal file tracking
      def self.internal_file?(path : String) : Bool
        @@internal_files_mutex.synchronize do
          @@internal_files.includes?(path)
        end
      end

      def self.add_internal_file(path : String) : Nil
        @@internal_files_mutex.synchronize do
          @@internal_files.add(path)
        end
      end

      def self.remove_internal_file(path : String) : Nil
        @@internal_files_mutex.synchronize do
          @@internal_files.delete(path)
        end
      end

      def initialize(@storage : FileStorage)
        @path_resolver = PathResolver.new(@storage.path)
      end

      # Register a callback to be called when events occur
      #
      # The callback will be called for each event that occurs while the watcher is running.
      #
      # ```
      # watcher.on_change do |event|
      #   puts "Got event: #{event.type}"
      # end
      # ```
      def on_change(&block : Event ->)
        @callback_block = block

        # If session is already created, set up the callback immediately
        if session = @session
          setup_session_callback(session, block)
        end

        spawn do
          # Keep the callback fiber alive while watcher is running
          while @running
            sleep 0.1.seconds
          end
        end
      end

      # Start watching the storage directory for changes
      #
      # This method is non-blocking and returns immediately.
      # The actual file system monitoring happens in the background.
      #
      # ```
      # watcher.start
      # puts "Watcher started, continuing with other work..."
      # ```
      def start
        return if @running

        @running = true
        watch_path = @storage.path

        # Create and configure the fswatch session
        @session = FSWatch::Session.build(
          recursive: true,
          latency: 0.1
        )

        # Set up callback if one was registered
        if callback = @callback_block
          setup_session_callback(@session.not_nil!, callback)
        end

        # Add the storage path to monitor
        @session.not_nil!.add_path(watch_path)

        # Start monitoring
        @session.not_nil!.start_monitor
      end

      # Stop watching for file system changes
      #
      # This stops the background monitoring.
      #
      # ```
      # watcher.stop
      # puts "Watcher stopped"
      # ```
      def stop
        return unless @running

        @running = false

        # Stop the fswatch session
        if session = @session
          session.stop_monitor
          @session = nil
        end
      end

      # Check if the watcher is currently running
      def running?
        @running
      end

      # Get the number of events processed (for debugging)
      def event_count
        @event_count
      end

      # Set up the fswatch session callback
      private def setup_session_callback(session : FSWatch::Session, block : Event ->)
        session.on_change do |fswatch_event|
          sepia_event = convert_fswatch_event(fswatch_event)
          if sepia_event
            # Automatically invalidate cache entry for this event
            invalidate_cache_for_event(sepia_event)

            block.call(sepia_event)
            @event_count += 1
          end
        end
      end

      # Create standardized cache key for an event
      #
      # ### Parameters
      #
      # - *event* : The Sepia event to create a cache key for
      #
      # ### Returns
      #
      # Cache key string in format "ClassName:object_id"
      #
      # ### Example
      #
      # ```
      # key = cache_key_for_event(event)
      # # => "MyDocument:doc-123"
      # ```
      private def cache_key_for_event(event : Event) : String
        "#{event.object_class}:#{event.object_id}"
      end

      # Invalidate cache entry for a Sepia event
      #
      # This method automatically invalidates the corresponding cache entry
      # when a file system event is detected, ensuring cache consistency.
      #
      # ### Parameters
      #
      # - *event* : The Sepia event that triggered cache invalidation
      #
      # ### Returns
      #
      # `true` if cache entry was invalidated, `false` if it didn't exist
      #
      # ### Example
      #
      # ```
      # invalidate_cache_for_event(event)
      # ```
      private def invalidate_cache_for_event(event : Event) : Bool
        cache_key = cache_key_for_event(event)
        CacheManager.instance.invalidate(cache_key)
      end

      # Convert fswatch events to Sepia events
      #
      # This method uses the PathResolver to convert file paths to Sepia object information,
      # then creates appropriate Sepia::Event objects.
      private def convert_fswatch_event(event : FSWatch::Event) : Event?
        # Skip hidden files but NOT .tmp files (they indicate real changes)
        filename = File.basename(event.path)
        return nil if filename.starts_with?(".")

        # Handle .tmp files by waiting for the real file
        if filename.ends_with?(".tmp")
          # For .tmp files, try to resolve the non-tmp version
          real_path = event.path.gsub(/\.tmp$/, "")
          object_info = @path_resolver.resolve_path(real_path)
          return nil unless object_info

          # Create an event for the real file that will be created
          return Event.new(
            type: EventType::Created,
            object_class: object_info.class_name,
            object_id: object_info.object_id,
            path: real_path,
            object_info: object_info
          )
        end

        # Use PathResolver to parse the path and get object information
        object_info = @path_resolver.resolve_path(event.path)

        # If direct resolution fails, check if this is a directory event
        # and we should be looking for files within it
        unless object_info
          if File.directory?(event.path)
            # For directory events, we don't generate Sepia events directly
            # but they indicate that files within might be changing
            return nil
          end
        end

        return nil unless object_info

        # Map fswatch event types to Sepia event types
        event_type = case
                     when event.created?
                       EventType::Created
                     when event.updated?
                       EventType::Modified
                     when event.removed?, event.moved_from?
                       EventType::Deleted
                     else
                       return nil # Skip unknown event types
                     end

        # Create and return the Sepia event with object information
        Event.new(
          type: event_type,
          object_class: object_info.class_name,
          object_id: object_info.object_id,
          path: event.path,
          object_info: object_info
        )
      end
    end
  {% end %}
end

require "file_utils"
require "./event"
require "./storage"
require "./watcher"

module Sepia
  # Abstract base class for event logging backends.
  #
  # This class defines the interface that all event logging implementations
  # must follow. Different backends can store events in different ways
  # while providing the same API to the storage system.
  #
  # ### Implementations
  #
  # - `PerFileEventLogger` - One file per object (current default)
  # - `GlobalEventLogger` - Single global log file (future)
  # - `DatabaseEventLogger` - Database storage (future)
  # - `CompositeEventLogger` - Multiple backends simultaneously (future)
  abstract class EventLoggerBackend
    # Append an event to the log.
    #
    # ### Parameters
    #
    # - *object* : The Sepia object the event relates to
    # - *event_type* : Type of event (Created, Updated, Deleted)
    # - *generation* : Object generation number
    # - *metadata* : Optional metadata for the event
    abstract def append_event(object : Serializable | Container, event_type : LogEventType, generation : Int32, metadata)

    # Read all events for a specific object.
    #
    # ### Parameters
    #
    # - *object_class* : The class of the object
    # - *id* : The object's unique identifier
    #
    # ### Returns
    #
    # Array of events for the specified object, ordered by timestamp
    abstract def read_events(object_class : Class, id : String) : Array(LogEvent)

    # Check if this backend should log events for the given class.
    #
    # Default implementation checks if the class has sepia_log_events enabled.
    # Subclasses can override for more sophisticated filtering.
    #
    # ### Parameters
    #
    # - *klass* : The class to check
    #
    # ### Returns
    #
    # True if events should be logged for this class
    def should_log?(klass : Class) : Bool
      klass.responds_to?(:sepia_log_events) && klass.sepia_log_events
    end
  end

  # Event logging backend that stores one file per object.
  #
  # This is the default implementation that creates a separate JSON Lines
  # file for each object, containing all events for that object in
  # chronological order.
  #
  # ### File Structure
  #
  # ```
  # storage_path/
  #   ├── Document/   # Regular object storage
  #       └──.events/ # Event storage
  #       └── Document/
  #           └── doc - 123.jsonl # Events for doc-123
  # ```
  #
  # ### Event Format
  #
  # Each line in the file is a JSON object:
  # ```
  # {"ts":"2025-01-15T10:30:45Z","type":"created","gen":1,"meta":{}}
  # {"ts":"2025-01-15T11:15:22Z","type":"updated","gen":2,"meta":{"user":"alice"}}
  # ```
  class PerFileEventLogger < EventLoggerBackend
    # The base storage path for events.
    #
    # This is automatically detected from the current storage backend.
    property base_path : String

    def initialize(@base_path : String = get_storage_path)
    end

    # Get the storage path from the current backend.
    #
    # Tries to detect the base storage path from the currently configured
    # storage backend. Falls back to system temp directory if detection fails.
    #
    # ### Returns
    #
    # The base storage path for storing events
    private def get_storage_path : String
      if backend = Storage.backend
        case backend
        when FileStorage
          return backend.path
        else
          return Dir.tempdir
        end
      end
      Dir.tempdir
    end

    # Append an event to the object's event file.
    #
    # Creates the event file and directory structure if needed,
    # then appends the event as a JSON line.
    #
    # ### Parameters
    #
    # - *object* : The Sepia object the event relates to
    # - *event_type* : Type of event (Created, Updated, Deleted)
    # - *generation* : Object generation number
    # - *metadata* : Optional metadata for the event
    def append_event(object : Serializable | Container, event_type : LogEventType, generation : Int32, metadata)
      return unless should_log?(object.class)
      metadata_json = metadata ? JSON.parse(metadata.to_json) : JSON::Any.new({} of String => JSON::Any)
      event = LogEvent.new(event_type, generation, metadata_json)
      event_file = event_file_path(object.class, object.sepia_id)

      # Ensure directory exists
      FileUtils.mkdir_p(File.dirname(event_file))

      # Mark event file as internal to prevent filesystem watcher events
      Watcher.add_internal_file(event_file)

      begin
        # Append event as JSON line
        File.write(event_file, event.to_json + "\n", mode: "a")

        # Remove from internal tracking after a brief delay
        spawn do
          sleep 0.3.seconds
          Watcher.remove_internal_file(event_file)
        end
      rescue ex
        # Ensure cleanup even on error
        Watcher.remove_internal_file(event_file)
        raise ex
      end
    end

    # Read all events for a specific object from its event file.
    #
    # Returns an empty array if the file doesn't exist or no events are found.
    #
    # ### Parameters
    #
    # - *object_class* : The class of the object
    # - *id* : The object's unique identifier
    #
    # ### Returns
    #
    # Array of events for the specified object, ordered by timestamp
    def read_events(object_class : Class, id : String) : Array(LogEvent)
      event_file = event_file_path(object_class, id)
      return [] of LogEvent unless File.exists?(event_file)

      events = [] of LogEvent
      begin
        File.each_line(event_file) do |line|
          next if line.strip.empty?
          begin
            events.push(LogEvent.from_json(line))
          rescue ex
            # Skip invalid lines but continue parsing valid ones
            # Don't log to avoid cluttering test output
          end
        end
      rescue ex
        # Log error but don't fail - return whatever events we could parse
        puts "Warning: Error reading event file #{event_file}: #{ex.message}"
      end

      events
    end

    # Get the file path for an object's event log.
    #
    # ### Parameters
    #
    # - *object_class* : The class of the object
    # - *id* : The object's unique identifier
    #
    # ### Returns
    #
    # Path to the object's event file
    private def event_file_path(object_class : Class, id : String) : String
      File.join(@base_path, ".events", object_class.name, "#{id}.jsonl")
    end
  end

  # Main event logger that manages event logging operations.
  #
  # This class provides the main interface for event logging in Sepia.
  # It manages the active backend and provides convenience methods
  # for common operations.
  class EventLogger
    # The current event logging backend.
    #
    # Defaults to PerFileEventLogger, but can be changed to support
    # different storage strategies.
    class_property backend : EventLoggerBackend = PerFileEventLogger.new

    # Configure the event logging backend.
    #
    # ### Parameters
    #
    # - *backend* : The backend instance to use for event logging
    #
    # ### Example
    #
    # ```
    # # Use per-file logging (default)
    # Sepia::EventLogger.configure(PerFileEventLogger.new("./data"))
    #
    # # Use global logging (future feature)
    # Sepia::EventLogger.configure(GlobalEventLogger.new("./data/events.jsonl"))
    # ```
    def self.configure(backend : EventLoggerBackend)
      @@backend = backend
    end

    # Reset the event logging backend to a fresh instance.
    #
    # This is useful in tests when you want to ensure a clean backend
    # that points to the current storage backend.
    def self.reset_backend
      @@backend = PerFileEventLogger.new
    end

    # Append an event to the log using the current backend.
    #
    # This is the main entry point for event logging. It delegates
    # to the configured backend after checking if logging is enabled.
    #
    # ### Parameters
    #
    # - *object* : The Sepia object the event relates to
    # - *event_type* : Type of event (Created, Updated, Deleted)
    # - *generation* : Object generation number
    # - *metadata* : Optional metadata for the event
    #
    # ### Example
    #
    # ```
    # Sepia::EventLogger.append_event(document, LogEventType::Updated, 2, {"user" => "alice"})
    # ```
    def self.append_event(object : Serializable | Container, event_type : LogEventType, generation : Int32, metadata)
      @@backend.append_event(object, event_type, generation, metadata)
    end

    # Read all events for a specific object using the current backend.
    #
    # ### Parameters
    #
    # - *object_class* : The class of the object
    # - *id* : The object's unique identifier
    #
    # ### Returns
    #
    # Array of events for the specified object, ordered by timestamp
    #
    # ### Example
    #
    # ```
    # events = Sepia::EventLogger.read_events(MyDocument, "doc-123")
    # events.each { |event| puts "#{event.timestamp}: #{event.event_type}" }
    # ```
    def self.read_events(object_class : Class, id : String) : Array(LogEvent)
      @@backend.read_events(object_class, id)
    end

    # Get the last event for a specific object.
    #
    # Convenience method that returns only the most recent event.
    #
    # ### Parameters
    #
    # - *object_class* : The class of the object
    # - *id* : The object's unique identifier
    #
    # ### Returns
    #
    # The last event for the object, or nil if no events exist
    #
    # ### Example
    #
    # ```
    # last_event = Sepia::EventLogger.last_event(MyDocument, "doc-123")
    # if last_event
    #   puts "Last modified: #{last_event.timestamp}"
    # end
    # ```
    def self.last_event(object_class : Class, id : String) : LogEvent?
      read_events(object_class, id).last?
    end

    # Get the next generation number for an object.
    #
    # This method reads the existing events for an object and determines
    # what the next generation number should be based on the last event.
    #
    # ### Parameters
    #
    # - *object_class* : The class of the object
    # - *id* : The object's unique identifier
    #
    # ### Returns
    #
    # The next generation number (1 for new objects, existing+1 for updates)
    #
    # ### Example
    #
    # ```
    # next_gen = Sepia::EventLogger.next_generation(MyDocument, "doc-123")
    # puts "Next generation: #{next_gen}"
    # ```
    def self.next_generation(object_class : Class, id : String) : Int32
      events = read_events(object_class, id)
      return 1 if events.empty?

      last_event = events.last
      case last_event.event_type
      when LogEventType::Deleted
        1 # Start over after deletion
      else
        last_event.generation + 1
      end
    end

    # Get the current generation for an object.
    #
    # This determines what generation number should be used for activity events.
    # It looks at the most recent save event (Created or Updated) to determine
    # the current generation of the object.
    #
    # ### Parameters
    #
    # - *object_class* : The class of the object
    # - *id* : The object's unique identifier
    #
    # ### Returns
    #
    # The current generation number for the object, or 0 if no save events exist
    #
    # ### Example
    #
    # ```
    # current_gen = Sepia::EventLogger.current_generation(MyDocument, "doc-123")
    # ```
    def self.current_generation(object_class : Class, id : String) : Int32
      events = read_events(object_class, id)
      return 0 if events.empty?

      # Find the most recent save event (Created or Updated)
      events.reverse_each do |event|
        case event.event_type
        when LogEventType::Created, LogEventType::Updated
          return event.generation
        end
      end

      # No save events found, return 0
      0
    end

    # Check if event logging is enabled for a class.
    #
    # Delegates to the current backend's should_log? method.
    #
    # ### Parameters
    #
    # - *klass* : The class to check
    #
    # ### Returns
    #
    # True if events should be logged for this class
    def self.should_log?(klass : Class) : Bool
      @@backend.should_log?(klass)
    end
  end
end

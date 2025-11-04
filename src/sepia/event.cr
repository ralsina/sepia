require "json"

module Sepia
  # Event types for Sepia object operations.
  #
  # These represent the different operations that can be performed on
  # Sepia objects and are recorded in the event log.
  enum LogEventType
    Created
    Updated
    Deleted
    Activity

    def to_json(json : JSON::Builder)
      json.string(to_s.downcase)
    end
  end

  # Represents an event in the Sepia object lifecycle.
  #
  # This struct captures when and how an object was modified, including
  # optional metadata provided during save operations.
  #
  # ### Properties
  #
  # - *timestamp*: When the event occurred
  # - *event_type*: Type of operation (Created, Updated, Deleted)
  # - *generation*: Object generation number for optimistic concurrency
  # - *metadata*: Optional user-provided context (username, reason, etc.)
  #
  # ### Example
  #
  # ```
  # event = Sepia::LogEvent.new(
  #   event_type: Sepia::LogEventType::Updated,
  #   generation: 2,
  #   metadata: {"user" => "alice", "reason" => "content_edit"}
  # )
  # ```
  struct LogEvent
    property timestamp : Time
    property event_type : LogEventType
    property generation : Int32
    property metadata : JSON::Any

    def initialize(@event_type : LogEventType, @generation : Int32, @metadata = JSON::Any.new({} of String => JSON::Any), @timestamp : Time = Time.local)
    end

    # Creates a LogEvent from JSON string.
    #
    # ### Parameters
    #
    # - *json_string* : JSON representation of the event
    #
    # ### Returns
    #
    # A new LogEvent instance parsed from the JSON
    #
    # ### Example
    #
    # ```
    # event_json = %({"ts":"2025-01-15T10:30:45Z","type":"updated","gen":2,"meta":{"user":"alice"}})
    # event = Sepia::LogEvent.from_json(event_json)
    # ```
    def self.from_json(json_string : String) : self
      parsed = JSON.parse(json_string)

      timestamp = Time.parse_utc(parsed["ts"].as_s, "%Y-%m-%dT%H:%M:%SZ")
      event_type = LogEventType.parse(parsed["type"].as_s)
      generation = parsed["gen"].as_i
      metadata = parsed["meta"]?

      new(event_type, generation, metadata || JSON::Any.new({} of String => JSON::Any), timestamp)
    end

    # Serializes the event to JSON format.
    #
    # ### Returns
    #
    # A JSON string representation of the event
    #
    # ### Example
    #
    # ```
    # event = Sepia::LogEvent.new(Sepia::LogEventType::Created, 1, {"user" => "alice"})
    # json = event.to_json # => {"ts":"2025-01-15T10:30:45Z","type":"created","gen":1,"meta":{"user":"alice"}}
    # ```
    def to_json : String
      String.build do |json|
        to_json(json)
      end
    end

    # Serializes the event to JSON format (builder version).
    #
    # This method writes the JSON representation to the provided JSON::Builder.
    # Used internally by the JSON serialization system.
    #
    # ### Parameters
    #
    # - *json* : JSON::Builder to write to
    def to_json(json : JSON::Builder)
      json.object do
        json.field("ts", timestamp.to_rfc3339)
        json.field("type", event_type)
        json.field("gen", generation)
        json.field("meta", metadata)
      end
    end

    # Creates a LogEvent for object creation.
    #
    # ### Parameters
    #
    # - *generation* : Initial generation number (usually 1)
    # - *metadata* : Optional metadata for the creation event
    #
    # ### Returns
    #
    # A new LogEvent with Created type
    #
    # ### Example
    #
    # ```
    # event = Sepia::LogEvent.created(1, {"user" => "alice"})
    # ```
    def self.created(generation : Int32, metadata = nil) : self
      metadata_json = metadata ? JSON.parse(metadata.to_json) : JSON::Any.new({} of String => JSON::Any)
      new(LogEventType::Created, generation, metadata_json)
    end

    # Creates a LogEvent for object updates.
    #
    # ### Parameters
    #
    # - *generation* : New generation number after update
    # - *metadata* : Optional metadata for the update event
    #
    # ### Returns
    #
    # A new LogEvent with Updated type
    #
    # ### Example
    #
    # ```
    # event = Sepia::LogEvent.updated(2, {"user" => "bob", "reason" => "fix_typo"})
    # ```
    def self.updated(generation : Int32, metadata = nil) : self
      metadata_json = metadata ? JSON.parse(metadata.to_json) : JSON::Any.new({} of String => JSON::Any)
      new(LogEventType::Updated, generation, metadata_json)
    end

    # Creates a LogEvent for object deletion.
    #
    # ### Parameters
    #
    # - *metadata* : Optional metadata for the deletion event
    #
    # ### Returns
    #
    # A new LogEvent with Deleted type (generation is always 0 for deletions)
    #
    # ### Example
    #
    # ```
    # event = Sepia::LogEvent.deleted({"user" => "admin", "reason" => "cleanup"})
    # ```
    def self.deleted(metadata = nil) : self
      metadata_json = metadata ? JSON.parse(metadata.to_json) : JSON::Any.new({} of String => JSON::Any)
      new(LogEventType::Deleted, 0, metadata_json)
    end

    # Creates a LogEvent for user activities.
    #
    # ### Parameters
    #
    # - *metadata* : Optional metadata for the activity event
    #
    # ### Returns
    #
    # A new LogEvent with Activity type (generation is always 0 for activities)
    #
    # ### Example
    #
    # ```
    # event = Sepia::LogEvent.activity({"action" => "moved_lane", "user" => "alice"})
    # ```
    def self.activity(metadata = nil) : self
      metadata_json = metadata ? JSON.parse(metadata.to_json) : JSON::Any.new({} of String => JSON::Any)
      new(LogEventType::Activity, 0, metadata_json)
    end
  end
end

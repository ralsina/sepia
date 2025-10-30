module Sepia
  # Types of file system events that can be detected.
  #
  # These represent the basic operations that can happen to objects
  # in storage that we want to monitor.
  enum EventType
    # A new file or directory was created
    Created
    # An existing file or directory was modified
    Modified
    # A file or directory was deleted
    Deleted
  end

  # Represents a file system change event for a Sepia object.
  #
  # Each event contains information about what type of change occurred,
  # which object was affected, and where on disk the change happened.
  #
  # ### Properties
  #
  # - *type* : The type of event (Created, Modified, Deleted)
  # - *object_class* : The class name of the affected object as a String
  # - *object_id* : The sepia_id of the affected object
  # - *path* : The absolute path to the file/directory that changed
  # - *timestamp* : When the event was detected (Time.utc)
  #
  # ### Example
  #
  # ```
  # event = Event.new(
  #   type: EventType::Modified,
  #   object_class: "MyDocument",
  #   object_id: "doc-123",
  #   path: "/storage/MyDocument/doc-123",
  #   timestamp: Time.utc
  # )
  #
  # puts "Event: #{event.type} #{event.object_class} #{event.object_id}"
  # # => Event: Modified MyDocument doc-123
  # ```
  struct Event
    property type : EventType
    property object_class : String
    property object_id : String
    property path : String
    property timestamp : Time

    def initialize(@type : EventType, @object_class : String, @object_id : String, @path : String, @timestamp : Time = Time.utc)
    end
  end
end

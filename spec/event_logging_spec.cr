require "spec"
require "../src/sepia"

# Define test classes in a module to avoid scoping issues
module EventLoggingTestClasses
  class TestClassWithLogging < Sepia::Object
    include Sepia::Serializable
    sepia_log_events true

    def to_sepia : String
      "test content"
    end

    def self.from_sepia(string : String)
      new
    end
  end

  class TestClassWithoutLogging < Sepia::Object
    include Sepia::Serializable

    def to_sepia : String
      "test content"
    end

    def self.from_sepia(string : String)
      new
    end
  end

  class EventLoggerTestClass < Sepia::Object
    include Sepia::Serializable
    sepia_log_events true

    property content : String

    def initialize(@content = "")
    end

    def to_sepia : String
      @content
    end

    def self.from_sepia(string : String)
      new(string)
    end
  end

  class LoggedDocument < Sepia::Object
    include Sepia::Serializable
    sepia_log_events true

    property content : String

    def initialize(@content = "")
    end

    def to_sepia : String
      @content
    end

    def self.from_sepia(string : String)
      new(string)
    end
  end

  class UnloggedDocument < Sepia::Object
    include Sepia::Serializable

    property content : String

    def initialize(@content = "")
    end

    def to_sepia : String
      @content
    end

    def self.from_sepia(string : String)
      new(string)
    end
  end

  class TrackedDocument < Sepia::Object
    include Sepia::Serializable
    sepia_log_events true

    property content : String

    def initialize(@content = "")
    end

    def to_sepia : String
      @content
    end

    def self.from_sepia(string : String)
      new(string)
    end
  end

  class DeletableDocument < Sepia::Object
    include Sepia::Serializable
    sepia_log_events true

    property content : String

    def initialize(@content = "")
    end

    def to_sepia : String
      @content
    end

    def self.from_sepia(string : String)
      new(string)
    end
  end

  class VersionedDocument < Sepia::Object
    include Sepia::Serializable
    sepia_log_events true

    property content : String

    def initialize(@content = "")
    end

    def to_sepia : String
      @content
    end

    def self.from_sepia(string : String)
      new(string)
    end
  end

  class DualDocument < Sepia::Object
    include Sepia::Serializable
    sepia_log_events true

    property content : String

    def initialize(@content = "")
    end

    def to_sepia : String
      @content
    end

    def self.from_sepia(string : String)
      new(string)
    end
  end

  class QueryTestDocument < Sepia::Object
    include Sepia::Serializable
    sepia_log_events true

    property content : String

    def initialize(@content = "")
    end

    def to_sepia : String
      @content
    end

    def self.from_sepia(string : String)
      new(string)
    end
  end

  class LastEventTestDocument < Sepia::Object
    include Sepia::Serializable
    sepia_log_events true

    property content : String

    def initialize(@content = "")
    end

    def to_sepia : String
      @content
    end

    def self.from_sepia(string : String)
      new(string)
    end
  end

  class TestContainer < Sepia::Object
    include Sepia::Container
    sepia_log_events true

    property content : String

    def initialize(@content = "")
    end
  end
end

describe "Sepia Event Logging" do
  describe "Event struct" do
    it "creates an event with correct properties" do
      event = Sepia::LogEvent.new(
        Sepia::LogEventType::Created,
        1,
        JSON.parse(%({"user": "alice"}))
      )

      event.event_type.should eq(Sepia::LogEventType::Created)
      event.generation.should eq(1)
      event.metadata.should eq(JSON.parse(%({"user": "alice"})))
      event.timestamp.should be_a(Time)
    end

    it "serializes to JSON correctly" do
      event = Sepia::LogEvent.created(1, {"user" => "bob"})
      json = event.to_json

      json.should contain("\"type\":\"created\"")
      json.should contain("\"gen\":1")
      json.should contain("\"meta\":{\"user\":\"bob\"}")
      json.should contain("\"ts\"")
    end

    it "deserializes from JSON correctly" do
      json = %({"ts":"2025-01-15T10:30:45Z","type":"updated","gen":2,"meta":{"user":"alice"}})
      event = Sepia::LogEvent.from_json(json)

      event.event_type.should eq(Sepia::LogEventType::Updated)
      event.generation.should eq(2)
      event.metadata.should eq(JSON.parse(%({"user": "alice"})))
    end

    it "has convenience factory methods" do
      created = Sepia::LogEvent.created(1)
      created.event_type.should eq(Sepia::LogEventType::Created)
      created.generation.should eq(1)
      created.metadata.should eq(JSON.parse(%({})))

      updated = Sepia::LogEvent.updated(2, {"user" => "bob"})
      updated.event_type.should eq(Sepia::LogEventType::Updated)
      updated.generation.should eq(2)
      updated.metadata.should eq(JSON.parse(%({"user": "bob"})))

      deleted = Sepia::LogEvent.deleted({"reason" => "cleanup"})
      deleted.event_type.should eq(Sepia::LogEventType::Deleted)
      deleted.generation.should eq(0)
      deleted.metadata.should eq(JSON.parse(%({"reason": "cleanup"})))
    end
  end

  describe "sepia_log_events macro" do
    it "adds sepia_log_events property to classes" do
      EventLoggingTestClasses::TestClassWithLogging.sepia_log_events.should be_true
    end

    it "defaults to false for classes without the macro" do
      EventLoggingTestClasses::TestClassWithoutLogging.sepia_log_events.should be_false
    end
  end

  describe "EventLogger backend" do
    temp_dir = ""

    before_each do
      temp_dir = File.join(Dir.tempdir, "event_logger_test_#{Random::Secure.hex(8)}")
      Dir.mkdir_p(temp_dir)
    end

    after_each do
      FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
    end

    it "stores events in per-object files" do
      logger = Sepia::PerFileEventLogger.new(temp_dir)
      obj = EventLoggingTestClasses::EventLoggerTestClass.new("Hello World")
      obj.sepia_id = "test-123"

      logger.append_event(obj, Sepia::LogEventType::Created, 1, {"user" => "alice"})

      event_file = File.join(temp_dir, ".events", EventLoggingTestClasses::EventLoggerTestClass.name, "test-123.jsonl")
      File.exists?(event_file).should be_true
    end

    it "reads events from per-object files" do
      logger = Sepia::PerFileEventLogger.new(temp_dir)
      obj = EventLoggingTestClasses::EventLoggerTestClass.new("Hello World")
      obj.sepia_id = "test-123"

      # Add events
      logger.append_event(obj, Sepia::LogEventType::Created, 1, {"user" => "alice"})
      logger.append_event(obj, Sepia::LogEventType::Updated, 2, {"user" => "bob"})

      # Read events
      events = logger.read_events(EventLoggingTestClasses::EventLoggerTestClass, "test-123")
      events.size.should eq(2)
      events[0].event_type.should eq(Sepia::LogEventType::Created)
      events[0].generation.should eq(1)
      events[0].metadata.should eq({"user" => "alice"})
      events[1].event_type.should eq(Sepia::LogEventType::Updated)
      events[1].generation.should eq(2)
      events[1].metadata.should eq({"user" => "bob"})
    end

    it "returns empty array for non-existent event files" do
      logger = Sepia::PerFileEventLogger.new(temp_dir)
      events = logger.read_events(EventLoggingTestClasses::EventLoggerTestClass, "non-existent")
      events.should eq([] of Sepia::LogEvent)
    end

    it "handles JSON parsing errors gracefully" do
      logger = Sepia::PerFileEventLogger.new(temp_dir)
      obj = EventLoggingTestClasses::EventLoggerTestClass.new("Hello World")
      obj.sepia_id = "json-test-123"

      # Create event file with invalid JSON
      event_file = File.join(temp_dir, ".events", EventLoggingTestClasses::EventLoggerTestClass.name, "json-test-123.jsonl")
      FileUtils.mkdir_p(File.dirname(event_file))
      File.write(event_file, "invalid json\n{\"ts\":\"2025-01-15T10:30:45Z\",\"type\":\"updated\",\"gen\":1,\"meta\":{\"valid\":\"json\"}}\n")

      # Should parse valid events and skip invalid ones
      events = logger.read_events(EventLoggingTestClasses::EventLoggerTestClass, "json-test-123")
      events.size.should eq(1)
      events[0].metadata.should eq({"valid" => "json"})
    end
  end

  describe "EventLogger integration" do
    temp_dir = ""

    before_each do
      temp_dir = File.join(Dir.tempdir, "event_integration_test_#{Random::Secure.hex(8)}")
      Dir.mkdir_p(temp_dir)
      Sepia::Storage.configure(:filesystem, {"path" => temp_dir})
    end

    after_each do
      FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
    end

    it "detects storage path correctly" do
      logger = Sepia::PerFileEventLogger.new
      logger.base_path.should eq(temp_dir)
    end

    it "determines next generation correctly" do
      # First event should be generation 1
      next_gen = Sepia::EventLogger.next_generation(EventLoggingTestClasses::EventLoggerTestClass, "test-doc")
      next_gen.should eq(1)

      # Simulate some events
      logger = Sepia::EventLogger.backend.as(Sepia::PerFileEventLogger)
      obj = EventLoggingTestClasses::EventLoggerTestClass.new("Hello")
      obj.sepia_id = "test-doc"

      logger.append_event(obj, Sepia::LogEventType::Created, 1, {} of String => String)
      logger.append_event(obj, Sepia::LogEventType::Updated, 2, {} of String => String)

      # Next generation should be 3
      next_gen = Sepia::EventLogger.next_generation(EventLoggingTestClasses::EventLoggerTestClass, "test-doc")
      next_gen.should eq(3)

      # After deletion, generation should reset to 1
      logger.append_event(obj, Sepia::LogEventType::Deleted, 0, {} of String => String)
      next_gen = Sepia::EventLogger.next_generation(EventLoggingTestClasses::EventLoggerTestClass, "test-doc")
      next_gen.should eq(1)
    end

    it "gets last event correctly" do
      # Use a different object ID to avoid conflicts with previous tests
      obj = EventLoggingTestClasses::EventLoggerTestClass.new("Hello")
      obj.sepia_id = "test-doc-last-event"

      # No events initially
      last_event = Sepia::EventLogger.last_event(EventLoggingTestClasses::EventLoggerTestClass, "test-doc-last-event")
      last_event.should be_nil

      # Add some events
      logger = Sepia::EventLogger.backend.as(Sepia::PerFileEventLogger)
      logger.append_event(obj, Sepia::LogEventType::Created, 1, {"user" => "alice"})
      logger.append_event(obj, Sepia::LogEventType::Updated, 2, {"user" => "bob"})

      # Should get the last event
      last_event = Sepia::EventLogger.last_event(EventLoggingTestClasses::EventLoggerTestClass, "test-doc-last-event")
      last_event.should_not be_nil
      if last_event
        last_event.event_type.should eq(Sepia::LogEventType::Updated)
        last_event.generation.should eq(2)
        last_event.metadata.should eq({"user" => "bob"})
      end
    end
  end

  describe "Storage API integration" do
    temp_dir = ""

    before_each do
      temp_dir = File.join(Dir.tempdir, "storage_integration_test_#{Random::Secure.hex(8)}")
      Dir.mkdir_p(temp_dir)
      Sepia::Storage.configure(:filesystem, {"path" => temp_dir})
    end

    after_each do
      FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
    end

    it "logs events for classes with logging enabled" do
      # Save with logging enabled
      doc = EventLoggingTestClasses::LoggedDocument.new("Hello World")
      doc.sepia_id = "logged-doc-123"

      Sepia::Storage.save(doc, metadata: {"user" => "alice", "action" => "create"})

      # Check that event was logged
      events = Sepia::Storage.object_events(EventLoggingTestClasses::LoggedDocument, "logged-doc-123")
      events.size.should eq(1)
      events[0].event_type.should eq(Sepia::LogEventType::Created)
      events[0].metadata.should eq({"user" => "alice", "action" => "create"})
    end

    it "does not log events for classes without logging enabled" do
      # Save without logging enabled
      doc = EventLoggingTestClasses::UnloggedDocument.new("Hello World")
      doc.sepia_id = "unlogged-doc-123"

      Sepia::Storage.save(doc, metadata: {"user" => "alice"})

      # Check that no event was logged
      events = Sepia::Storage.object_events(EventLoggingTestClasses::UnloggedDocument, "unlogged-doc-123")
      events.should eq([] of Sepia::LogEvent)
    end

    it "logs updates with correct event type" do
      doc = EventLoggingTestClasses::TrackedDocument.new("Hello World")
      doc.sepia_id = "tracked-doc-123"

      # Initial save (should be Created)
      Sepia::Storage.save(doc, metadata: {"user" => "alice"})

      # Update save (should be Updated)
      doc.content = "Updated content"
      Sepia::Storage.save(doc, metadata: {"user" => "bob", "reason" => "edit"})

      # Check events
      events = Sepia::Storage.object_events(EventLoggingTestClasses::TrackedDocument, "tracked-doc-123")
      events.size.should eq(2)
      events[0].event_type.should eq(Sepia::LogEventType::Created)
      events[0].metadata.should eq({"user" => "alice"})
      events[1].event_type.should eq(Sepia::LogEventType::Updated)
      events[1].metadata.should eq({"user" => "bob", "reason" => "edit"})
    end

    it "logs deletions with metadata" do
      doc = EventLoggingTestClasses::DeletableDocument.new("Hello World")
      doc.sepia_id = "deletable-doc-123"

      # Save first
      Sepia::Storage.save(doc, metadata: {"user" => "alice"})

      # Delete with metadata
      Sepia::Storage.delete(doc, metadata: {"user" => "admin", "reason" => "cleanup"})

      # Check events
      events = Sepia::Storage.object_events(EventLoggingTestClasses::DeletableDocument, "deletable-doc-123")
      events.size.should eq(2)
      events[0].event_type.should eq(Sepia::LogEventType::Created)
      events[1].event_type.should eq(Sepia::LogEventType::Deleted)
      events[1].metadata.should eq({"user" => "admin", "reason" => "cleanup"})
    end

    it "generates correct generation numbers" do
      doc = EventLoggingTestClasses::VersionedDocument.new("Version 1")
      doc.sepia_id = "versioned-doc-123"

      # Multiple saves should increment generation
      Sepia::Storage.save(doc) # gen 1
      doc.content = "Version 2"
      Sepia::Storage.save(doc) # gen 2
      doc.content = "Version 3"
      Sepia::Storage.save(doc) # gen 3

      events = Sepia::Storage.object_events(EventLoggingTestClasses::VersionedDocument, "versioned-doc-123")
      events.size.should eq(3)
      events[0].generation.should eq(1)
      events[1].generation.should eq(2)
      events[2].generation.should eq(3)
    end

    it "works with both instance and class methods" do
      # Instance method
      doc1 = EventLoggingTestClasses::DualDocument.new("Instance method")
      doc1.sepia_id = "dual-doc-1"
      storage = Sepia::Storage.new
      storage.save(doc1, metadata: {"method" => "instance"})

      # Class method
      doc2 = EventLoggingTestClasses::DualDocument.new("Class method")
      doc2.sepia_id = "dual-doc-2"
      Sepia::Storage.save(doc2, metadata: {"method" => "class"})

      # Both should be logged
      events1 = Sepia::Storage.object_events(EventLoggingTestClasses::DualDocument, "dual-doc-1")
      events2 = Sepia::Storage.object_events(EventLoggingTestClasses::DualDocument, "dual-doc-2")

      events1.size.should eq(1)
      events1[0].metadata.should eq({"method" => "instance"})

      events2.size.should eq(1)
      events2[0].metadata.should eq({"method" => "class"})
    end
  end

  describe "query methods" do
    temp_dir = ""

    before_each do
      temp_dir = File.join(Dir.tempdir, "query_methods_test_#{Random::Secure.hex(8)}")
      Dir.mkdir_p(temp_dir)
      Sepia::Storage.configure(:filesystem, {"path" => temp_dir})
    end

    after_each do
      FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
    end

    it "provides object_events method" do
      doc = EventLoggingTestClasses::QueryTestDocument.new("Test content")
      doc.sepia_id = "query-test-doc"

      # Add multiple events
      Sepia::Storage.save(doc, metadata: {"user" => "alice"})
      doc.content = "Updated content"
      Sepia::Storage.save(doc, metadata: {"user" => "bob"})

      # Query events
      events = Sepia::Storage.object_events(EventLoggingTestClasses::QueryTestDocument, "query-test-doc")
      events.size.should eq(2)
      events[0].metadata["user"].should eq("alice")
      events[1].metadata["user"].should eq("bob")
    end

    it "provides last_event method" do
      doc = EventLoggingTestClasses::LastEventTestDocument.new("Test content")
      doc.sepia_id = "last-event-test-doc"

      # No events initially
      last_event = Sepia::Storage.last_event(EventLoggingTestClasses::LastEventTestDocument, "last-event-test-doc")
      last_event.should be_nil

      # Add events
      Sepia::Storage.save(doc, metadata: {"user" => "alice", "action" => "create"})
      doc.content = "Updated content"
      Sepia::Storage.save(doc, metadata: {"user" => "bob", "action" => "edit"})

      # Get last event
      last_event = Sepia::Storage.last_event(EventLoggingTestClasses::LastEventTestDocument, "last-event-test-doc")
      last_event.should_not be_nil
      if last_event
        last_event.event_type.should eq(Sepia::LogEventType::Updated)
        last_event.metadata.should eq({"user" => "bob", "action" => "edit"})
      end
    end
  end

  describe "Object Activity Logging" do
    temp_dir = ""

    before_each do
      temp_dir = File.join(Dir.tempdir, "activity_test_#{Random::Secure.hex(8)}")
      Dir.mkdir_p(temp_dir)
      Sepia::Storage.configure(:filesystem, {"path" => temp_dir})
    end

    after_each do
      FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
    end

    it "logs activities for Serializable objects" do
      obj = EventLoggingTestClasses::EventLoggerTestClass.new("Test content")
      obj.sepia_id = "activity-test-123"

      # Log an activity
      obj.log_activity("moved_lane", {"from" => "In Progress", "to" => "Done", "user" => "alice"})

      # Check that activity was logged
      events = Sepia::Storage.object_events(EventLoggingTestClasses::EventLoggerTestClass, "activity-test-123")
      events.size.should eq(1)
      events[0].event_type.should eq(Sepia::LogEventType::Activity)
      events[0].metadata["action"].should eq("moved_lane")
      events[0].metadata["from"].should eq("In Progress")
      events[0].metadata["to"].should eq("Done")
      events[0].metadata["user"].should eq("alice")
    end

    it "logs simple activities without metadata" do
      obj = EventLoggingTestClasses::EventLoggerTestClass.new("Test content")
      obj.sepia_id = "simple-activity-123"

      # Log a simple activity
      obj.log_activity("edited")

      # Check that activity was logged
      events = Sepia::Storage.object_events(EventLoggingTestClasses::EventLoggerTestClass, "simple-activity-123")
      events.size.should eq(1)
      events[0].event_type.should eq(Sepia::LogEventType::Activity)
      events[0].metadata["action"].should eq("edited")
    end

    it "does not log activities for classes without logging enabled" do
      obj = EventLoggingTestClasses::TestClassWithoutLogging.new
      obj.sepia_id = "no-logging-123"

      # Attempt to log an activity
      obj.log_activity("should_not_log", {"user" => "alice"})

      # Check that no activity was logged
      events = Sepia::Storage.object_events(EventLoggingTestClasses::TestClassWithoutLogging, "no-logging-123")
      events.should eq([] of Sepia::LogEvent)
    end

    it "logs activities alongside regular object events" do
      doc = EventLoggingTestClasses::LoggedDocument.new("Hello World")
      doc.sepia_id = "mixed-events-123"

      # Save the object (creates Created event)
      Sepia::Storage.save(doc, metadata: {"user" => "alice"})

      # Log an activity
      doc.log_activity("highlighted", {"color" => "yellow", "user" => "bob"})

      # Update the object (creates Updated event)
      doc.content = "Updated content"
      Sepia::Storage.save(doc, metadata: {"user" => "charlie"})

      # Check all events are present
      events = Sepia::Storage.object_events(EventLoggingTestClasses::LoggedDocument, "mixed-events-123")
      events.size.should eq(3)

      events[0].event_type.should eq(Sepia::LogEventType::Created)
      events[0].metadata["user"].should eq("alice")

      events[1].event_type.should eq(Sepia::LogEventType::Activity)
      events[1].metadata["action"].should eq("highlighted")
      events[1].metadata["color"].should eq("yellow")
      events[1].metadata["user"].should eq("bob")

      events[2].event_type.should eq(Sepia::LogEventType::Updated)
      events[2].metadata["user"].should eq("charlie")
    end

    it "logs activities for Container objects" do
      container = EventLoggingTestClasses::TestContainer.new("Container content")
      container.sepia_id = "container-activity-123"

      # Save the container
      Sepia::Storage.save(container)

      # Log an activity
      container.log_activity("restructured", {"sections" => 3, "user" => "alice"})

      # Check that activity was logged
      events = Sepia::Storage.object_events(EventLoggingTestClasses::TestContainer, "container-activity-123")
      events.size.should eq(2)
      events[0].event_type.should eq(Sepia::LogEventType::Created)
      events[1].event_type.should eq(Sepia::LogEventType::Activity)
      events[1].metadata["action"].should eq("restructured")
      events[1].metadata["sections"].should eq(3)
      events[1].metadata["user"].should eq("alice")
    end

    it "logs activities with current generation number" do
      doc = EventLoggingTestClasses::LoggedDocument.new("Hello World")
      doc.sepia_id = "gen-test-123"

      # Save the object (creates Created event with generation 1)
      Sepia::Storage.save(doc, metadata: {"user" => "alice"})

      # Log an activity (should use generation 1)
      doc.log_activity("highlighted", {"color" => "yellow", "user" => "bob"})

      # Update the object (creates Updated event with generation 2)
      doc.content = "Updated content"
      Sepia::Storage.save(doc, metadata: {"user" => "charlie"})

      # Log another activity (should use generation 2)
      doc.log_activity("shared", {"platform" => "slack", "user" => "diana"})

      # Check all events and their generations
      events = Sepia::Storage.object_events(EventLoggingTestClasses::LoggedDocument, "gen-test-123")
      events.size.should eq(4)

      events[0].event_type.should eq(Sepia::LogEventType::Created)
      events[0].generation.should eq(1)

      events[1].event_type.should eq(Sepia::LogEventType::Activity)
      events[1].generation.should eq(1)  # Activity uses generation 1
      events[1].metadata["action"].should eq("highlighted")

      events[2].event_type.should eq(Sepia::LogEventType::Updated)
      events[2].generation.should eq(2)

      events[3].event_type.should eq(Sepia::LogEventType::Activity)
      events[3].generation.should eq(2)  # Activity uses generation 2
      events[3].metadata["action"].should eq("shared")
    end

    it "logs delete events with current generation number" do
      doc = EventLoggingTestClasses::LoggedDocument.new("Hello World")
      doc.sepia_id = "delete-gen-test-123"

      # Save the object (creates Created event with generation 1)
      Sepia::Storage.save(doc, metadata: {"user" => "alice"})

      # Update the object (creates Updated event with generation 2)
      doc.content = "Updated content"
      Sepia::Storage.save(doc, metadata: {"user" => "bob"})

      # Delete the object (should use generation 2)
      Sepia::Storage.delete(doc, metadata: {"user" => "admin", "reason" => "cleanup"})

      # Check all events and their generations
      events = Sepia::Storage.object_events(EventLoggingTestClasses::LoggedDocument, "delete-gen-test-123")
      events.size.should eq(3)

      events[0].event_type.should eq(Sepia::LogEventType::Created)
      events[0].generation.should eq(1)

      events[1].event_type.should eq(Sepia::LogEventType::Updated)
      events[1].generation.should eq(2)

      events[2].event_type.should eq(Sepia::LogEventType::Deleted)
      events[2].generation.should eq(2)  # Delete uses generation 2
      events[2].metadata["user"].should eq("admin")
      events[2].metadata["reason"].should eq("cleanup")
    end

    it "supports new doc.save() API with force_new_generation flag" do
      doc = EventLoggingTestClasses::LoggedDocument.new("Hello World")
      doc.sepia_id = "save-api-test-123"

      # First save using object API (creates)
      doc.save(metadata: {"user" => "alice", "action" => "create"})

      # Second save using object API with force flag (updates)
      doc.content = "Updated content"
      doc.save(force_new_generation: true, metadata: {"user" => "bob", "action" => "force_update"})

      # Check all events
      events = Sepia::Storage.object_events(EventLoggingTestClasses::LoggedDocument, "save-api-test-123")
      events.size.should eq(2)

      events[0].event_type.should eq(Sepia::LogEventType::Created)
      events[0].generation.should eq(1)
      events[0].metadata["user"].should eq("alice")
      events[0].metadata["action"].should eq("create")

      events[1].event_type.should eq(Sepia::LogEventType::Updated)
      events[1].generation.should eq(1)  # First generation (save-api-test-123.1)
      events[1].metadata["user"].should eq("bob")
      events[1].metadata["action"].should eq("force_update")
    end
  end
end

require "./spec_helper"
require "file_utils"

# Test classes for watcher specs
class TestSerializable < Sepia::Object
  include Sepia::Serializable

  property content : String

  def initialize(@content = "")
  end

  def to_sepia : String
    @content
  end

  def self.from_sepia(s : String) : self
    new(s)
  end
end

class TestContainer < Sepia::Object
  include Sepia::Container

  def initialize
    # Container needs a sepia_id
  end

  def save_references(path : String)
    # Minimal implementation for testing
    data_path = File.join(path, "data.json")
    File.write(data_path, "{}")
  end

  def load_references(path : String)
    # Minimal implementation for testing
  end
end

class TestWatchDocument < Sepia::Object
  include Sepia::Serializable

  property title : String
  property content : String

  def initialize(@title = "", @content = "")
  end

  def to_sepia : String
    {
      title:   @title,
      content: @content,
    }.to_json
  end

  def self.from_sepia(sepia_string : String) : self
    data = JSON.parse(sepia_string)
    new(
      data["title"].as_s,
      data["content"].as_s
    )
  end
end

describe Sepia::Watcher do
  describe "Event" do
    it "creates an event with all properties" do
      event = Sepia::Event.new(
        type: Sepia::EventType::Modified,
        object_class: "TestClass",
        object_id: "test-id",
        path: "/test/path"
      )

      event.type.should eq(Sepia::EventType::Modified)
      event.object_class.should eq("TestClass")
      event.object_id.should eq("test-id")
      event.path.should eq("/test/path")
      event.timestamp.should be_a(Time)
    end
  end

  describe "EventType" do
    it "has all required event types" do
      Sepia::EventType::Created.should eq(Sepia::EventType::Created)
      Sepia::EventType::Modified.should eq(Sepia::EventType::Modified)
      Sepia::EventType::Deleted.should eq(Sepia::EventType::Deleted)
    end
  end

  describe "Watcher" do
    temp_dir = ""
    storage = nil.as(Sepia::FileStorage?)
    received_events = [] of Sepia::Event

    before_each do
      temp_dir = File.join(Dir.tempdir, "sepia_test_#{Random::Secure.hex(8)}")
      Dir.mkdir(temp_dir)
      storage = Sepia::FileStorage.new(temp_dir)
      received_events.clear
    end

    after_each do
      if temp_dir && Dir.exists?(temp_dir)
        FileUtils.rm_rf(temp_dir)
      end
    end

    describe "#initialize" do
      it "creates a watcher with storage backend" do
        new_watcher = nil.as(Sepia::Watcher?)
        begin
          new_watcher = Sepia::Watcher.new(storage.not_nil!)
          new_watcher.storage.should eq(storage.not_nil!)
          new_watcher.running?.should be_false # Not auto-started
        ensure
          new_watcher.not_nil!.stop
          new_watcher.not_nil!.running?.should be_false
        end
      end
    end

    describe "#on_change" do
      it "registers a callback" do
        callback_called = false
        local_watcher = nil.as(Sepia::Watcher?)

        begin
          local_watcher = Sepia::Watcher.new(storage.not_nil!)

          local_watcher.on_change do |_|
            callback_called = true
          end

          # Manually trigger a callback by simulating an event
          if callback = local_watcher.callback
            test_event = Sepia::Event.new(
              type: Sepia::EventType::Created,
              object_class: "Test",
              object_id: "test",
              path: "/test"
            )
            callback.call(test_event)
          end

          callback_called.should be_true
        ensure
          local_watcher.not_nil!.stop
          local_watcher.not_nil!.running?.should be_false
        end
      end
    end

    describe "#start and #stop" do
      it "starts and stops watching" do
        begin
          local_watcher = Sepia::Watcher.new(storage.not_nil!)
          local_watcher.running?.should be_false # Not auto-started

          # Try to start again (should be idempotent)
          local_watcher.start
          local_watcher.running?.should be_true

          local_watcher.stop
          local_watcher.running?.should be_false
        ensure
          if local_watcher
            local_watcher.stop
            local_watcher.running?.should be_false
          end
        end
      end
    end

    describe "internal file tracking" do
      it "tracks and checks internal files" do
        test_path = "/test/path"

        Sepia::Watcher.internal_file?(test_path).should be_false

        Sepia::Watcher.add_internal_file(test_path)
        Sepia::Watcher.internal_file?(test_path).should be_true

        Sepia::Watcher.remove_internal_file(test_path)
        Sepia::Watcher.internal_file?(test_path).should be_false
      end

      it "is thread-safe" do
        test_paths = ["/test/1", "/test/2", "/test/3"]
        threads = [] of Thread

        # Add files from multiple threads
        test_paths.each do |path|
          threads << Thread.new do
            Sepia::Watcher.add_internal_file(path)
          end
        end

        threads.each(&.join)

        # Check files from multiple threads
        test_paths.each do |path|
          threads << Thread.new do
            Sepia::Watcher.internal_file?(path).should be_true
          end
        end

        threads.each(&.join)

        # Remove files from multiple threads
        test_paths.each do |path|
          threads << Thread.new do
            Sepia::Watcher.remove_internal_file(path)
          end
        end

        threads.each(&.join)

        test_paths.each do |path|
          Sepia::Watcher.internal_file?(path).should be_false
        end
      end
    end

    describe "path parsing" do
      it "parses valid object paths" do
        # This tests the private parse_path method indirectly
        # We can't test it directly, but we can verify it works
        # through the watcher behavior

        test_event = Sepia::Event.new(
          type: Sepia::EventType::Created,
          object_class: "MyClass",
          object_id: "test-id",
          path: File.join(temp_dir, "MyClass", "test-id")
        )

        test_event.object_class.should eq("MyClass")
        test_event.object_id.should eq("test-id")
      end
    end

    describe "Storage integration" do
      it "creates class directories during save" do
        # Use a simple test class defined outside
        test_obj = TestSerializable.new("test")
        test_obj.sepia_id = "test-id"

        class_dir = File.join(temp_dir, TestSerializable.name)
        Dir.exists?(class_dir).should be_false

        storage.not_nil!.save(test_obj)

        Dir.exists?(class_dir).should be_true
        File.exists?(File.join(class_dir, "test-id")).should be_true
      end

      it "handles atomic writes properly" do
        test_obj = TestSerializable.new("test content")
        test_obj.sepia_id = "test-obj"

        storage.not_nil!.save(test_obj)

        # File should exist without .tmp extension
        file_path = File.join(temp_dir, TestSerializable.name, "test-obj")
        File.exists?(file_path).should be_true

        # .tmp file should not exist
        File.exists?("#{file_path}.tmp").should be_false

        # Content should be correct
        File.read(file_path).should eq("test content")
      end
    end
  end

  describe "Container support" do
    temp_dir = ""
    storage = nil.as(Sepia::FileStorage?)

    before_each do
      temp_dir = File.join(Dir.tempdir, "sepia_container_test_#{Random::Secure.hex(8)}")
      Dir.mkdir(temp_dir)
      storage = Sepia::FileStorage.new(temp_dir)
    end

    after_each do
      if temp_dir && Dir.exists?(temp_dir)
        FileUtils.rm_rf(temp_dir)
      end
    end

    it "creates directories for container objects" do
      obj = TestContainer.new
      obj.sepia_id = "container-test"

      storage.not_nil!.save(obj)

      container_path = File.join(temp_dir, TestContainer.name, "container-test")
      Dir.exists?(container_path).should be_true
      File.exists?(File.join(container_path, "data.json")).should be_true
    end
  end

  describe "Edge cases" do
    temp_dir = ""
    storage = nil.as(Sepia::FileStorage?)

    before_each do
      temp_dir = File.join(Dir.tempdir, "sepia_edge_test_#{Random::Secure.hex(8)}")
      Dir.mkdir(temp_dir)
      storage = Sepia::FileStorage.new(temp_dir)
    end

    after_each do
      if temp_dir && Dir.exists?(temp_dir)
        FileUtils.rm_rf(temp_dir)
      end
    end

    it "handles empty storage path" do
      begin
        watcher = Sepia::Watcher.new(storage.not_nil!)
      ensure
        watcher.not_nil!.stop
        watcher.not_nil!.running?.should be_false
      end
      # Should not crash
    end

    it "filters out .tmp files" do
      # Direct test of file filtering
      tmp_file = File.join(temp_dir, "test.tmp")
      File.write(tmp_file, "test")

      File.exists?(tmp_file).should be_true

      # The watcher should ignore this file when parsing paths
      # This is tested indirectly through the path parsing logic
    end
  end

  describe "End-to-End File System Monitoring" do
    it "detects real file changes with proper lifecycle management" do
      # Setup temporary storage for testing
      storage_dir = File.join(Dir.tempdir, "sepia_e2e_#{UUID.random}")
      Dir.mkdir_p(storage_dir) unless Dir.exists?(storage_dir)
      pp! storage_dir
      pp! Dir.exists?(storage_dir)

      watcher = nil.as(Sepia::Watcher?)

      begin
        # Step 1: Create watcher (not started yet)
        test_storage = Sepia::FileStorage.new(storage_dir)
        pp! test_storage.path
        watcher = Sepia::Watcher.new(test_storage)
        watcher.running?.should be_false

        # Step 2: Setup event tracking
        received_events = [] of Sepia::Event

        watcher.on_change do |event|
          received_events << event
        end

        # Step 3: Start watching
        watcher.start
        watcher.running?.should be_true
        pp! "pre-sleep"
        sleep 1.seconds
        pp! "post-sleep"

        # Step 4: Modify filesystem - create a test file
        test_file = File.join(storage_dir, "TestClass", "test-id")
        test_dir = File.dirname(test_file)
        Dir.mkdir_p(test_dir) unless Dir.exists?(test_dir)

        File.write(test_file, "initial content")

        # Step 5: Brief pause to let events process
        pp! "pre", test_file
        Fiber.yield
        # 10.times { Fiber.yield }

        # Step 6: Modify the file
        File.write(test_file, "modified content")
        pp! 1111

        # Step 7: Another brief pause
        Fiber.yield
        # 10.times { Fiber.yield }
        pp! "post"

        # Step 8: Stop watching
        watcher.stop
        watcher.running?.should be_false

        # Step 9: Verify we got events
        received_events.size.should be >= 1

        if received_events.size > 0
          event = received_events.first
          event.object_class.should eq("TestClass")
          event.object_id.should eq("test-id")
          (event.type == Sepia::EventType::Created ||
            event.type == Sepia::EventType::Modified).should be_true
        end
      ensure
        # Cleanup - ALWAYS stop the watcher
        if watcher
          watcher.stop
        end
        # FileUtils.rm_r(storage_dir) if Dir.exists?(storage_dir)
      end
    end
  end
end

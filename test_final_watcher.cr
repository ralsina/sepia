require "json"
require "./src/sepia/watcher"
require "./src/sepia/file_storage"
require "./src/sepia/serializable"
require "./src/sepia/object"
require "file_utils"

# Test class for the final watcher
class TestDocument < Sepia::Object
  include Sepia::Serializable

  property title : String
  property content : String

  def initialize(@title = "", @content = "")
  end

  def to_sepia : String
    {
      "title"   => @title,
      "content" => @content,
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

puts "Testing final integrated Sepia Watcher..."

# Create temporary directory
storage_dir = File.join(Dir.tempdir, "sepia_final_test_#{Random::Secure.hex(8)}")
Dir.mkdir_p(storage_dir)
puts "Created temp dir: #{storage_dir}"

begin
  # Create storage and watcher
  storage = Sepia::FileStorage.new(storage_dir)
  watcher = Sepia::Watcher.new(storage)

  puts "Watcher created, running: #{watcher.running?}"
  puts "Path resolver: #{watcher.path_resolver.class.name}"

  # Setup event tracking
  received_events = [] of Sepia::Event

  watcher.on_change do |event|
    puts "Received event: #{event.type} #{event.object_class}:#{event.object_id}"
    puts "  Path: #{event.path}"

    if info = event.object_info?
      puts "  Container?: #{info.container?}"
      puts "  Serializable?: #{info.serializable?}"
    end

    received_events << event
  end

  # Start watching
  puts "Starting watcher..."
  watcher.start
  puts "Watcher running: #{watcher.running?}"

  # Give the watcher a moment to start
  sleep 0.1.seconds
  puts "Watcher started successfully"

  # Test 1: Create a document
  puts "\n=== Test 1: Creating document ==="
  doc = TestDocument.new("Test Doc", "Initial content")
  doc.sepia_id = "test-doc-1"
  storage.save(doc)

  # Give event processing a moment
  sleep 0.1.seconds
  puts "Document created, events received: #{received_events.size}"

  # Test 2: Load the object from the event
  if received_events.size > 0
    event = received_events.last
    puts "\n=== Test 2: Loading object from event ==="
    loaded_obj = event.object(TestDocument)
    if loaded_obj
      puts "✅ Successfully loaded object from event!"
      puts "  Class: #{loaded_obj.class.name}"
      puts "  ID: #{loaded_obj.sepia_id}"
      if loaded_obj.is_a?(TestDocument)
        puts "  Title: #{loaded_obj.title}"
        puts "  Content: #{loaded_obj.content}"
      end
    else
      puts "❌ Failed to load object from event"
    end
  end

  # Test 3: Modify the document
  puts "\n=== Test 3: Modifying document ==="
  doc.content = "Modified content"
  storage.save(doc)

  # Give event processing a moment
  sleep 0.1.seconds
  puts "Document modified, total events: #{received_events.size}"

  # Test 4: Delete the document
  puts "\n=== Test 4: Deleting document ==="
  storage.delete(doc)

  # Give event processing a moment
  sleep 0.1.seconds
  puts "Document deleted, total events: #{received_events.size}"

  # Stop the watcher
  puts "\n=== Stopping watcher ==="
  watcher.stop
  puts "Watcher running: #{watcher.running?}"

  # Verify events
  puts "\n=== Results ==="
  puts "Total events received: #{received_events.size}"

  received_events.each_with_index do |event, index|
    puts "#{index + 1}. #{event.type} #{event.object_class}:#{event.object_id} at #{event.path}"
  end

  # Expected: create, modify, delete events
  if received_events.size >= 3
    puts "✅ Final Watcher test PASSED: Received expected events"
  else
    puts "❌ Final Watcher test FAILED: Expected at least 3 events, got #{received_events.size}"
  end
rescue ex
  puts "Error: #{ex.message}"
  puts ex.backtrace.join("\n")
ensure
  # Cleanup
  if watcher
    watcher.stop
  end
  if Dir.exists?(storage_dir)
    FileUtils.rm_rf(storage_dir)
    puts "Cleaned up temp dir"
  end
end

puts "\nFinal Watcher test completed!"

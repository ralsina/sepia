require "json"
require "./src/sepia/watcher"
require "./src/sepia/file_storage"
require "./src/sepia/serializable"
require "./src/sepia/object"
require "file_utils"

# Simple test class for our new watcher
class TestDocument < Sepia::Object
  include Sepia::Serializable

  property title : String
  property content : String

  def initialize(@title = "", @content = "")
  end

  def to_sepia : String
    {
      "title" => @title,
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

puts "Testing new Watcher implementation..."

# Create temporary directory
storage_dir = File.join(Dir.tempdir, "sepia_new_watcher_test_#{Random::Secure.hex(8)}")
Dir.mkdir_p(storage_dir)
puts "Created temp dir: #{storage_dir}"

begin
  # Create storage and watcher
  storage = Sepia::FileStorage.new(storage_dir)
  watcher = Sepia::Watcher.new(storage)

  puts "Watcher created, running: #{watcher.running?}"

  # Setup event tracking
  received_events = [] of Sepia::Event

  watcher.on_change do |event|
    puts "Received event: #{event.type} #{event.object_class}:#{event.object_id}"
    received_events << event
  end

  puts "Starting watcher..."
  watcher.start
  puts "Watcher running: #{watcher.running?}"

  # Give the watcher a moment to start
  sleep 0.1.seconds
  puts "Watcher started successfully"

  # Test 1: Create a document
  puts "Creating document..."
  doc = TestDocument.new("Test Doc", "Initial content")
  doc.sepia_id = "test-doc-1"
  storage.save(doc)

  # Give event processing a moment
  sleep 0.1.seconds
  puts "Document created, events received: #{received_events.size}"

  # Test 2: Modify the document
  puts "Modifying document..."
  doc.content = "Modified content"
  storage.save(doc)

  # Give event processing a moment
  sleep 0.1.seconds
  puts "Document modified, events received: #{received_events.size}"

  # Test 3: Delete the document
  puts "Deleting document..."
  storage.delete(doc)

  # Give event processing a moment
  sleep 0.1.seconds
  puts "Document deleted, events received: #{received_events.size}"

  # Stop the watcher
  puts "Stopping watcher..."
  watcher.stop
  puts "Watcher running: #{watcher.running?}"

  # Verify events
  puts "\n=== Results ==="
  puts "Total events received: #{received_events.size}"

  received_events.each_with_index do |event, index|
    puts "#{index + 1}. #{event.type} #{event.object_class}:#{event.object_id} at #{event.path}"
  end

  # Expected: at least create, modify, delete events
  if received_events.size >= 3
    puts "✅ Test PASSED: Received expected events"
  else
    puts "❌ Test FAILED: Expected at least 3 events, got #{received_events.size}"
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

puts "Test completed!"
require "json"
require "./src/sepia/file_storage"
require "./src/sepia/serializable"
require "./src/sepia/object"
require "file_utils"
require "inotify"

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

puts "Testing simple Sepia file system watching..."

# Create temporary directory
storage_dir = File.join(Dir.tempdir, "sepia_simple_test_#{Random::Secure.hex(8)}")
Dir.mkdir_p(storage_dir)
puts "Created temp dir: #{storage_dir}"

begin
  # Create storage
  storage = Sepia::FileStorage.new(storage_dir)

  # Create event channel (following inotify library pattern)
  event_channel = Channel(String).new

  # Start watching the directory with recursive watching
  puts "Starting directory watcher..."
  watcher = Inotify.watch(storage_dir, recursive: true) do |event|
    puts "Raw inotify event: #{event.type} name=#{event.name}"
    # Filter for our test document events (either TestDocument directory or test-doc-1 file)
    name = event.name
    if name && (name.includes?("TestDocument") || name.includes?("test-doc-1"))
      event_channel.send("Event: #{event.type} name=#{name}")
    end
  end
  puts "Watcher started!"

  # Test 1: Create a document
  puts "Creating document..."
  doc = TestDocument.new("Test Doc", "Initial content")
  doc.sepia_id = "test-doc-1"
  storage.save(doc)

  # Wait for events
  puts "Waiting for creation event..."
  event1 = event_channel.receive
  puts "Received: #{event1}"

  # Test 2: Modify the document
  puts "Modifying document..."
  doc.content = "Modified content"
  storage.save(doc)

  # Wait for events
  puts "Waiting for modification event..."
  event2 = event_channel.receive
  puts "Received: #{event2}"

  # Test 3: Delete the document
  puts "Deleting document..."
  storage.delete(doc)

  # Wait for events
  puts "Waiting for deletion event..."
  event3 = event_channel.receive
  puts "Received: #{event3}"

  # Clean up
  puts "Stopping watcher..."
  watcher.close
  event_channel.close

  puts "Simple Sepia watcher test completed successfully!"

rescue ex
  puts "Error: #{ex.message}"
  puts ex.backtrace.join("\n")
ensure
  # Cleanup
  if Dir.exists?(storage_dir)
    FileUtils.rm_rf(storage_dir)
    puts "Cleaned up temp dir"
  end
end
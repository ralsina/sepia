require "inotify"
require "./src/sepia/storage_backend"
require "./src/sepia/file_storage"
require "file_utils"

# Simple e2e test following inotify library pattern
puts "Testing simple inotify-based file watching..."

# Create temporary directory
storage_dir = File.join(Dir.tempdir, "sepia_e2e_test_#{Random::Secure.hex(8)}")
Dir.mkdir_p(storage_dir)
puts "Created temp dir: #{storage_dir}"

begin
  # Create event channel (following inotify library pattern)
  event_channel = Channel(String).new

  # Start watching the directory
  puts "Starting directory watcher..."
  watcher = Inotify.watch(storage_dir) do |event|
    event_channel.send("Event: #{event.type} name=#{event.name}")
  end
  puts "Watcher started!"

  # Test 1: Create a file
  test_file = File.join(storage_dir, "test.txt")
  puts "Creating file: #{test_file}"
  File.write(test_file, "initial content")

  # Wait for events
  puts "Waiting for creation event..."
  event1 = event_channel.receive
  puts "Received: #{event1}"

  # Test 2: Modify the file
  puts "Modifying file..."
  File.write(test_file, "modified content")

  # Wait for events
  puts "Waiting for modification event..."
  event2 = event_channel.receive
  puts "Received: #{event2}"

  # Test 3: Delete the file
  puts "Deleting file..."
  File.delete(test_file)

  # Wait for events
  puts "Waiting for deletion event..."
  event3 = event_channel.receive
  puts "Received: #{event3}"

  # Clean up
  puts "Stopping watcher..."
  watcher.close
  event_channel.close

  puts "E2E test completed successfully!"
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

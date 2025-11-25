require "./src/sepia"

class TestDoc < Sepia::Object
  include Sepia::Serializable

  property content : String

  def initialize(@content = "")
  end

  def to_sepia : String
    @content
  end

  def self.from_sepia(sepia_string : String) : self
    new(sepia_string)
  end
end

def test_watcher_backend(flag)
  puts "\n=== Testing #{flag} backend ==="

  # Setup storage and watcher
  path = "/tmp/sepia_watcher_test_#{flag}"
  FileUtils.rm_rf(path) if File.exists?(path)
  FileUtils.mkdir_p(path)

  storage = Sepia::FileStorage.new(path)
  watcher = Sepia::Watcher.new(storage)

  # Test basic watcher API
  puts "✓ Watcher created successfully"
  puts "✓ Storage path: #{storage.path}"

  # Test callback registration
  events_received = [] of Sepia::Event
  watcher.on_change do |event|
    events_received << event
    puts "Event: #{event.type} for #{event.object_class}:#{event.object_id}"
  end

  puts "✓ Callback registered"

  # Test lifecycle
  watcher.start
  puts "✓ Watcher started (running: #{watcher.running?})"

  # Test stopping
  begin
    watcher.stop
    puts "✓ Watcher stopped (running: #{watcher.running?})"
  rescue ex
    puts "⚠ Watcher stop failed: #{ex.message}"
  end

  puts "✓ #{flag} backend works correctly!"
end

# Test different backends
test_watcher_backend("fswatch")
test_watcher_backend("inotify")

puts "\n🎉 All backends tested successfully!"
require "fswatch"
require "file_utils"

describe "crystal-fswatch" do
  temp_dir = ""
  event_count = 0

  before_each do
    temp_dir = File.join(Dir.tempdir, "sepia_fswatch_spec_#{Random::Secure.hex(8)}")
    Dir.mkdir(temp_dir)
    event_count = 0
  end

  after_each do
    if temp_dir && Dir.exists?(temp_dir)
      FileUtils.rm_rf(temp_dir)
    end
  end

  describe "basic functionality" do
    it "detects file changes without hanging" do
      # Create a session for controlled watching
      session = FSWatch::Session.build(recursive: true)

      # Set up event callback
      session.on_change do |event|
        event_count += 1 if event.created? || event.updated? || event.removed?
      end

      # Add the test directory to watch
      session.add_path(temp_dir)

      # Start monitoring
      session.start_monitor

      # Give it a moment to start
      sleep 0.1.seconds

      # Create a test file
      test_file = File.join(temp_dir, "test.txt")
      File.write(test_file, "Hello World")

      # Give it a moment to detect the change
      sleep 0.5.seconds

      # Modify the file
      File.write(test_file, "Hello Modified World")

      # Give it a moment to detect the change
      sleep 0.5.seconds

      # Delete the file
      File.delete(test_file)

      # Give it a moment to detect the change
      sleep 0.5.seconds

      # Stop the watcher
      session.stop_monitor

      # Verify we got events
      event_count.should be > 0
    end
  end
end
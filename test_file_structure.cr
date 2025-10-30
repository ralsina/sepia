require "json"
require "./src/sepia/file_storage"
require "./src/sepia/serializable"
require "./src/sepia/object"
require "file_utils"

# Simple test class
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

puts "Testing Sepia file structure..."

# Create temporary directory
storage_dir = File.join(Dir.tempdir, "sepia_structure_test_#{Random::Secure.hex(8)}")
Dir.mkdir_p(storage_dir)
puts "Created temp dir: #{storage_dir}"

begin
  # Create storage
  storage = Sepia::FileStorage.new(storage_dir)

  # Test 1: Create a document
  puts "Creating document..."
  doc = TestDocument.new("Test Doc", "Initial content")
  doc.sepia_id = "test-doc-1"
  storage.save(doc)

  # Check what files were created
  puts "Directory structure:"
  puts `find #{storage_dir} -type f`

  puts "File structure test completed successfully!"

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
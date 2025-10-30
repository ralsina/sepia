require "json"
require "./src/sepia/path_resolver"
require "./src/sepia/file_storage"
require "./src/sepia/serializable"
require "./src/sepia/object"
require "file_utils"

# Test class for resolver
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

# Another test class
class TestNote < Sepia::Object
  include Sepia::Serializable

  property content : String

  def initialize(@content = "")
  end

  def to_sepia : String
    {
      "content" => @content,
    }.to_json
  end

  def self.from_sepia(sepia_string : String) : self
    data = JSON.parse(sepia_string)
    new(data["content"].as_s)
  end
end

puts "Testing Sepia PathResolver..."

# Create temporary directory
storage_dir = File.join(Dir.tempdir, "sepia_resolver_test_#{Random::Secure.hex(8)}")
Dir.mkdir_p(storage_dir)
puts "Created temp dir: #{storage_dir}"

begin
  # Create storage
  storage = Sepia::FileStorage.new(storage_dir)
  resolver = Sepia::PathResolver.new(storage_dir)

  # Test 1: Create and resolve a Serializable object
  puts "\n=== Test 1: Serializable Object ==="
  doc = TestDocument.new("Test Doc", "Initial content")
  doc.sepia_id = "test-doc-1"
  storage.save(doc)

  expected_path = File.join(storage_dir, "TestDocument", "test-doc-1")
  puts "File created at: #{expected_path}"
  puts "File exists: #{File.exists?(expected_path)}"

  # Resolve the path
  info = resolver.resolve_path(expected_path)
  if info
    puts "✅ Path resolved successfully:"
    puts "  Class name: #{info.class_name}"
    puts "  Object ID: #{info.object_id}"
    puts "  Full path: #{info.full_path}"
    puts "  Serializable?: #{info.serializable?}"
    puts "  Container?: #{info.container?}"

    # Try to get the object class
    klass = info.object_class
    puts "  Object class: #{klass}"

    # Try to load the object
    obj = info.object
    if obj
      puts "✅ Object loaded successfully:"
      puts "  Loaded class: #{obj.class.name}"
      puts "  Loaded ID: #{obj.sepia_id}"
      if obj.is_a?(TestDocument)
        puts "  Title: #{obj.title}"
        puts "  Content: #{obj.content}"
      end
    else
      puts "❌ Failed to load object"
    end
  else
    puts "❌ Failed to resolve path"
  end

  # Test 2: Create and resolve another Serializable object
  puts "\n=== Test 2: Second Serializable Object ==="
  note = TestNote.new("This is a note")
  note.sepia_id = "note-1"
  storage.save(note)

  note_path = File.join(storage_dir, "TestNote", "note-1")
  puts "Note created at: #{note_path}"
  puts "File exists: #{File.exists?(note_path)}"

  # Resolve the note path
  note_info = resolver.resolve_path(note_path)
  if note_info
    puts "✅ Note path resolved successfully:"
    puts "  Class name: #{note_info.class_name}"
    puts "  Object ID: #{note_info.object_id}"
    puts "  Serializable?: #{note_info.serializable?}"
    puts "  Container?: #{note_info.container?}"

    # Try to load the note
    loaded_note = note_info.object
    if loaded_note
      puts "✅ Note loaded successfully:"
      puts "  Loaded class: #{loaded_note.class.name}"
      if loaded_note.is_a?(TestNote)
        puts "  Content: #{loaded_note.content}"
      end
    else
      puts "❌ Failed to load note"
    end
  else
    puts "❌ Failed to resolve note path"
  end

  # Test 3: List all objects
  puts "\n=== Test 3: List All Objects ==="
  all_objects = resolver.list_all_objects
  puts "Found #{all_objects.size} objects:"
  all_objects.each do |obj_info|
    puts "  #{obj_info.class_name}: #{obj_info.object_id} (#{obj_info.container? ? "Container" : "Serializable"})"
  end

  # Test 4: Invalid paths
  puts "\n=== Test 4: Invalid Paths ==="
  invalid_paths = [
    "/outside/storage/path",
    File.join(storage_dir, "NonExistentClass", "id"),
    File.join(storage_dir, "IncompletePath"),
  ]

  invalid_paths.each do |path|
    result = resolver.valid_sepia_path?(path)
    puts "  #{path}: #{result ? "✅ Valid" : "❌ Invalid"}"
  end

  # Test 5: Convenience method
  puts "\n=== Test 5: Convenience Method ==="
  loaded_obj = resolver.resolve_and_load(expected_path)
  if loaded_obj
    puts "✅ resolve_and_load worked: #{loaded_obj.class.name}"
  else
    puts "❌ resolve_and_load failed"
  end

  puts "\n=== PathResolver test completed successfully! ==="

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
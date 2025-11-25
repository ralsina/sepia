require "./src/sepia"

# Test classes for backup functionality
class TestDocument < Sepia::Object
  include Sepia::Serializable

  property title : String
  property content : String

  def initialize(@title = "", @content = "")
  end

  def to_sepia : String
    "#{@title}\n#{@content}"
  end

  def self.from_sepia(sepia_string : String) : self
    lines = sepia_string.split('\n', 2)
    title = lines[0]? || ""
    content = lines[1]? || ""
    new(title, content)
  end
end

class TestProject < Sepia::Object
  include Sepia::Container

  property name : String
  property documents : Array(TestDocument)

  def initialize(@name = "")
    @documents = [] of TestDocument
  end
end

# Setup test storage
storage_dir = "/tmp/sepia_backup_test_#{Time.utc.to_unix}"
Dir.mkdir_p(storage_dir)
Sepia::Storage.backend = Sepia::FileStorage.new(storage_dir)

puts "Creating test objects..."

# Create test objects
doc1 = TestDocument.new("First Document", "This is the first document content")
doc1.sepia_id = "doc1"
doc1.save

doc2 = TestDocument.new("Second Document", "This is the second document content")
doc2.sepia_id = "doc2"
doc2.save

project = TestProject.new("Test Project")
project.sepia_id = "project1"
project.documents << doc1
project.documents << doc2
project.save

puts "Test objects created:"
puts "- Document 1: #{doc1.title} (#{doc1.sepia_id})"
puts "- Document 2: #{doc2.title} (#{doc2.sepia_id})"
puts "- Project: #{project.name} (#{project.sepia_id})"

# Test backup creation
puts "\nCreating backup..."
backup_path = File.join(Dir.tempdir, "test_backup.sepia.tar")

begin
  result_path = Sepia::Backup.create([project], backup_path)
  puts "✓ Backup created successfully: #{result_path}"

  # Check if backup file exists and has content
  if File.exists?(result_path) && File.size(result_path) > 0
    backup_size = File.size(result_path)
    puts "✓ Backup file size: #{backup_size} bytes"
  else
    puts "✗ Backup file is empty or missing"
    exit 1
  end

  # List backup contents with tar command
  puts "\nBackup contents:"
  system("tar -tf #{result_path}") || puts("(tar command not available)")

rescue ex
  puts "✗ Backup failed: #{ex.message}"
  puts ex.backtrace.join("\n")
  exit 1
end

# Examine backup contents
puts "\nExamining backup structure..."
system("echo 'Backup file list:' && tar -tf #{backup_path} | head -10")
system("echo 'Backup metadata:' && tar -xf #{backup_path} metadata.json -O 2>/dev/null || echo 'Could not extract metadata'")

# Cleanup
puts "\nCleaning up..."
FileUtils.rm_rf(storage_dir) if Dir.exists?(storage_dir)
File.delete(backup_path) if File.exists?(backup_path)

puts "\n🎉 Backup test completed successfully!"
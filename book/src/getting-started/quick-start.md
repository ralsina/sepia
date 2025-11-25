# Quick Start

This guide will get you up and running with Sepia in just a few minutes. We'll create a simple document management system to demonstrate the core concepts.

## Step 1: Define Your Objects

Let's create a simple `Document` class that can be saved and loaded:

```crystal
require "sepia"

class Document < Sepia::Object
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
    new(lines[0]? || "", lines[1]? || "")
  end
end
```

## Step 2: Configure Storage

```crystal
# Configure Sepia to use the filesystem backend
Sepia::Storage.configure(:filesystem, {"path" => "./data"})
```

## Step 3: Save and Load Objects

```crystal
# Create a new document
doc = Document.new("My First Document", "Hello, Sepia!")
doc.save  # Automatically generates a unique ID

puts "Document saved with ID: #{doc.sepia_id}"

# Load it back
loaded_doc = Sepia::Storage.get(Document, doc.sepia_id).as(Document)
puts "Loaded title: #{loaded_doc.title}"
puts "Loaded content: #{loaded_doc.content}"
```

## Step 4: Try Container Objects

Container objects can contain other objects. Let's create a `Folder`:

```crystal
class Folder < Sepia::Object
  include Sepia::Container

  property name : String
  property description : String?
  property documents : Array(Document)

  def initialize(@name = "", @description = nil)
    @documents = [] of Document
  end
end

# Create a folder with documents
folder = Folder.new("Important Docs", "My important documents")

doc1 = Document.new("Meeting Notes", "Discussed project timeline")
doc1.sepia_id = "meeting-notes"
doc1.save

doc2 = Document.new("Todo List", "- Review code\n- Write docs")
doc2.sepia_id = "todo-list"
doc2.save

folder.documents << doc1 << doc2
folder.sepia_id = "important-docs"
folder.save

puts "Folder saved with #{folder.documents.size} documents"
```

## Step 5: File System Watching

Sepia can detect when files are changed externally:

```crystal
# Set up a watcher
storage = Sepia::Storage.backend.as(Sepia::FileStorage)
watcher = Sepia::Watcher.new(storage)

watcher.on_change do |event|
  puts "Detected change: #{event.type} - #{event.object_class}:#{event.object_id}"

  # Reload the object if it was modified
  if event.type.modified?
    begin
      obj = Sepia::Storage.load(event.object_class.constantize(typeof(Object)), event.object_id)
      puts "Reloaded: #{obj}"
    rescue ex
      puts "Failed to reload: #{ex.message}"
    end
  end
end

# Start watching
watcher.start

# Now try editing one of the document files manually:
# ./data/Document/meeting-notes
# You should see the watcher detect the change!

# Stop watching when done
# watcher.stop
```

## Step 6: Backup Your Data

Sepia makes it easy to create backups:

```crystal
# Backup a specific object
backup_path = doc.backup_to("my_document_backup.tar")
puts "Backup created: #{backup_path}"

# Backup multiple objects
backup_path = Sepia::Storage.backup([doc1, doc2, folder], "project_backup.tar")
puts "Project backup created: #{backup_path}"

# Inspect backup contents
manifest = Sepia::Backup.list_contents("project_backup.tar")
puts "Backup contains #{manifest.all_objects.values.map(&.size).sum} objects"

# Verify backup integrity
result = Sepia::Backup.verify("project_backup.tar")
puts "Backup is #{result.valid ? "valid" : "invalid"}"
```

## Complete Example

Here's a complete working example:

```crystal
require "sepia"

class Document < Sepia::Object
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
    new(lines[0]? || "", lines[1]? || "")
  end
end

# Configure storage
Sepia::Storage.configure(:filesystem, {"path" => "./quickstart_data"})

# Create and save a document
doc = Document.new("Welcome to Sepia", "This is your first persistent object!")
doc.save

puts "✅ Document saved!"
puts "   Title: #{doc.title}"
puts "   ID: #{doc.sepia_id}"

# Load it back
loaded = Sepia::Storage.get(Document, doc.sepia_id).as(Document)
puts "✅ Document loaded!"
puts "   Title: #{loaded.title}"

# Create a backup
backup_path = doc.backup_to("welcome_backup.tar")
puts "✅ Backup created: #{backup_path}"

puts "\n🎉 Quick start completed!"
```

Save this as `quickstart.cr` and run:

```bash
crystal run quickstart.cr
```

## What's Next?

Now that you have the basics, explore these topics:

- [Serializable Objects](../user-guide/serializable.md) - Deep dive into file-based objects
- [Container Objects](../user-guide/containers.md) - Learn about complex object structures
- [File System Watching](../user-guide/file-watching.md) - Build reactive applications
- [Backup and Restore](../user-guide/backup.md) - Data protection strategies

Happy coding with Sepia! 🚀
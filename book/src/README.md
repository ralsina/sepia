# Sepia Documentation

📖 **Complete API Documentation**: <a href="https://ralsina.github.io/sepia/api/Sepia.html" target="_blank" rel="noopener noreferrer">https://ralsina.github.io/sepia/api/Sepia.html</a> (opens in new tab)

**Sepia** is a file-system-based serialization library for Crystal that provides intelligent object persistence with automatic filesystem watching and backup capabilities.

## What is Sepia?

Sepia allows you to save and load Crystal objects as files and directories on the filesystem, with automatic relationship tracking and change detection. It bridges the gap between in-memory objects and persistent storage without the complexity of traditional databases.

## Key Features

### 🗂️ **File System Storage**
- **Serializable Objects**: Store objects as individual files
- **Container Objects**: Store complex objects as directories with nested structures
- **Automatic Relationships**: Handles object references with symlinks
- **Canonical Storage**: Objects stored in consistent `ClassName/object_id` structure

### 👀 **File System Watching**
- **Real-time Monitoring**: Detect external file changes automatically
- **Multiple Backends**: Support for both fswatch and Linux inotify
- **Smart Filtering**: Eliminates self-generated events to prevent unnecessary callbacks
- **Thread-safe**: Concurrent access with proper synchronization

### 💾 **Backup Functionality**
- **Complete Backups**: Create tar archives of object trees with all relationships
- **Inspection Tools**: List contents and verify backup integrity
- **API Integration**: Simple backup methods from Storage and Object classes
- **Symlink Preservation**: Maintains object relationships in backups

### 🔄 **Generation Tracking**
- **Optimistic Concurrency**: Prevents lost updates with generation numbers
- **Conflict Detection**: Identifies concurrent modifications
- **Automatic Merging**: Smart handling of object relationships

## Why Use Sepia?

- **Simple Setup**: No database servers or migrations required
- **Human-readable**: Objects stored as plain files and directories
- **Development-friendly**: Easy to debug, backup, and version control
- **Real-time Updates**: Automatic detection of external file changes
- **Backup Ready**: Built-in backup and restore capabilities
- **Crystal Native**: Designed specifically for the Crystal ecosystem

## Quick Example

```crystal
require "sepia"

# Define a simple document
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
Sepia::Storage.configure(:filesystem, {"path" => "./data"})

# Create and save a document
doc = Document.new("My First Document", "Hello, Sepia!")
doc.save  # Automatically generates sepia_id

# Load it back
loaded = Sepia::Storage.get(Document, doc.sepia_id)
puts loaded.title  # "My First Document"
```

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  sepia:
    github: ralsina/sepia
```

Then run:
```bash
shards install
```

## Documentation Structure

This documentation is organized into several sections:

- **Getting Started**: Introduction, installation, and basic concepts
- **User Guide**: Comprehensive usage examples and feature explanations
- **API Reference**: Detailed API documentation
- **Advanced Topics**: Performance, troubleshooting, and advanced usage
- **Examples**: Real-world usage patterns and examples

## Requirements

- Crystal 1.16.3 or higher
- Optional: fswatch shard for cross-platform file system watching
- Optional: inotify.cr shard for Linux-native file system monitoring

---

**Sepia** makes file system persistence simple, reliable, and intelligent for Crystal applications.
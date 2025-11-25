# Generation Tracking

Generation tracking enables optimistic concurrency control and versioning of objects. This is particularly useful for collaborative applications where multiple users might edit the same data.

## Overview

Generation tracking allows you to:

- Track multiple versions of the same object
- Detect concurrent modifications
- Implement optimistic locking
- Maintain a complete history of changes
- Recover previous versions when needed

## How It Works

### ID Format

Objects are stored with IDs in the format: `{base_id}.{generation}`

- `base_id`: The unique identifier (typically a UUID)
- `generation`: Version number starting from 0

Example files on disk:
```
data/
  └── Note/
      ├── note-123e4567-e89b-12d3-a456-426614174000.0
      ├── note-123e4567-e89b-12d3-a456-426614174000.1
      └── note-123e4567-e89b-12d3-a456-426614174000.2
```

### Atomic Operations

Each `save_with_generation` creates a new file, ensuring:
- No data corruption during writes
- Previous versions remain intact
- Easy rollback to any version

## API Reference

### Instance Methods

#### `generation : Int32`
Returns the generation number extracted from the object's ID.

```crystal
note = Note.load("note-xxx.2")
note.generation  # => 2
```

#### `base_id : String`
Returns the base ID without the generation suffix.

```crystal
note = Note.load("note-xxx.2")
note.base_id  # => "note-xxx"
```

#### `save_with_generation : self`
Creates a new version with incremented generation number.

```crystal
note = Note.load("note-xxx.1")
new_note = note.save_with_generation
new_note.sepia_id  # => "note-xxx.2"
```

#### `stale?(expected_generation : Int32) : Bool`
Checks if a newer version exists.

```crystal
note = Note.load("note-xxx.1")
note.stale?(1)  # Returns true if note-xxx.2 exists
```

### Class Methods

#### `latest(base_id : String) : self?`
Returns the newest version of an object.

```crystal
latest = Note.latest("note-xxx")
latest.generation  # Highest generation number
```

#### `versions(base_id : String) : Array(self)`
Returns all versions sorted by generation.

```crystal
versions = Note.versions("note-xxx")
versions.map(&.generation)  # => [0, 1, 2, ...]
```

#### `exists?(id : String) : Bool`
Checks if an object with the given ID exists.

```crystal
Note.exists?("note-xxx.1")  # => true
Note.exists?("note-xxx.99") # => false
```

## Use Cases

### Collaborative Editing

```crystal
class Document < Sepia::Object
  include Sepia::Serializable

  property content : String
  property last_modified : Time

  # ... implement to_sepia/from_sepia
end

# When a user opens a document
doc = Document.load("doc-123.3")
user_generation = doc.generation

# When saving
if doc.stale?(user_generation)
  # Show merge dialog
  latest = Document.latest(doc.base_id)
  # Merge content
else
  doc.save_with_generation
end
```

### Version History

```crystal
# Show document history
versions = Document.versions("doc-123")
versions.each do |version|
  puts "Version #{version.generation}: #{version.last_modified}"
end

# Restore specific version
doc = Document.load("doc-123.2")
current = doc.save_with_generation  # Creates version 3 from version 2
```

### Audit Trail

```crystal
class LogEntry < Sepia::Object
  include Sepia::Serializable

  property action : String
  property user_id : String
  property timestamp : Time
  property data : String

  # ... serialization methods
end

# Each log change creates a new version
entry = LogEntry.new("update", "user1", Time.now, data_json)
entry.save_with_generation

# Query all changes
all_changes = LogEntry.versions("log-entry-456")
```

## Performance Considerations

### Storage Usage
- Each version consumes additional disk space
- Consider cleanup strategies for old versions

### Lookup Performance
- `latest()` scans all files to find highest generation
- Consider caching for frequently accessed objects

### Cleanup Strategies

```crystal
# Keep only last N versions
def keep_recent_versions(base_id, max_versions = 10)
  versions = MyClass.versions(base_id)
  if versions.size > max_versions
    versions[0..-(max_versions+1)].each(&:delete)
  end
end

# Keep versions newer than date
def keep_recent_by_date(base_id, cutoff_date = Time.now - 30.days)
  versions = MyClass.versions(base_id)
  versions.select { |v| v.saved_at < cutoff_date }.each(&:delete)
end
```

## Best Practices

1. **Always check for staleness** before saving in collaborative scenarios
2. **Use meaningful base IDs** that reflect the object's identity
3. **Implement cleanup** for long-running applications
4. **Handle merge conflicts** gracefully with user-friendly UI
5. **Consider using GenerationInfo module** to include generation data in JSON

## Migration from Non-Generation IDs

Existing objects without generation suffix automatically work:
- Treated as generation 0
- Can be versioned normally
- No migration required

```crystal
# Old code still works
old_obj = MyClass.load("old-id")
old_obj.generation  # => 0

# Start versioning
new_obj = old_obj.save_with_generation
new_obj.generation  # => 1
```
# Feature Request: Add Generation Numbers via ID for Optimistic Concurrency Control

## Summary

Add generation number tracking to Sepia by encoding the version in the object ID itself (e.g., `note-uuid.1`, `note-uuid.2`), enabling optimistic concurrency control, real-time updates, and conflict resolution while maintaining Sepia's simple file-based architecture.

## Problem Statement

When building collaborative applications (like ToCry with shared boards), developers need a reliable way to:
1. Track object versions across clients
2. Detect concurrent modifications
3. Resolve conflicts when multiple users edit the same data
4. Efficiently sync updates via WebSockets or other real-time mechanisms

Currently, Sepia doesn't provide built-in support for this. Traditional approaches adding a `generation` field to each object complicate the file-based persistence model.

## Proposed Solution

Leverage Sepia's ID-based architecture to encode generation numbers directly in the object ID, using the format: `{type}-{uuid}.{generation}`

### Examples:
- `note-123e4567-e89b-12d3-a456-426614174000.0` (initial version)
- `note-123e4567-e89b-12d3-a456-426614174000.1` (first update)
- `note-123e4567-e89b-12d3-a456-426614174000.2` (second update)

### Core API:

```crystal
class Note < Sepia::Base
  # Automatic generation tracking
  def save_with_generation
    # Creates new ID with incremented generation
    # Returns new object instance
  end

  def generation
    # Extract generation from ID: 2
  end

  def base_id
    # Extract UUID part: note-123e4567-e89b-12d3-a456-426614174000
  end

  def stale?(expected_generation)
    # Check if current generation > expected
  end
end
```

## Implementation Details

### 1. ID Format
```
{object_type}-{uuid}.{generation}
```
- Separator: `.` (configurable)
- Generation starts at 0 for new objects
- Increments on each `save_with_generation` call

### 2. Key Methods

```crystal
module Sepia
  class Base
    class_property generation_separator = "."

    # Override to include generation in new IDs
    def self.generate_id
      "#{super}#{generation_separator}0"
    end

    # Extract generation from current ID
    def generation : Int32
      id.split(generation_separator).last.to_i
    end

    # Get base ID without generation
    def base_id : String
      id.split(generation_separator)[0..-2].join(generation_separator)
    end

    # Create new version
    def save_with_generation : self
      new_id = "#{base_id}#{generation_separator}#{generation + 1}"
      new_obj = self.class.new
      new_obj.id = new_id
      new_obj.attributes = self.attributes.reject("id")
      new_obj.save
      new_obj
    end

    # Check if object has newer version
    def stale?(expected_generation : Int32) : Bool
      self.class.exists?("#{base_id}#{generation_separator}#{expected_generation + 1}")
    end

    # Find latest version
    def self.latest(base_id : String) : self?
      # Find all files matching base_id.*
      # Return one with highest generation
    end

    # Find all versions
    def self.versions(base_id : String) : Array(self)
      # Return all versions in order
    end
  end
end
```

### 3. Query Support

```crystal
# Find latest version of an object
note = Note.latest("note-123e4567-e89b-12d3-a456-426614174000")

# Get all versions
versions = Note.versions("note-123e4567-e89b-12d3-a456-426614174000")

# Check if newer version exists
if note.stale?(note.generation)
  # Reload latest
  note = Note.latest(note.base_id)
end
```

### 4. JSON Serialization
- Include generation in serialized output:
```json
{
  "id": "note-123e4567-e89b-12d3-a456-426614174000.2",
  "generation": 2,
  "base_id": "note-123e4567-e89b-12d3-a456-426614174000",
  ...
}
```

## Benefits

1. **Perfect Fit for Sepia** - Works with file-based architecture, not against it
2. **Atomic Operations** - New version is a new file, no in-place updates
3. **No Migration Needed** - Existing objects remain valid (generation 0)
4. **Built-in History** - All versions preserved automatically
5. **Simple Implementation** - Leverages existing ID mechanisms
6. **Conflict Resolution** - Easy to detect concurrent modifications
7. **Garbage Collection Friendly** - Old versions can be cleaned up separately

## Use Cases

### 1. Real-time Collaborative Editing (ToCry)
```javascript
// WebSocket message from server
{
  type: "note_updated",
  base_id: "note-123e4567-e89b-12d3-a456-426614174000",
  generation: 3
}

// Client checks if update needed
if (clientGeneration < 3) {
  // Fetch and replace note card
}
```

### 2. Optimistic Concurrency Control
```crystal
# User 1 loads note (gen 2)
note1 = Note.get("note-xxx.2")

# User 2 loads same note
note2 = Note.get("note-xxx.2")

# User 1 saves
note1_saved = note1.save_with_generation  # Creates note-xxx.3

# User 2 tries to save
note2_stale = note2.stale?(2)  # true, because note-xxx.3 exists
unless note2_stale
  note2.save_with_generation
else
  # Handle conflict: reload and merge
end
```

### 3. Version History/Audit Trail
```crystal
# Get change history
versions = Note.versions("note-xxx")
versions.each do |version|
  puts "Version #{version.generation}: #{version.updated_at}"
end
```

## Migration Strategy

1. **Existing Objects** - Treated as generation 0
2. **New Objects** - Get `.0` suffix automatically
3. **Backward Compatibility** - Old IDs still work
4. **Optional Upgrade** - Existing code continues working without changes

## File System Impact

```
# Before
data/
  └── Note/
      └── note-123e4567-e89b-12d3-a456-426614174000.json

# After (multiple versions)
data/
  └── Note/
      ├── note-123e4567-e89b-12d3-a456-426614174000.0.json
      ├── note-123e4567-e89b-12d3-a456-426614174000.1.json
      └── note-123e4567-e89b-12d3-a456-426614174000.2.json
```

## Performance Considerations

1. **Storage** - Additional files for each version
2. **Lookup** - Slightly more complex ID parsing
3. **Cleanup** - Optional background job to remove old versions

## Open Questions

1. Should the generation separator be configurable?
2. Should we provide automatic cleanup of old versions?
3. Should `save` automatically use `save_with_generation` (breaking change)?
4. Should we support custom ID formats for existing objects?

## Alternatives Considered

1. **Separate Generation Field**
   - Requires file modification
   - Migration complexity
   - Not atomic with file-based storage

2. **Timestamp-Based Versioning**
   - Clock skew issues
   - Less precise than sequence numbers
   - Harder to detect exact changes

3. **External Version Tracking**
   - Application-specific
   - Code duplication
   - Error-prone

## Conclusion

Encoding generation numbers in the ID is the most Sepia-idiomatic approach to versioning. It leverages the existing file-based architecture rather than fighting against it, provides atomic updates naturally, and requires minimal changes to the core system.
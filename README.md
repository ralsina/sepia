# Sepia

⚠️ **Warning: Unstable API and Storage Format**
Sepia is currently in active development and does not have a stable API or storage format. **The API is subject to change without notice**, and **breaking changes may occur in any release**. Additionally, the on-disk storage format is not stable - you will need to migrate your data stores when upgrading between versions. Use at your own risk in production.

Sepia is a simple, file-system-based serialization library for Crystal. It provides two modules, `Sepia::Serializable` and `Sepia::Container`, to handle the persistence of objects to disk.

## Core Concepts

- **`Sepia::Serializable`**: Objects that include this module are serialized to a single file. The content of the file is determined by the object's `to_sepia` method. These objects are stored in a "canonical" location based on their class name and `sepia_id`.

- **`Sepia::Container`**: Objects that include this module are serialized as directories. They can contain other `Serializable` or `Container` objects.
  - Nested `Serializable` objects are stored as symlinks to their canonical file.
  - Nested `Container` objects are stored as subdirectories, creating a nested on-disk structure that mirrors the object hierarchy.
  - **Automatic JSON Serialization**: Primitive properties (String, Int32, Bool, Time, etc.) are automatically serialized to a `data.json` file without requiring custom methods.

## Documentation

API documentation can be found at [crystaldoc.info/github/ralsina/sepia/](https://crystaldoc.info/github/ralsina/sepia/)

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     sepia:
       github: ralsina/sepia
   ```

2. Run `shards install`

## Storage Backends

Sepia supports pluggable storage backends. Two backends are currently available:

- **`:filesystem`**: The default backend, which stores objects on the local filesystem. This is the original Sepia behavior.
- **`:memory`**: An in-memory backend, useful for testing or for temporary, non-persistent data.

You can configure the storage backend using `Sepia::Storage.configure`.

## Garbage Collection

Sepia includes a mark-and-sweep garbage collector (GC) to automatically find and delete orphaned objects from storage.

### New Requirement: Inheriting from `Sepia::Object`

To enable garbage collection and other shared features, all classes that you intend to manage with Sepia **must** inherit from the `Sepia::Object` base class.

```crystal
class MySerializable < Sepia::Object
  include Sepia::Serializable
  # ...
end

class MyContainer < Sepia::Object
  include Sepia::Container
  # ...
end
```

### How it Works

The garbage collector identifies "live" objects by starting from a set of "root objects" that you provide. It marks them and any object they reference (and so on recursively) as "live". Any object in storage that is not marked as live is considered an orphan and is deleted.

To run the collector, you must pass an `Enumerable` (like an `Array`) of the objects you consider to be the roots.

```crystal
# Assume my_app_roots is an array containing the top-level
# objects that your application considers the starting point.
my_app_roots = [user1, user2, top_level_board]

# Find and delete all orphaned objects
deleted_summary = Sepia::Storage.gc(roots: my_app_roots)

# To get a report of what would be deleted without actually deleting anything:
orphans = Sepia::Storage.gc(roots: my_app_roots, dry_run: true)

# To garbage collect everything, pass an empty array:
deleted_summary = Sepia::Storage.gc(roots: [] of Sepia::Object)
```

## File Watcher

Sepia includes a file system watcher that can monitor changes to objects in storage and generate events when data is modified on disk. This is useful for building collaborative applications that need to react to external file changes.

### ⚠️ Linux Only

The file watcher feature currently only supports Linux systems with inotify support.

### Basic Usage

```crystal
require "sepia"

# Configure storage
Sepia::Storage.configure(:filesystem, {"path" => "./data"})

# Create a watcher for the current storage backend
storage = Sepia::Storage.backend.as(Sepia::FileStorage)
watcher = Sepia::Watcher.new(storage)

# Register a callback for file system events
watcher.on_change do |event|
  puts "#{event.type}: #{event.object_class} #{event.object_id} (#{event.path})"

  case event.type
  when .created?
    puts "New object created!"
  when .modified?
    puts "Object modified, reloading..."
    begin
      # Load the modified object
      obj = Sepia::Storage.load(event.object_class.constantize(typeof(Object)), event.object_id)
      handle_object_change(obj)
    rescue ex
      puts "Failed to load object: #{ex.message}"
    end
  when .deleted?
    puts "Object deleted!"
  end
end

# Start watching (runs in background)
watcher.start

# Your application continues here...
# The watcher will automatically detect external file changes

# Stop watching when done
watcher.stop
```

### Event Types

The watcher generates events of type `Sepia::EventType`:

- **`Created`**: A new file or directory was created
- **`Modified`**: An existing file or directory was modified
- **`Deleted`**: A file or directory was deleted

### Event Structure

Each event contains the following information:

```crystal
event = Sepia::Event.new(
  type: Sepia::EventType::Modified,
  object_class: "MyDocument",
  object_id: "doc-123",
  path: "/storage/MyDocument/doc-123",
  timestamp: Time.utc
)

event.type          # => Sepia::EventType::Modified
event.object_class   # => "MyDocument"
event.object_id      # => "doc-123"
event.path           # => "/storage/MyDocument/doc-123"
event.timestamp      # => Time instance
```

### Internal Operation Filtering

The watcher automatically filters out operations performed by Sepia itself to prevent callback loops. This means that if you call `save()` on an object through the Sepia API, it won't trigger the watcher callback.

### Important Notes

- The watcher only monitors the filesystem directory where Sepia stores its data
- Temporary files (`.tmp` extensions) from atomic writes are automatically ignored
- The watcher is Linux-only and requires inotify support
- Events are processed asynchronously in background fibers
- Multiple rapid changes may be batched or reordered

## Event Logging

Sepia includes a comprehensive event logging system that tracks object lifecycle events and user activities. This is particularly useful for collaborative applications, audit trails, and activity feeds.

### Key Concepts

- **Event Types**: Created, Updated, Deleted, Activity
- **Per-Object Storage**: Events are stored in JSON Lines format alongside object data
- **Metadata Support**: Attach custom context to events (user, reason, etc.)
- **Class-Level Control**: Enable/disable logging per class type
- **Activity Logging**: Log user actions that aren't object persistence events

### Enabling Event Logging

Event logging is disabled by default. Enable it for specific classes:

```crystal
class Document < Sepia::Object
  include Sepia::Serializable
  sepia_log_events true  # Enable logging for this class

  property content : String

  def initialize(@content = "")
  end

  def to_sepia : String
    @content
  end

  def self.from_sepia(json : String) : self
    new(json)
  end
end

class Project < Sepia::Object
  include Sepia::Container
  sepia_log_events true  # Enable logging for containers too

  property name : String
  property boards : Array(Board)

  def initialize(@name = "")
    @boards = [] of Board
  end
end
```

### Automatic Event Logging

When event logging is enabled, Sepia automatically logs lifecycle events:

```crystal
# Create and save (logs Created event)
doc = Document.new("Hello World")
doc.save(metadata: {"user" => "alice", "reason" => "initial_creation"})

# Update and save (logs Updated event)
doc.content = "Hello Updated World"
doc.save(metadata: {"user" => "bob", "reason" => "content_edit"})

# Delete (logs Deleted event)
Sepia::Storage.delete(doc, metadata: {"user" => "admin", "reason" => "cleanup"})
```

### Activity Logging

Log user activities that aren't related to object persistence:

```crystal
# Log arbitrary activities on objects
doc.log_activity("highlighted", {"color" => "yellow", "user" => "alice"})
doc.log_activity("shared", {"platform" => "slack", "user" => "bob"})

# Log activities on containers too
project.log_activity("lane_created", {"lane_name" => "Review", "user" => "charlie"})
project.log_activity("color_changed")  # Simple version without metadata
```

### Querying Events

Access the event history for any object:

```crystal
# Get all events for an object
events = Sepia::Storage.object_events(Document, doc.sepia_id)

# Events are ordered by timestamp (newest first)
events.each do |event|
  puts "#{event.timestamp}: #{event.event_type}"
  puts "  Generation: #{event.generation}"
  puts "  Metadata: #{event.metadata}"
end

# Filter by event type
created_events = events.select(&.event_type.created?)
activity_events = events.select(&.event_type.activity?)
```

### Event Structure

Each event contains:

```crystal
event = Sepia::LogEvent.new(
  event_type: Sepia::LogEventType::Updated,
  generation: 2,
  metadata: {"user" => "alice", "reason" => "edit"}
)

event.timestamp    # => Time when the event occurred
event.event_type   # => Created, Updated, Deleted, or Activity
event.generation   # => Object generation number (0 for activities)
event.metadata     # => Hash(String, String) of custom context
```

### On-Disk Format

Events are stored in JSON Lines format in `.events/` directories:

```
./_data
├── Document
│   └── doc-123
│       └── .events
│           └── doc-123.jsonl    # One JSON event per line
└── Project
    └── proj-456
        └── .events
            └── proj-456.jsonl
```

Event file format:
```json
{"ts":"2025-01-15T10:30:45Z","type":"created","gen":1,"meta":{"user":"alice"}}
{"ts":"2025-01-15T10:31:20Z","type":"activity","gen":0,"meta":{"action":"highlighted","color":"yellow"}}
{"ts":"2025-01-15T10:32:10Z","type":"updated","gen":2,"meta":{"user":"bob","reason":"edit"}}
```

### Use Cases

- **Activity Feeds**: Show recent user actions in collaborative apps
- **Audit Trails**: Track who changed what and when
- **Debugging**: Understand the sequence of operations on objects
- **Analytics**: Analyze usage patterns and collaboration metrics

### Important Notes

- Event logging is opt-in per class to avoid unnecessary storage overhead
- Metadata values are automatically converted to strings for consistent storage
- Events are persisted alongside object data and survive garbage collection
- Activity events don't affect object generation numbers
- The system is designed to be extensible for future enhancements

## Generation Tracking for Optimistic Concurrency Control

Sepia supports generation tracking to enable optimistic concurrency control and versioning of objects. This is particularly useful for collaborative applications where multiple users might edit the same data.

### Key Concepts

- **Generation Number**: Each object version has a generation number (0, 1, 2, etc.) encoded in its ID
- **Base ID**: The unique identifier without the generation suffix
- **Atomic Updates**: New versions are created as new files, never modifying existing ones
- **Optimistic Locking**: Detect conflicts when multiple users try to save simultaneously

### ID Format

Objects use the format: `{type}-{uuid}.{generation}`

Examples:
- `note-123e4567-e89b-12d3-a456-426614174000.0` (initial version)
- `note-123e4567-e89b-12d3-a456-426614174000.1` (first update)
- `note-123e4567-e89b-12d3-a456-426614174000.2` (second update)

### Core API

```crystal
class Note < Sepia::Object
  include Sepia::Serializable

  property title : String
  property content : String

  def initialize(@title, @content)
  end

  def to_sepia : String
    {title: @title, content: @content}.to_json
  end

  def self.from_sepia(json : String) : self
    data = JSON.parse(json)
    new(data["title"].as_s, data["content"].as_s)
  end
end

# Create and save
note = Note.new("My Note", "Initial content")
note.save  # Creates note-xxx.0

# Create new version
v2 = note.save_with_generation
# v2.id is now note-xxx.1

# Check current generation
note.generation      # => 0
v2.generation        # => 1

# Get base ID
note.base_id         # => "note-xxx"
v2.base_id           # => "note-xxx"

# Check for newer versions
note.stale?(0)       # => true (because v2 exists)

# Find latest version
latest = Note.latest("note-xxx")
latest.generation    # => 1

# Get all versions
versions = Note.versions("note-xxx")
versions.map(&.generation)  # => [0, 1]
```

### Conflict Resolution

```crystal
# User 1 loads note
user1_note = Note.load("note-xxx.1")

# User 2 loads same note
user2_note = Note.load("note-xxx.1")

# User 1 saves
user1_saved = user1_note.save_with_generation  # Creates note-xxx.2

# User 2 tries to save
if user2_note.stale?(1)
  # Conflict! Reload and merge
  latest = Note.latest(user2_note.base_id)
  # Merge changes and save again
else
  user2_saved = user2_note.save_with_generation
end
```

### Backward Compatibility

Existing objects without generation suffix are treated as generation 0 and continue to work seamlessly:

```crystal
# Legacy object
old_note = Note.load("legacy-note")
old_note.generation  # => 0
old_note.base_id     # => "legacy-note"
```

## Automatic JSON Serialization for Container Objects

`Sepia::Container` now automatically handles JSON serialization for primitive properties, eliminating the need to write custom save/load methods for simple data types.

### Supported Primitive Types

- Basic types: `String`, `Int32`, `Int64`, `Float32`, `Float64`, `Bool`
- Time types: `Time`
- Collections of primitives: `Array`, `Set`, `Hash` (when containing primitive types)
- Nilable versions of all above types

### How It Works

1. **Automatic Detection**: The Container module automatically identifies primitive instance variables at compile time
2. **Filtered Serialization**: Only primitive properties are included in the JSON - Sepia objects and collections containing them are excluded
3. **File Storage**: Primitive properties are stored in a `data.json` file within the container's directory
4. **Type-Safe Parsing**: Each type is parsed using the appropriate method to ensure type safety

### Example with Primitive Properties

```crystal
class UserProfile < Sepia::Object
  include Sepia::Container

  # Primitive properties - automatically serialized to JSON
  property name : String
  property age : Int32
  property active : Bool
  property created_at : Time
  property tags : Array(String)
  property metadata : Hash(String, String)

  # Sepia objects - handled via symlinks as before
  property friends : Array(User)
  property settings : UserSettings?

  def initialize(@name = "", @age = 0, @active = false)
    @created_at = Time.utc
    @tags = [] of String
    @metadata = {} of String => String
    @friends = [] of User
  end
end
```

When you save and load a `UserProfile`, all primitive properties are automatically handled:

```crystal
profile = UserProfile.new
profile.name = "Alice"
profile.age = 30
profile.active = true
profile.tags = ["admin", "premium"]
profile.metadata = {"theme" => "dark", "locale" => "en_US"}

# Save - primitive properties automatically written to data.json
# Sepia objects saved as symlinks
profile.save

# Load - primitive properties automatically restored from data.json
loaded = UserProfile.load(profile.sepia_id).as(UserProfile)

puts loaded.name        # => "Alice"
puts loaded.tags[0]      # => "admin"
puts loaded.metadata     # => {"theme" => "dark", "locale" => "en_US"}
```

### On-Disk Structure with Primitives

```
./_data
└── UserProfile
    └── alice_profile
        ├── data.json              # Primitive properties
        ├── friends
        │   └── 0000_bob -> ./_data/User/bob
        └── settings -> ./_data/UserSettings/default
```

The `data.json` file contains:
```json
{
  "name": "Alice",
  "age": 30,
  "active": true,
  "created_at": "2024-01-15T10:30:00Z",
  "tags": ["admin", "premium"],
  "metadata": {"theme": "dark", "locale": "en_US"}
}
```

### Excluded Properties

The following are automatically excluded from JSON serialization:
- Any property whose type inherits from `Sepia::Object`
- Arrays containing `Sepia::Object` elements
- Sets containing `Sepia::Object` elements
- Hashes with `Sepia::Object` values
- The `sepia_id` property (handled separately)

### Backward Compatibility

This feature is fully backward compatible. Existing Container classes will continue to work exactly as before, with primitive properties simply gaining automatic serialization support.

## Usage

Here's a simple example demonstrating how to use `Sepia` to save and load a nested structure of "Boards" and "Post-its".

First, configure the storage backend. For this example, we'll use the `:filesystem` backend to store data in a local `_data` directory.

```crystal
require "sepia"

# Configure Sepia to use the filesystem backend.
Sepia::Storage.configure(:filesystem, {"path" => "./_data"})

# A Postit is a simple Serializable object.
class Postit < Sepia::Object
  include Sepia::Serializable

  property text : String

  def initialize(@text); end
  def initialize; @text = ""; end

  # The to_sepia method defines the content of the serialized file.
  def to_sepia : String
    @text
  end

  # The from_sepia class method defines how to deserialize the object.
  def self.from_sepia(sepia_string : String) : self
    new(sepia_string)
  end
end

# A Board is a Container that can hold other Boards and Postits.
class Board < Sepia::Object
  include Sepia::Container

  # Primitive properties - automatically serialized
  property name : String
  property description : String?
  property created_at : Time
  property is_public : Bool = false

  # Sepia object references - handled via symlinks
  property boards : Array(Board)
  property postits : Array(Postit)

  def initialize(@name = "", @description = nil)
    @created_at = Time.utc
    @boards = [] of Board
    @postits = [] of Postit
  end
end

# --- Create and Save ---

# A top-level board for "Work"
work_board = Board.new
work_board.sepia_id = "work_board"
work_board.name = "Work"
work_board.description = "Work-related boards"
work_board.is_public = false

# A nested board for "Project X"
project_x_board = Board.new
project_x_board.sepia_id = "project_x" # This ID is only used for top-level objects
project_x_board.name = "Project X"
project_x_board.description = "Tracking Project X progress"

# Create some Post-its
postit1 = Postit.new("Finish the report")
postit1.sepia_id = "report_postit"
postit2 = Postit.new("Review the code")
postit2.sepia_id = "code_review_postit"

# Assemble the structure
project_x_board.postits << postit2
work_board.boards << project_x_board
work_board.postits << postit1

# Save the top-level board. This will recursively save all its contents.
work_board.save

# --- Load ---

loaded_work_board = Board.load("work_board").as(Board)

puts loaded_work_board.postits[0].text # => "Finish the report"
puts loaded_work_board.boards[0].postits[0].text # => "Review the code"
```

### On-Disk Representation

After running the code above, the `_data` directory will have the following structure:

```
./_data
├── Board
│   └── work_board
│       ├── data.json              # Primitive properties (name, description, etc.)
│       ├── boards
│       │   └── 0000_project_x     # Array elements are prefixed with index
│       │       ├── data.json      # Primitive properties for project_x
│       │       └── postits
│       │           └── 0000_code_review_postit -> ./_data/Postit/code_review_postit
│       └── postits
│           └── 0000_report_postit -> ./_data/Postit/report_postit
└── Postit
    ├── code_review_postit
    └── report_postit
```

Notice how:
- The `work_board` and its nested `project_x` board are directories.
- Each board directory contains a `data.json` file with primitive properties.
- Array elements (like `boards` and `postits`) are stored in subdirectories with indexed prefixes (e.g., `0000_project_x`) to maintain order.
- The `Postit` objects are stored in the canonical `Postit` directory and are referenced by symlinks.

The `data.json` for `work_board` would contain:
```json
{
  "name": "Work",
  "description": "Work-related boards",
  "created_at": "2024-01-15T10:30:00Z",
  "is_public": false
}
```

## Development

To run the tests, clone the repository and run `crystal spec`.

## Contributing

1. Fork it (<https://github.com/ralsina/sepia/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Roberto Alsina](https://github.com/ralsina) - creator and maintainer

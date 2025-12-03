# Utilities

## Sepia::Watcher

File system monitoring for detecting external changes to stored objects. Works with FileStorage to provide real-time notifications when objects are modified by external processes.

### Configuration

```crystal
# Get watcher from FileStorage with watching enabled
storage = Sepia::FileStorage.new("./data", watch: true)
watcher = storage.watcher

# Or create directly
storage = Sepia::FileStorage.new("./data")
watcher = Sepia::Watcher.new(storage)
```

### Event Types

The watcher can detect different types of file system events:

- **Created** - New file or directory appeared
- **Modified** - Existing file content changed
- **Deleted** - File or directory was removed
- **Moved** - File or directory was renamed/ relocated

### Event Handling

```crystal
watcher.on_change do |events|
  events.each do |event|
    case event.type
    when .created?
      puts "New object: #{event.path}"
    when .modified?
      puts "Object modified: #{event.path}"
    when .deleted?
      puts "Object deleted: #{event.path}"
    end
  end
end

watcher.start
```

### Methods

- `start` - Begin monitoring the storage directory
- `stop` - Stop monitoring and cleanup resources
- `running?` - Check if watcher is currently active
- `on_change(&block : Array(Sepia::Watcher::Event) ->)` - Register event callback
- `storage` - Get the associated storage backend

## Sepia::EventLogger

Automatic event logging system that tracks object lifecycle events and user activities. Provides audit trails and activity feeds for collaborative applications.

### Event Types

- **Created** - Object was created for the first time
- **Updated** - Object was modified and saved
- **Deleted** - Object was removed from storage
- **Activity** - User-defined actions

### Usage

```crystal
# Enable event logging with FileStorage
storage = Sepia::FileStorage.new("./data")
logger = Sepia::EventLogger.new(storage)

# Or configure with Storage
Sepia::Storage.configure(:filesystem, {"path" => "./data"})
logger = Sepia::EventLogger.new(Sepia::Storage.backend)
```

### Activity Logging

```crystal
# Log custom activities
logger.log_activity("shared", {"user" => "alice", "recipient" => "bob"})
logger.log_activity("moved", {"from" => "folder1", "to" => "folder2"})
```

### Querying Events

```crystal
# Get all events for an object
events = logger.events_for("document-123")

# Get events in time range
events = logger.events_between(Time.utc - 1.hour, Time.utc)

# Filter by event type
update_events = logger.events_for("document-123", type: :updated)

# Filter by metadata
shared_events = logger.events_for("document-123", metadata_contains: {"user" => "alice"})
```

### Methods

- `save(object, metadata = nil)` - Automatically log object save events
- `delete(object, metadata = nil)` - Automatically log object deletion
- `log_activity(action, metadata = nil)` - Log custom activity events
- `events_for(object_id, type = nil, metadata_contains = nil)` - Query events
- `events_between(start_time, end_time, type = nil)` - Query by time range
- `delete_events_for(object_id)` - Remove all events for an object

## Sepia::Backup

Complete backup and restore system for Sepia object graphs. Creates tar archives with all objects, their relationships, and metadata for data migration and portability.

### Creating Backups

```crystal
# Backup with automatic object graph discovery
backup_path = Sepia::Backup.create([root_object], "backup.tar")

# Backup multiple root objects
backup_path = Sepia::Backup.create([project1, project2], "backup.tar")

# Using object method
backup_path = project.backup_to("project_backup.tar")
```

### Backup Contents

Each backup includes:

- **Objects/** - All object data and references
- **metadata.json** - Backup metadata and object relationships
- **README** - Human-readable backup information

### Verification

```crystal
# Verify backup integrity
result = Sepia::Backup.verify("backup.tar")
result.valid        # => true/false
result.errors        # => Array of error messages
result.statistics   # => Backup size, object counts, etc.
```

### Methods

- `create(root_objects, output_path)` - Create backup from root objects
- `verify(backup_path)` - Verify backup integrity and structure
- `list_contents(backup_path)` - List all files in backup archive

## Sepia::MemoryLimiter

Memory pressure monitoring system for cache management. Monitors system memory usage and provides signals for when caches should be purged.

### Configuration

```crystal
limiter = Sepia::MemoryLimiter.new(
  warning_threshold: "70%",   # Trigger warning at 70% memory usage
  critical_threshold: "85%",   # Trigger critical at 85% memory usage
  check_interval: 30.seconds   # Check every 30 seconds
)
```

### Event Callbacks

```crystal
limiter.on_warning do |stats|
  puts "Memory usage is high: #{stats.usage_percent}%"
  # Trigger cache cleanup
end

limiter.on_critical do |stats|
  puts "Critical memory usage: #{stats.usage_percent}%"
  # Aggressive cleanup
end

limiter.start_monitoring
```

### Memory Statistics

The limiter provides detailed memory information:

```crystal
limiter.current_stats        # => MemoryStats with current usage
limiter.status_description  # => Human-readable status
limiter.check_now           # => Force immediate check
```

### Methods

- `start_monitoring` - Begin periodic memory monitoring
- `stop_monitoring` - Stop monitoring and cleanup
- `check_now` - Force immediate memory usage check
- `suggest_cache_size` - Get recommended cache size based on pressure
- `on_warning(&block)` - Register warning callback
- `on_critical(&block)` - Register critical callback

## Sepia::WeakCache

Memory-aware cache using weak references. Allows garbage collection to reclaim memory while providing fast object access.

### Features

- **Weak references** - Objects can be garbage collected when memory is needed
- **Automatic cleanup** - Dead references are automatically removed
- **Type-safe** - Generic cache for specific object types
- **Statistics** - Track cache hit rates and memory usage

### Usage

```crystal
# Create cache for Sepia objects
cache = Sepia::WeakCache(Sepia::Object).new

# Store objects
cache.put("doc-123", my_document)
cache.put("user-456", my_user)

# Retrieve objects (may return nil if garbage collected)
doc = cache.get("doc-123")
user = cache.get("user-456")

# Get cache statistics
stats = cache.stats
stats.hit_rate        # => Cache hit rate percentage
stats.total_objects   # => Current number of cached objects
```

### Methods

- `put(key, value)` - Store object in cache
- `get(key)` - Retrieve object (may return nil)
- `delete(key)` - Remove specific object from cache
- `cleanup` - Remove dead references
- `clear` - Remove all objects
- `size` - Get current cache size
- `stats` - Get cache statistics

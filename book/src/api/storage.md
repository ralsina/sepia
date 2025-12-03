# Storage Backends

## Sepia::Storage

Global storage management singleton. Provides the main API for interacting with different storage backends and managing object persistence.

### Configuration

```crystal
# Configure with filesystem storage (default)
Sepia::Storage.configure(:filesystem, {"path" => "./data"})

# Configure with in-memory storage
Sepia::Storage.configure(:memory)

# Get the configured backend
backend = Sepia::Storage.backend
```

### Core Methods

- `configure(backend_type : Symbol, options = Hash(String, String).new)` - Configure storage backend
- `backend : StorageBackend` - Get the current storage backend
- `save(object : Sepia::Object, path = nil)` - Save an object to storage
- `load(klass : Class, id : String, path = nil)` - Load an object from storage
- `delete(object : Sepia::Object)` - Delete an object from storage
- `exists?(klass : Class, id : String)` - Check if an object exists

## Sepia::FileStorage

Filesystem-based storage backend. Stores objects as files and directories on the local filesystem.

### Features

- **Serializable objects** - Stored as individual files
- **Container objects** - Stored as directories with nested structure
- **Canonical storage paths** - Consistent `storage_path/ClassName/object_id` structure
- **File system watching** - Optional monitoring for external changes

### Configuration

```crystal
storage = Sepia::FileStorage.new("./my_data")

# With file watching enabled
storage = Sepia::FileStorage.new("./my_data", watch: true)

# Advanced watcher configuration
storage = Sepia::FileStorage.new(
  "./my_data",
  watch: {
    "enabled" => true,
    "recursive" => true,
    "latency" => 0.1
  }
)
```

### Directory Structure

```
storage_path/
├── MyDocument/           # Serializable objects
│   ├── doc-1
│   └── doc-2
├── MyProject/            # Container objects
│   ├── project-1/
│   │   ├── data.json
│   │   └── refs/
│   └── project-2/
└── User/
    ├── user-123
    └── user-456
```

### Watcher Configuration

FileStorage supports multiple backends for file system monitoring:

- **fswatch** (default): Cross-platform (Linux, macOS, Windows)
- **inotify**: Linux-only for better performance

### Methods

- `path : String` - Get the storage root directory
- `save(object : Serializable, path = nil)` - Save a serializable object
- `save(object : Container, path = nil)` - Save a container object
- `load(klass : Class, id : String, path = nil)` - Load an object
- `delete(object : Serializable)` - Delete a serializable object
- `delete(object : Container)` - Delete a container object
- `exists?(klass : Class, id : String)` - Check if object exists
- `watcher_running?` - Check if file system watcher is active

## Sepia::InMemoryStorage

In-memory storage backend for testing and temporary use. Objects are stored in memory and lost when the process ends.

### Features

- **Fast access** - No disk I/O overhead
- **No persistence** - Data lost on process exit
- **Simple structure** - Uses internal Hash storage
- **Thread-safe** - Uses Mutex for concurrent access

### Usage

```crystal
# Configure for in-memory storage
Sepia::Storage.configure(:memory)

# Or create directly
storage = Sepia::InMemoryStorage.new

# Objects behave the same as with file storage
storage.save(my_object)
loaded = storage.load(MyClass, "object-id")
```

### Limitations

- **No backup support** - Cannot create filesystem backups
- **No file watching** - No external change detection
- **Memory usage** - All objects remain in memory until explicitly deleted
- **No persistence** - Data lost when process exits

### Methods

- `save(object : Sepia::Object, path = nil)` - Store object in memory
- `load(klass : Class, id : String, path = nil)` - Load object from memory
- `delete(object : Sepia::Object)` - Remove object from memory
- `exists?(klass : Class, id : String)` - Check if object exists in memory
- `clear` - Remove all objects from memory
- `size` - Get number of objects currently stored

## Sepia::StorageBackend

Abstract base class for storage backends. Defines the interface that all storage implementations must follow.

### Required Methods

Storage backends must implement:
- `save(object : Serializable, path = nil)`
- `save(object : Container, path = nil)`
- `load(klass : Class, id : String, path = nil)`
- `delete(object : Serializable)`
- `delete(object : Container)`
- `exists?(klass : Class, id : String)`

### Optional Features

Backends may also implement:
- **File watching** - `Watcher` support for external change detection
- **Backup support** - Integration with backup system
- **Performance optimizations** - Caching, bulk operations, etc.

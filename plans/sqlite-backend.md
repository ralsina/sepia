# SQLite Backend Implementation Plan for Sepia

## Overview
Create a new `SQLiteStorage` backend that provides document-style schemaless storage using SQLite with JSON/BLOB approach, optimized for local development and embedded applications.

## Implementation Steps

### 1. Project Dependencies
- Add `sqlite3` dependency to `shard.yml`
- Ensure SQLite3 development libraries are available

### 2. Database Schema Design
- Create a single `objects` table with columns: `class_name`, `object_id`, `content`, `object_type`, `metadata`
- Use JSON storage for Serializable objects, BLOB for Container data
- Add indexes on `class_name` and `object_id` for fast lookups

### 3. Core SQLiteStorage Class (`src/sepia/sqlite_storage.cr`)
- Inherit from `StorageBackend` abstract class
- Implement all required methods: save, load, delete, list_all, exists?, count, clear, export_data, import_data
- Handle both Serializable and Container objects
- Use connection pooling and prepared statements for performance
- Implement proper transaction handling

### 4. Storage Integration (`src/sepia/storage.cr`)
- Update `Storage.configure` to support `:sqlite` backend
- Add configuration options for database path, connection settings
- Ensure seamless integration with existing caching system

### 5. Error Handling & Edge Cases
- Database connection failures
- Schema migrations
- Concurrent access handling
- Data corruption recovery

### 6. Testing (`spec/sqlite_storage_spec.cr`)
- Comprehensive test suite covering all backend methods
- Performance benchmarks vs FileStorage and InMemoryStorage
- Concurrency testing
- Edge case handling (large objects, special characters)

### 7. Documentation
- API documentation with examples
- Performance characteristics guide
- Migration guide from other backends

## Key Design Decisions
- Document-style storage in single table for simplicity and performance
- JSON for Serializable objects, structured JSON for Container references
- Connection pooling for better concurrent performance
- Automatic schema initialization and migration support

## Database Schema (Initial Draft)

```sql
CREATE TABLE IF NOT EXISTS objects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    class_name TEXT NOT NULL,
    object_id TEXT NOT NULL,
    content TEXT NOT NULL,  -- JSON for both Serializable and Container objects
    object_type TEXT NOT NULL,  -- 'serializable' or 'container'
    metadata TEXT,  -- JSON metadata for future extensibility
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(class_name, object_id)
);

CREATE INDEX IF NOT EXISTS idx_objects_class_name ON objects(class_name);
CREATE INDEX IF NOT EXISTS idx_objects_class_id ON objects(class_name, object_id);
```

## Performance Considerations

### Advantages of SQLite Approach
- **Single file database**: Easier deployment than separate files
- **ACID compliance**: Reliable transactions
- **Indexed lookups**: Fast key-value access
- **Concurrent readers**: Multiple reads without blocking
- **Memory efficiency**: Less overhead than many small files

### Trade-offs
- **Write overhead**: Database writes may be slower than direct file writes for very large objects
- **Single writer limitation**: SQLite allows only one writer at a time
- **Dependency management**: Requires SQLite3 library

## Usage Examples

```crystal
# Configure SQLite storage
Sepia::Storage.configure(:sqlite, {
  "database_path" => "./app_data.db"
})

# Or with custom settings
Sepia::Storage.configure(:sqlite, {
  "database_path" => "./app_data.db",
  "connection_pool_size" => 10,
  "journal_mode" => "WAL"
})

# Usage is identical to other backends
doc = MyDocument.new("Hello SQLite")
Sepia::Storage.save(doc)

loaded = Sepia::Storage.load(MyDocument, doc.sepia_id)
```

## Future Enhancements
- Full-text search capabilities using SQLite FTS5
- Query API for complex object retrieval
- Database migration system for schema changes
- Backup and restore utilities
- Performance monitoring and statistics
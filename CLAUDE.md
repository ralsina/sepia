# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

Since this is a Crystal library, there's no traditional build process. Use these commands:

- **Run tests**: `crystal spec`
- **Run specific test file**: `crystal spec spec/sepia_spec.cr`
- **Run single test**: `crystal spec spec/sepia_spec.cr -e "test name"`
- **Format code**: `crystal tool format`
- **Check dependencies**: `shards check`

### Build Options

**Standard build (with fswatch support):**
```bash
crystal build src/your_app.cr
# or
crystal run src/your_app.cr
```

**Static builds or without fswatch:**
For static builds or when fswatch is not available, compile with the `no_fswatch` flag:
```bash
crystal build src/your_app.cr -D no_fswatch
# or
crystal run src/your_app.cr -D no_fswatch
```

When using `no_fswatch`, the file system watcher will be a no-op implementation that doesn't monitor external changes. This allows the library to work in environments where fswatch cannot be compiled statically.

## Architecture Overview

Sepia is a file-system-based serialization library with two core modules:

### Core Modules

1. **Sepia::Serializable** (`src/sepia/serializable.cr`):
   - Objects serialize to single files
   - Must implement `to_sepia : String` and `self.from_sepia(sepia_string : String)`
   - Stored in canonical location: `storage_path/ClassName/sepia_id`

2. **Sepia::Container** (`src/sepia/container.cr`):
   - Objects serialize as directories
   - Can contain other Serializable or Container objects
   - Uses extensive compile-time macros to handle different nested types

### Storage System

**Sepia::Storage** (`src/sepia/storage.cr`):
- Singleton pattern (INSTANCE)
- Manages the base storage path (defaults to temp directory)
- Handles save/load/delete operations for both Serializable and Container objects

### Key Design Patterns

1. **Automatic sepia_id**: All objects get a UUID-based ID by default
2. **Symlink references**: Serializable objects in Containers are stored as symlinks to avoid duplication
3. **Recursive save/load**: Container objects automatically handle nested object persistence
4. **Compile-time type inspection**: Container module uses macros to analyze instance variables at compile time

### On-Disk Structure

The library creates a filesystem representation where:
- `Serializable` objects → Files in `ClassName/sepia_id`
- `Container` objects → Directories with nested structure
- Collections → Subdirectories with indexed entries
- References → Relative symlinks to canonical locations

### Important Implementation Details

1. **Container.save_references**: Uses macro-generated code to handle each instance variable based on its type
2. **Container.load_references**: Complex compile-time logic to reconstruct objects from filesystem structure
3. **Relative symlinks**: Uses `Path.relative_to` for portable symlinks
4. **Nilable handling**: Properly handles optional references in both save and load operations

### Testing

The specs (`spec/` directory) demonstrate usage patterns and edge cases, particularly around:
- Nested object structures
- Nilable references
- Different collection types (Array, Hash)
- Circular reference handling
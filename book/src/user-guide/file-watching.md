# File System Watching

Sepia's file system watcher enables reactive applications that respond to external changes in storage. It's particularly useful for collaborative applications where multiple users or processes might modify data simultaneously.

## Backend Options

The file watcher supports multiple backends for cross-platform compatibility:

### fswatch (Default)
- **Platforms**: Linux, macOS, Windows
- **Requirements**: libfswatch installed
- **Use case**: Development and cross-platform applications

### inotify
- **Platforms**: Linux only
- **Requirements**: None (uses kernel inotify)
- **Use case**: Production Linux servers, static builds

## Configuration

The file watcher is automatically configured based on the backend you selected when building your application.

```crystal
# No additional configuration needed - uses the compiled backend
storage = Sepia::Storage.backend.as(Sepia::FileStorage)
watcher = Sepia::Watcher.new(storage)
```

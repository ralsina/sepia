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

### no_watching (Disabled)
- **Platforms**: All platforms
- **Requirements**: None
- **Use case**: Applications without file watching needs, embedded systems, reduced dependencies

## Configuration with no_watching

When you don't need file system monitoring, you can completely disable it to reduce dependencies:

```crystal
# Compile without file watching
crystal build your_app.cr -D no_watching

# Or use it in your shard.yml for static builds
dependencies:
  sepia:
    github: ralsina/sepia
# no fswatch dependency needed when using -D no_watching
```

## Benefits of no_watching

- **Zero dependencies**: No need for libfswatch or inotify.shards
- **Static compilation**: Works in environments where fswatch can't be statically compiled
- **Reduced memory**: No background threads or processes
- **Faster startup**: No file system monitoring setup overhead
- **Cross-platform**: Works everywhere without platform-specific dependencies

## Configuration

The file watcher is automatically configured based on the backend you selected when building your application.

```crystal
# No additional configuration needed - uses the compiled backend
storage = Sepia::Storage.backend.as(Sepia::FileStorage)
watcher = Sepia::Watcher.new(storage)
```

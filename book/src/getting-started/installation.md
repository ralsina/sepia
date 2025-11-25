# Installation

This guide will help you install Sepia in your Crystal project and set up the necessary dependencies.

## Adding Sepia to Your Project

### Using Shards

1. Add Sepia to your `shard.yml` file:

```yaml
dependencies:
  sepia:
    github: ralsina/sepia
```

2. Run the installation command:

```bash
shards install
```

3. Require Sepia in your Crystal code:

```crystal
require "sepia"
```

### Optional Dependencies

Sepia includes optional dependencies for enhanced functionality:

#### File System Watching

For cross-platform file system monitoring:

```yaml
dependencies:
  sepia:
    github: ralsina/sepia
  fswatch:
    github: bcardiff/crystal-fswatch
```

For Linux-native monitoring (recommended for Linux):

```yaml
dependencies:
  sepia:
    github: ralsina/sepia
  inotify:
    github: petoem/inotify.cr
```

#### Static Builds

If you're building a static binary, you can compile without fswatch:

```bash
crystal build src/your_app.cr -D no_fswatch
```

Sepia will automatically use a no-op fallback for file watching when fswatch is not available.

## Basic Configuration

After installation, configure Sepia to use your preferred storage backend:

```crystal
require "sepia"

# Use the default filesystem backend
Sepia::Storage.configure(:filesystem, {"path" => "./data"})

# Or use in-memory storage (useful for testing)
Sepia::Storage.configure(:memory)
```

## Verifying Installation

Create a simple test to verify Sepia is working:

```crystal
require "sepia"

class TestObject < Sepia::Object
  include Sepia::Serializable

  property name : String

  def initialize(@name = "")
  end

  def to_sepia : String
    @name
  end

  def self.from_sepia(sepia_string : String) : self
    new(sepia_string)
  end
end

# Configure storage
Sepia::Storage.configure(:filesystem, {"path" => "./test_data"})

# Create and save an object
obj = TestObject.new("Hello Sepia!")
obj.save

puts "Sepia is working! Object saved with ID: #{obj.sepia_id}"
```

Run this with:

```bash
crystal run test_installation.cr
```

If successful, you should see output similar to:

```
Sepia is working! Object saved with ID: test-object-123e4567-e89b-12d3-a456-426614174000
```

## Next Steps

Now that Sepia is installed, let's move on to the [Quick Start](quick-start.md) guide to create your first persistent objects!
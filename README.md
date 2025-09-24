# Sepia

Sepia is a simple, file-system-based serialization library for Crystal. It provides two modules, `Sepia::Serializable` and `Sepia::Container`, to handle the persistence of objects to disk.

## Core Concepts

- **`Sepia::Serializable`**: Objects that include this module are serialized to a single file. The content of the file is determined by the object's `to_sepia` method. These objects are stored in a "canonical" location based on their class name and `sepia_id`.

- **`Sepia::Container`**: Objects that include this module are serialized as directories. They can contain other `Serializable` or `Container` objects.
  - Nested `Serializable` objects are stored as symlinks to their canonical file.
  - Nested `Container` objects are stored as subdirectories, creating a nested on-disk structure that mirrors the object hierarchy.

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

  property boards : Array(Board)
  property postits : Array(Postit)

  def initialize(@boards = [] of Board, @postits = [] of Postit); end
end

# --- Create and Save ---

# A top-level board for "Work"
work_board = Board.new
work_board.sepia_id = "work_board"

# A nested board for "Project X"
project_x_board = Board.new
project_x_board.sepia_id = "project_x" # This ID is only used for top-level objects

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
│       ├── boards
│       │   └── project_x
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
- The `Postit` objects are stored in the canonical `Postit` directory and are referenced by symlinks.

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

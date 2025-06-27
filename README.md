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

## Usage

Here's a simple example demonstrating how to use `Sepia` to save and load a nested structure of "Boards" and "Post-its".

```crystal
require "sepia"

# Configure Sepia to use a local directory for storage.
Sepia::Storage::INSTANCE.path = "./_data"

# A Postit is a simple Serializable object.
class Postit
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
class Board
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
│       │           └── 0 -> ./_data/Postit/code_review_postit
│       └── postits
│           └── 0 -> ./_data/Postit/report_postit
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

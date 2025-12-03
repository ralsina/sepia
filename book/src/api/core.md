# Core Modules

## Sepia::Object

Base class for all objects managed by Sepia. Provides generation tracking, automatic ID generation, and core persistence methods.

### Key Features

- **Automatic UUID generation** when no custom `sepia_id` is provided
- **Generation tracking** for optimistic concurrency control
- **Sanitized IDs** - forward slashes in custom IDs are automatically replaced with underscores
- **Core persistence methods**: `save`, `load`, `delete`, `exists?`
- **Backup integration**: `backup_to`, `create_backup`

### Core Methods

#### ID Management

- `sepia_id : String` - Returns the object's unique identifier
- `sepia_id=(id : String)` - Sets the identifier (sanitizes slashes)
- `canonical_path : String` - Returns the filesystem path for this object

#### Generation Tracking

- `generation : Int32` - Returns the generation number from the ID
- `base_id : String` - Returns the ID without generation suffix
- `save_with_generation(metadata = nil)` - Creates a new version with incremented generation
- `latest(base_id : String)` - Returns the latest version of an object
- `versions(base_id : String)` - Returns all versions of an object

#### Persistence

- `save(metadata = nil)` - Saves the object to storage
- `save(*, force_new_generation : Bool, metadata = nil)` - Saves with forced new generation
- `load(id : String, path : String? = nil)` - Loads an object (generation-transparent)
- `delete` - Removes the object from storage
- `exists?(id : String)` - Checks if an object exists

#### Backup

- `backup_to(output_path : String)` - Creates backup with this object as root
- `create_backup(backup_dir = ".", include_timestamp = true)` - Creates timestamped backup
- `backup_supported?` - Checks if current backend supports backup

## Sepia::Serializable

Module for objects that serialize to single files. Objects using this module are stored as individual files in the canonical storage location.

### Requirements

Classes must implement:
- `to_sepia : String` - Convert object to string representation
- `self.from_sepia(sepia_string : String) : self` - Create object from string

### Example

```crystal
class MyDocument < Sepia::Object
  include Sepia::Serializable

  property title : String
  property content : String

  def initialize(@title = "", @content = "")
  end

  def to_sepia : String
    {@title, @content}.to_json
  end

  def self.from_sepia(sepia_string : String) : self
    data = JSON.parse(sepia_string)
    new(data["title"].as_s, data["content"].as_s)
  end
end
```

## Sepia::Container

Module for objects that serialize as directories and can contain other Sepia objects. Containers store primitive properties in a `data.json` file and nested objects in a `refs/` directory.

### Features

- **Nested object storage** - Can contain Serializable and Container objects
- **Collection support** - Handles Arrays, Sets, and Hashes of Sepia objects
- **Symlink references** - Uses symbolic links to avoid data duplication
- **Automatic relationship tracking** - Maintains object graphs through references

### Example

```crystal
class Project < Sepia::Object
  include Sepia::Container

  property name : String
  property documents : Array(MyDocument) = [] of MyDocument
  property owner : User?

  def initialize(@name = "")
  end
end
```

### Storage Structure

```
storage_path/Project/project-id/
├── data.json           # Primitive properties (name, etc.)
└── refs/
    ├── documents/
    │   ├── doc-1       # Symlink to canonical document
    │   └── doc-2       # Symlink to canonical document
    └── owner/
        └── user-123     # Symlink to canonical user
```

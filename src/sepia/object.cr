require "uuid"

module Sepia
  # Base class for all objects managed by Sepia.
  #
  # Provides generation tracking functionality for optimistic concurrency control,
  # automatic ID generation with UUIDs, and core persistence methods.
  #
  # All classes that use Sepia's serialization features must inherit from this class.
  #
  # ### Example
  #
  # ```
  # class MyDocument < Sepia::Object
  #   include Sepia::Serializable
  #
  #   property content : String
  #
  #   def initialize(@content = "")
  #   end
  #
  #   def to_sepia : String
  #     @content
  #   end
  #
  #   def self.from_sepia(sepia_string : String) : self
  #     new(sepia_string)
  #   end
  # end
  #
  # doc = MyDocument.new("Hello, World!")
  # doc.save # Saves to storage with auto-generated UUID
  # ```
  class Object
    # Separator character used between base ID and generation number.
    #
    # Default is "." which creates IDs like "note-123.1", "note-123.2".
    # Can be overridden per class if needed.
    #
    # ```
    # class CustomNote < Sepia::Object
    #   class_property generation_separator = "_"
    # end
    #
    # note = CustomNote.new
    # note.save_with_generation # ID becomes "note-uuid_1"
    # ```
    class_property generation_separator = "."

    # Unique identifier for this object.
    #
    # Defaults to a randomly generated UUIDv4 string. Can be manually set
    # for specific use cases or when restoring objects with known IDs.
    #
    # The ID format may include generation suffixes for version tracking:
    # - Without generation: "note-123e4567-e89b-12d3-a456-426614174000"
    # - With generation: "note-123e4567-e89b-12d3-a456-426614174000.1"
    #
    # ```
    # obj = MyClass.new
    # obj.sepia_id # => "myclass-uuid-string"
    #
    # # Manually set ID
    # obj.sepia_id = "custom-id"
    # ```
    getter sepia_id : String = UUID.random.to_s

    # Sets the unique identifier for this object.
    #
    # Use this when you need to control the object's ID, such as when
    # restoring from external data or maintaining specific naming conventions.
    #
    # Note: Forward slashes ("/") are automatically replaced with underscores ("_")
    # to prevent unintended subdirectory creation in the filesystem storage.
    #
    # ```
    # obj = MyClass.new
    # obj.sepia_id = "document-2024-001"
    # obj.sepia_id = "path/to/document" # Becomes "path_to_document"
    # ```
    def sepia_id=(id : String)
      @sepia_id = id.gsub('/', '_')
    end

    # Returns the generation number extracted from the object's ID.
    #
    # For IDs without a generation suffix, returns 0.
    #
    # ```
    # obj.sepia_id = "note-123.2"
    # obj.generation # => 2
    #
    # obj.sepia_id = "legacy-note"
    # obj.generation # => 0
    # ```
    def generation : Int32
      parts = @sepia_id.split(self.class.generation_separator)
      if parts.size > 1 && parts.last.matches?(/^\d+$/)
        parts.last.to_i
      else
        0 # No generation suffix means generation 0
      end
    end

    # Returns the base ID without the generation suffix.
    #
    # The base ID is the unique identifier that remains constant across all generations.
    #
    # ```
    # obj.sepia_id = "note-123.2"
    # obj.base_id # => "note-123"
    #
    # obj.sepia_id = "legacy-note"
    # obj.base_id # => "legacy-note"
    # ```
    def base_id : String
      parts = @sepia_id.split(self.class.generation_separator)
      if parts.size > 1 && parts.last.matches?(/^\d+$/)
        parts[0..-2].join(self.class.generation_separator)
      else
        @sepia_id # No generation suffix
      end
    end

    # Checks if a newer version of this object exists.
    #
    # Returns true if an object with ID `base_id.(expected_generation + 1)` exists.
    # This is useful for optimistic concurrency control.
    #
    # ```
    # obj.sepia_id = "note-123.2"
    # obj.stale?(2) # => true if "note-123.3" exists
    # ```
    def stale?(expected_generation : Int32) : Bool
      self.class.exists?("#{base_id}#{self.class.generation_separator}#{expected_generation + 1}")
    end

    # Saves the object to storage with optional metadata.
    #
    # This is a convenience method that delegates to the global Storage API.
    # It automatically detects whether to create a new object or update an existing one.
    #
    # ### Parameters
    #
    # - *metadata* : Optional JSON-serializable metadata for event logging
    #
    # ### Returns
    #
    # The object itself (for method chaining)
    #
    # ### Example
    #
    # ```
    # note = Note.new("Hello World")
    # note.sepia_id = "my-note"
    #
    # # Simple save
    # note.save
    #
    # # Save with metadata
    # note.save(metadata: {"user" => "alice"})
    # ```
    def save(metadata = nil) : self
      Sepia::Storage.save(self, metadata: metadata)
      self
    end

    # Saves the object with forced new generation.
    #
    # This method always creates a new version regardless of whether the object
    # already exists in storage. Equivalent to save_with_generation but follows
    # the same method signature pattern as save().
    #
    # ### Parameters
    #
    # - *force_new_generation* : Always increment generation (set to true)
    # - *metadata* : Optional JSON-serializable metadata for event logging
    #
    # ### Returns
    #
    # The object itself (for method chaining)
    #
    # ### Example
    #
    # ```
    # note = Note.new("Hello World")
    # note.sepia_id = "my-note"
    #
    # # Always creates new version
    # note.save(force_new_generation: true, metadata: {"user" => "alice"})
    # ```
    def save(*, force_new_generation : Bool, metadata = nil)
      Sepia::Storage.save(self, metadata: metadata, force_new_generation: force_new_generation)
    end

    # Creates a new version of this object with an incremented generation number.
    #
    # Returns a new object instance with the same attributes but a new ID
    # containing the next generation number. The original object is not modified.
    #
    # ```
    # obj.sepia_id = "note-123.2"
    # new_obj = obj.save_with_generation
    # new_obj.sepia_id # => "note-123.3"
    # ```
    #
    # NOTE: This method requires the class to implement `to_sepia` and `from_sepia`
    # for Serializable objects. For Container objects, override this method.
    def save_with_generation(metadata = nil) : self
      new_id = "#{base_id}#{self.class.generation_separator}#{generation + 1}"

      # Check if we can use serialization (works for Serializable objects)
      if self.responds_to?(:to_sepia) && self.class.responds_to?(:from_sepia)
        new_obj = self.class.from_sepia(self.to_sepia)
        new_obj.sepia_id = new_id
        Sepia::Storage.save(new_obj, metadata: metadata)
        new_obj
      else
        # For Container objects, this method needs to be overridden
        # or the class must have a parameterless constructor
        raise "save_with_generation not implemented for #{self.class.name}. " +
              "Either implement to_sepia/from_sepia or override save_with_generation."
      end
    end

    # Find the latest version of an object by its base ID.
    #
    # Returns the object with the highest generation number, or `nil` if no versions exist.
    # This is useful for always retrieving the most recent version of an object.
    #
    # ```
    # # Get the latest version of a document
    # latest_doc = Document.latest("doc-123")
    # if latest_doc
    #   puts "Latest version: #{latest_doc.generation}"
    #   puts "Content: #{latest_doc.content}"
    # end
    #
    # # Always returns nil for non-existent base IDs
    # Document.latest("non-existent") # => nil
    # ```
    def self.latest(base_id : String) : self?
      all_versions = versions(base_id)
      all_versions.max_by(&.generation)
    end

    # Find all versions of an object by its base ID.
    #
    # Returns an array of all object versions, sorted by generation number in ascending order.
    # This allows you to access the complete version history of an object.
    #
    # ```
    # # Get all versions of a document
    # all_versions = Document.versions("doc-123")
    #
    # # Print version history
    # all_versions.each do |version|
    #   puts "Version #{version.generation}: #{version.created_at}"
    # end
    #
    # # versions are sorted by generation
    # all_versions.first.generation # => 0 (oldest)
    # all_versions.last.generation  # => 2 (newest)
    # ```
    #
    # Note: For FileStorage, this scans the directory and may be slow with many versions.
    # Consider caching or cleanup strategies for long-running applications.
    def self.versions(base_id : String) : Array(self)
      backend = Sepia::Storage.backend

      versions = [] of self

      if backend.is_a?(FileStorage)
        # File-based storage - scan directory
        class_dir = File.join(backend.path, self.name)
        return versions unless Dir.exists?(class_dir)

        Dir.each_child(class_dir) do |filename|
          if filename == base_id
            # Legacy object without generation
            begin
              obj = Sepia::Storage.load(self, filename)
              versions << obj
            rescue
              # Skip invalid files
            end
          elsif filename.starts_with?("#{base_id}#{generation_separator}")
            gen_part = filename[base_id.size + generation_separator.size..-1]
            if gen_part.matches?(/^\d+$/)
              begin
                obj = Sepia::Storage.load(self, filename)
                versions << obj
              rescue
                # Skip invalid files
              end
            end
          end
        end
      else
        # For other backends, try to find versions by checking consecutive generations
        gen = 0
        loop do
          begin
            obj = Sepia::Storage.load(self, "#{base_id}#{generation_separator}#{gen}")
            versions << obj
            gen += 1
          rescue
            break
          end
        end

        # Also check base_id without generation (generation 0)
        if versions.empty?
          begin
            obj = Sepia::Storage.load(self, base_id)
            versions << obj
          rescue
            # Not found
          end
        end
      end

      versions.sort_by(&.generation)
    end

    # Check if an object with the given ID exists in storage.
    #
    # Returns `true` if an object of this class with the specified ID exists,
    # `false` otherwise. This is useful for checking existence before loading
    # or verifying if a specific generation exists.
    #
    # ```
    # # Check if a specific version exists
    # if Document.exists?("doc-123.2")
    #   puts "Version 2 exists"
    # else
    #   puts "Version 2 does not exist"
    # end
    #
    # # Check for existence of legacy object (generation 0)
    # Document.exists?("legacy-doc") # => true if exists
    #
    # # Common pattern: check before creating new generation
    # unless Document.exists?("doc-123.3")
    #   # Safe to create version 3
    # end
    # ```
    def self.exists?(id : String) : Bool
      backend = Sepia::Storage.backend

      if backend.is_a?(FileStorage)
        object_path = File.join(backend.path, self.name, id)
        File.exists?(object_path)
      else
        # For other backends, try to load and catch error
        begin
          self.load(id)
          true
        rescue
          false
        end
      end
    end

    # Saves the object to storage.
    #
    # For Serializable objects, serializes the object using its `to_sepia` method.
    # For Container objects, creates a directory structure and saves all nested objects.
    #
    # The optional `path` parameter specifies where to save the object. If not provided,
    # uses the canonical path based on the object's class and sepia_id.
    #
    # ```
    # doc = MyDocument.new("Hello")
    # doc.save # Saves to default location
    #
    # # Save to specific path
    # doc.save("/custom/path")
    # ```
    def save(path : String? = nil)
      Sepia::Storage::INSTANCE.save(self, path)
    end

    # Loads an object from storage with transparent generation handling.
    #
    # **Generation-transparent loading:**
    # - If you specify a generation (e.g., "note-123.2"), loads that specific generation
    # - If you specify base ID only (e.g., "note-123"), automatically loads the latest generation
    # - If no generations exist, loads the base object
    #
    # This makes generations completely transparent - users get the latest content
    # by default without needing to think about versioning.
    #
    # ```
    # # Load the latest version automatically (most common case)
    # doc = MyDocument.load("doc-uuid")
    #
    # # Load a specific generation (rare, for version control)
    # old_doc = MyDocument.load("doc-uuid.1")
    #
    # # Load from custom path (still respects latest generation)
    # doc = MyDocument.load("doc-uuid", "/custom/path")
    # ```
    def self.load(id : String, path : String? = nil) : self
      # Check if a specific generation was requested
      if id.includes?(generation_separator)
        # Load the specific generation requested
        Sepia::Storage::INSTANCE.load(self, id, path)
      else
        # Base ID requested
        if path
          # Custom path - generations not supported, load directly
          Sepia::Storage::INSTANCE.load(self, id, path)
        else
          # Standard path - try to load latest generation first
          latest_obj = latest(id)
          if latest_obj
            latest_obj
          else
            # No generations exist, load the base object
            Sepia::Storage::INSTANCE.load(self, id, path)
          end
        end
      end
    end

    # Deletes the object from storage.
    #
    # Removes the object's file or directory from storage. For Container objects,
    # also cleans up any nested objects and references.
    #
    # ```
    # doc = MyDocument.load("doc-uuid")
    # doc.delete # Removes the document from storage
    # ```
    def delete
      Sepia::Storage::INSTANCE.delete(self)
    end

    # Returns the canonical path for this object in storage.
    #
    # The canonical path follows the pattern: `{storage_path}/{ClassName}/{sepia_id}`.
    # This is where Serializable objects are stored by default.
    #
    # ```
    # doc = MyDocument.new
    # doc.sepia_id = "my-doc"
    # doc.canonical_path # => "/tmp/storage/MyDocument/my-doc"
    # ```
    def canonical_path : String
      File.join(Sepia::Storage::INSTANCE.path, self.class.name, sepia_id)
    end

    # ## Backup Methods

    # Creates a backup of this object and all its referenced objects.
    #
    # This is a convenience method that creates a backup containing this object
    # as the root and automatically includes all objects it references.
    #
    # ### Parameters
    #
    # - *output_path* : Path where the backup tar file will be created
    #
    # ### Returns
    #
    # The path to the created backup file
    #
    # ### Example
    #
    # ```
    # # Backup a project and all its documents
    # project = Project.load("project-123")
    # backup_path = project.backup_to("project_backup.tar")
    #
    # # Auto-generate timestamped backup name
    # backup_path = user.backup_to("user_backup_#{Time.utc.to_unix}.tar")
    # ```
    #
    # ### Raises
    #
    # - `Sepia::Backup::BackendNotSupportedError` if storage doesn't support backups
    # - `Sepia::Backup::BackupCreationError` if backup creation fails
    def backup_to(output_path : String) : String
      Sepia::Storage.backup(self, output_path)
    end

    # Creates a backup with an auto-generated timestamped filename.
    #
    # Convenience method that generates a backup filename based on the object's
    # class name and ID with a timestamp.
    #
    # ### Parameters
    #
    # - *backup_dir* : Directory where the backup will be created (defaults to current directory)
    # - *include_timestamp* : Whether to include timestamp in filename (default: true)
    #
    # ### Returns
    #
    # The path to the created backup file
    #
    # ### Example
    #
    # ```
    # # Create timestamped backup in current directory
    # backup_path = document.create_backup
    # # => "Document_doc123_backup_1703123456.tar"
    #
    # # Create backup in specific directory without timestamp
    # backup_path = project.create_backup("/backups", include_timestamp: false)
    # # => "/backups/Project_project456_backup.tar"
    # ```
    def create_backup(backup_dir : String = ".", include_timestamp : Bool = true) : String
      Dir.mkdir_p(backup_dir) unless Dir.exists?(backup_dir)

      base_name = "#{self.class.name}_#{sepia_id}_backup"
      timestamp = include_timestamp ? "_#{Time.utc.to_unix}" : ""
      filename = "#{base_name}#{timestamp}.tar"
      output_path = File.join(backup_dir, filename)

      backup_to(output_path)
    end

    # Checks if this object can be backed up with the current storage backend.
    #
    # ### Returns
    #
    # `true` if backup is supported, `false` otherwise
    #
    # ### Example
    #
    # ```
    # if document.backup_supported?
    #   puts "Can create backup of this document"
    # else
    #   puts "Switch to FileStorage to enable backup"
    # end
    # ```
    def backup_supported? : Bool
      Sepia::Storage.backup_supported?
    end
  end
end

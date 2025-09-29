require "file_utils"
require "./storage_backend"

module Sepia
  # Central storage management class.
  #
  # The `Storage` class manages pluggable storage backends and provides
  # both a modern class-based API and backward compatibility with the
  # original singleton pattern.
  #
  # ⚠️ **WARNING**: The Storage API and backend interfaces are subject to change.
  # The on-disk format for the filesystem backend is not stable.
  #
  # ### Supported Backends
  #
  # - `:filesystem` - Default file-based storage (FileStorage)
  # - `:memory` - In-memory storage for testing (InMemoryStorage)
  #
  # ### Usage
  #
  # ```
  # # Configure storage backend
  # Sepia::Storage.configure(:filesystem, {"path" => "./data"})
  #
  # # Or use in-memory storage
  # Sepia::Storage.configure(:memory)
  #
  # # Class-based API (recommended)
  # Sepia::Storage.save(my_object)
  # loaded = Sepia::Storage.load(MyClass, "object-id")
  #
  # # Legacy singleton API (still supported)
  # Sepia::Storage::INSTANCE.save(my_object)
  # loaded = Sepia::Storage::INSTANCE.load(MyClass, "object-id")
  # ```
  class Storage
    # Current storage backend instance.
    #
    # Defaults to FileStorage using the system temporary directory.
    # Can be changed at runtime to switch storage backends.
    @@current_backend : StorageBackend = FileStorage.new(Dir.tempdir)

    # Legacy singleton instance for backward compatibility.
    #
    # Provides the same API as the class methods for existing code
    # that relies on the singleton pattern.
    INSTANCE = new

    # Returns the current storage backend.
    #
    # ### Returns
    #
    # The currently active StorageBackend instance.
    #
    # ### Example
    #
    # ```
    # backend = Sepia::Storage.backend
    # puts backend.class # => FileStorage or InMemoryStorage
    # ```
    def self.backend
      @@current_backend
    end

    # Sets the current storage backend.
    #
    # Allows switching to a different backend implementation at runtime.
    #
    # ### Parameters
    #
    # - *backend* : A StorageBackend instance to use
    #
    # ### Example
    #
    # ```
    # # Switch to custom backend
    # custom_backend = MyCustomStorage.new
    # Sepia::Storage.backend = custom_backend
    # ```
    def self.backend=(backend : StorageBackend)
      @@current_backend = backend
    end

    # Configures storage using a named backend.
    #
    # Provides a convenient way to configure common backends without
    # instantiating them manually.
    #
    # ### Parameters
    #
    # - *backend* : Symbol identifying the backend type (`:filesystem` or `:memory`)
    # - *config* : Optional configuration hash for the backend
    #
    # ### Configuration Options
    #
    # For `:filesystem` backend:
    # - `"path"`: Root directory path (defaults to system temp directory)
    #
    # For `:memory` backend:
    # - No configuration options available
    #
    # ### Example
    #
    # ```
    # # Configure filesystem storage with custom path
    # Sepia::Storage.configure(:filesystem, {"path" => "./app_data"})
    #
    # # Configure in-memory storage
    # Sepia::Storage.configure(:memory)
    # ```
    def self.configure(backend : Symbol, config = {} of String => String)
      case backend
      when :filesystem
        path = config["path"]? || Dir.tempdir
        self.backend = FileStorage.new(path)
      when :memory
        self.backend = InMemoryStorage.new
      else
        raise "Unknown storage backend: #{backend}"
      end
    end

    # Saves a Serializable object using the current backend.
    #
    # Delegates to the current storage backend's save method.
    #
    # ### Parameters
    #
    # - *object* : The Serializable object to save
    # - *path* : Optional custom save path
    #
    # ### Example
    #
    # ```
    # doc = MyDocument.new("Hello")
    # Sepia::Storage.save(doc) # Uses current backend
    # ```
    def save(object : Serializable, path : String? = nil)
      @@current_backend.save(object, path)
    end

    # Saves a Container object using the current backend.
    #
    # Delegates to the current storage backend's save method.
    #
    # ### Parameters
    #
    # - *object* : The Container object to save
    # - *path* : Optional custom save path
    #
    # ### Example
    #
    # ```
    # board = Board.new("My Board")
    # Sepia::Storage.save(board) # Uses current backend
    # ```
    def save(object : Container, path : String? = nil)
      @@current_backend.save(object, path)
    end

    # Loads an object using the current backend.
    #
    # Generic method that loads an object of the specified class.
    # The type parameter ensures type safety without requiring casting.
    #
    # ### Parameters
    #
    # - *object_class* : The class of object to load
    # - *id* : The object's unique identifier
    # - *path* : Optional custom load path
    #
    # ### Returns
    #
    # An instance of type T loaded from storage.
    #
    # ### Example
    #
    # ```
    # # Load with explicit type
    # doc = Sepia::Storage.load(MyDocument, "doc-uuid")
    #
    # # Type is inferred, no casting needed
    # puts doc.content # doc is typed as MyDocument
    # ```
    def load(object_class : T.class, id : String, path : String? = nil) : T forall T
      @@current_backend.load(object_class, id, path).as(T)
    end

    def delete(object : Serializable | Container)
      @@current_backend.delete(object)
    end

    # Legacy path property (only works with FileStorage)
    def path : String
      if @@current_backend.is_a?(FileStorage)
        @@current_backend.as(FileStorage).path
      else
        raise "path property is only available with FileStorage backend"
      end
    end

    def path=(path : String)
      if @@current_backend.is_a?(FileStorage)
        @@current_backend.as(FileStorage).path = path
      else
        raise "path property is only available with FileStorage backend"
      end
    end

    # Discovery API - delegates to current backend
    def self.list_all(object_class : Class) : Array(String)
      @@current_backend.list_all(object_class)
    end

    def self.exists?(object_class : Class, id : String) : Bool
      @@current_backend.exists?(object_class, id)
    end

    def self.count(object_class : Class) : Int32
      @@current_backend.count(object_class)
    end

    # Bulk operations
    def self.clear
      @@current_backend.clear
    end

    def self.export_data : Hash(String, Array(Hash(String, String)))
      @@current_backend.export_data
    end

    def self.import_data(data : Hash(String, Array(Hash(String, String))))
      @@current_backend.import_data(data)
    end

    def self.delete(class_name : String, id : String)
      @@current_backend.delete(class_name, id)
    end

    def self.list_all_objects : Hash(String, Array(String))
      @@current_backend.list_all_objects
    end

    def self.gc(roots : Enumerable(Sepia::Object), dry_run : Bool = false) : Hash(String, Array(String))
      # Phase 1: Mark
      live_object_keys = Set(String).new
      roots.each do |obj|
        mark_live_objects(obj, live_object_keys)
      end

      # Phase 2: Sweep
      deleted_keys = Hash(String, Array(String)).new { |hash, key| hash[key] = [] of String }
      all_objects = list_all_objects

      all_objects.each do |class_name, ids|
        ids.each do |id|
          key = "#{class_name}/#{id}"
          unless live_object_keys.includes?(key)
            # Orphaned object
            deleted_keys[class_name] << id
            unless dry_run
              delete(class_name, id)
            end
          end
        end
      end

      deleted_keys
    end

    private def self.mark_live_objects(object : Sepia::Object, live_set : Set(String))
      key = "#{object.class.name}/#{object.sepia_id}"
      return if live_set.includes?(key) # Already visited, stop recursion

      live_set.add(key)

      if object.responds_to?(:sepia_references)
        object.sepia_references.each do |child|
          mark_live_objects(child, live_set)
        end
      end
    end
  end
end

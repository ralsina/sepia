require "file_utils"
require "./storage_backend"
require "./file_storage"
require "./cache_manager"

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
    # - `"watch"`: Enable file system watcher (default: false)
    #   - `true`: Enable watcher with default settings
    #   - `false`: Disable watcher
    #   - `Hash`: Custom watcher configuration options
    #
    # For `:memory` backend:
    # - No configuration options available
    #
    # ### Examples
    #
    # ```
    # # Configure filesystem storage with custom path
    # Sepia::Storage.configure(:filesystem, {"path" => "./app_data"})
    #
    # # Configure filesystem storage with watcher enabled
    # Sepia::Storage.configure(:filesystem, {"watch" => true})
    #
    # # Configure filesystem storage with custom watcher settings
    # Sepia::Storage.configure(:filesystem, {
    #   "path"  => "./app_data",
    #   "watch" => {
    #     "recursive" => true,
    #     "latency"   => 0.1,
    #   },
    # })
    #
    # # Configure in-memory storage
    # Sepia::Storage.configure(:memory)
    # ```
    def self.configure(backend : Symbol, config : Hash(String, String | Bool | Hash(String, String)) = {} of String => String)
      case backend
      when :filesystem
        path = config["path"]? || Dir.tempdir

        # Handle watcher configuration
        watch_config = config["watch"]?
        if watch_config
          case watch_config
          when Bool
            # Simple boolean configuration
            self.backend = FileStorage.new(path.to_s, watch: watch_config)
          when Hash
            # Detailed watcher configuration
            self.backend = FileStorage.new(path.to_s, watch: watch_config)
          when String
            # String configuration - convert to boolean
            self.backend = FileStorage.new(path.to_s, watch: watch_config == "true")
          else
            # Other types - convert to boolean
            self.backend = FileStorage.new(path.to_s, watch: !!watch_config)
          end
        else
          # No watcher configuration
          self.backend = FileStorage.new(path.to_s)
        end
      when :memory
        self.backend = InMemoryStorage.new
      else
        raise "Unknown storage backend: #{backend}"
      end
    end

    # Saves a Serializable object using the current backend.
    #
    # Automatically caches the object for faster retrieval. Set `cache: false`
    # to disable caching for this operation.
    #
    # ### Parameters
    #
    # - *object* : The Serializable object to save
    # - *path* : Optional custom save path
    # - *cache* : Whether to cache the object (default: true)
    #
    # ### Example
    #
    # ```
    # doc = MyDocument.new("Hello")
    # Sepia::Storage.save(doc)               # Save with caching (default)
    # Sepia::Storage.save(doc, cache: false) # Save without caching
    # ```
    def save(object : Serializable, path : String? = nil, cache : Bool = true)
      # Save to backend first
      @@current_backend.save(object, path)

      # Update cache if enabled
      if cache
        cache_key = "#{object.class.name}:#{object.sepia_id}"
        CacheManager.instance.put(cache_key, object)
      end
    end

    # Saves a Container object using the current backend.
    #
    # Automatically caches the object for faster retrieval. Set `cache: false`
    # to disable caching for this operation.
    #
    # ### Parameters
    #
    # - *object* : The Container object to save
    # - *path* : Optional custom save path
    # - *cache* : Whether to cache the object (default: true)
    #
    # ### Example
    #
    # ```
    # board = Board.new("My Board")
    # Sepia::Storage.save(board)               # Save with caching (default)
    # Sepia::Storage.save(board, cache: false) # Save without caching
    # ```
    def save(object : Container, path : String? = nil, cache : Bool = true)
      # Save to backend first
      @@current_backend.save(object, path)

      # Update cache if enabled
      if cache
        cache_key = "#{object.class.name}:#{object.sepia_id}"
        CacheManager.instance.put(cache_key, object)
      end
    end

    # Loads an object using the current backend.
    #
    # First checks the cache for the object. If not found, loads from backend
    # and automatically caches the result for future retrievals. Set `cache: false`
    # to disable caching for this operation.
    #
    # ### Parameters
    #
    # - *object_class* : The class of object to load
    # - *id* : The object's unique identifier
    # - *path* : Optional custom load path
    # - *cache* : Whether to use cache (default: true)
    #
    # ### Returns
    #
    # An instance of type T loaded from storage.
    #
    # ### Example
    #
    # ```
    # # Load with caching (default)
    # doc = Sepia::Storage.load(MyDocument, "doc-uuid")
    #
    # # Load without caching
    # doc = Sepia::Storage.load(MyDocument, "doc-uuid", cache: false)
    #
    # # Type is inferred, no casting needed
    # puts doc.content # doc is typed as MyDocument
    # ```
    def load(object_class : T.class, id : String, path : String? = nil, cache : Bool = true) : T forall T
      if cache
        cache_key = "#{object_class.name}:#{id}"

        # Try cache first
        cached_object = CacheManager.instance.get(cache_key)
        if cached_object
          return cached_object.as(T)
        end

        # Load from backend and cache the result
        loaded_object = @@current_backend.load(object_class, id, path).as(T)
        CacheManager.instance.put(cache_key, loaded_object)
        loaded_object
      else
        # Load directly from backend without caching
        @@current_backend.load(object_class, id, path).as(T)
      end
    end

    def delete(object : Serializable | Container, cache : Bool = true)
      # Remove from cache first if enabled
      if cache
        cache_key = "#{object.class.name}:#{object.sepia_id}"
        CacheManager.instance.remove(cache_key)
      end

      # Delete from backend
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

    # Class methods with cache integration (caching is default)
    def self.save(object : Serializable, path : String? = nil, cache : Bool = true)
      INSTANCE.save(object, path, cache)
    end

    def self.save(object : Container, path : String? = nil, cache : Bool = true)
      INSTANCE.save(object, path, cache)
    end

    def self.load(object_class : T.class, id : String, path : String? = nil, cache : Bool = true) : T forall T
      INSTANCE.load(object_class, id, path, cache)
    end

    def self.delete(object : Serializable | Container, cache : Bool = true)
      INSTANCE.delete(object, cache)
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

    def self.delete(class_name : String, id : String, cache : Bool = true)
      # Remove from cache first if enabled
      if cache
        cache_key = "#{class_name}:#{id}"
        CacheManager.instance.remove(cache_key)
      end

      # Delete from backend
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

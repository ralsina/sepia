require "file_utils"
require "./storage_backend"

module Sepia
  # The `Storage` class manages storage backends and provides
  # backward compatibility with the original singleton API.
  class Storage
    # Class variable to hold the current backend
    @@current_backend : StorageBackend = FileStorage.new(Dir.tempdir)

    # Legacy singleton instance for backward compatibility
    INSTANCE = new

    # Get the current storage backend
    def self.backend
      @@current_backend
    end

    # Set the current storage backend
    def self.backend=(backend : StorageBackend)
      @@current_backend = backend
    end

    # Configure storage with a named backend
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

    # Legacy API - delegates to current backend
    def save(object : Serializable, path : String? = nil)
      @@current_backend.save(object, path)
    end

    def save(object : Container, path : String? = nil)
      @@current_backend.save(object, path)
    end

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
      deleted_keys = Hash(String, Array(String)).new { |h, k| h[k] = [] of String }
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

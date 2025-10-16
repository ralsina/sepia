require "file_utils"
require "./storage_backend"
require "./watcher"

module Sepia
  # Filesystem-based storage backend for Sepia objects.
  #
  # This is the default storage backend that stores objects on the local filesystem.
  # Serializable objects are stored as files, while Container objects are stored as
  # directories with nested structures.
  #
  # ### Directory Structure
  #
  # The storage creates a directory structure like:
  #
  # ```
  # storage_path/
  #   ├── ClassName1/
  #   │   ├── object1_id     (Serializable object file)
  #   │   └── object2_id     (Serializable object file)
  #   └── ClassName2/
  #       ├── container1/    (Container directory)
  #       │   ├── data.json  (Primitive properties)
  #       │   └── refs/      (Reference files/symlinks)
  #       └── container2/    (Container directory)
  # ```
  #
  # ### Example
  #
  # ```
  # # Configure Sepia to use filesystem storage
  # Sepia::Storage.configure(:filesystem, {"path" => "./data"})
  #
  # # Objects will be stored in ./data/ClassName/sepia_id
  # ```
  class FileStorage < StorageBackend
    # Root directory path where objects are stored.
    #
    # Default is the system's temporary directory. Can be set to any absolute path.
    #
    # ```
    # storage = FileStorage.new
    # storage.path # => "/tmp"
    #
    # # Custom path
    # storage = FileStorage.new("./my_data")
    # storage.path # => "./my_data"
    # ```
    property path : String

    # Creates a new FileStorage instance.
    #
    # The `path` parameter specifies the root directory where objects will be stored.
    # If not provided, uses the system's temporary directory.
    #
    # ```
    # # Use system temp directory
    # storage = FileStorage.new
    #
    # # Use custom directory
    # storage = FileStorage.new("./data")
    #
    # # Use absolute path
    # storage = FileStorage.new("/var/lib/myapp/data")
    # ```
    def initialize(@path : String = Dir.tempdir)
    end

    # Saves a Serializable object to the filesystem.
    #
    # Writes the object's serialized content to a file. Creates any necessary
    # parent directories. Uses atomic write operations to prevent corruption.
    #
    # The object is saved to `path/class_name/sepia_id` if no specific path is provided.
    #
    # ### Atomic Writes
    #
    # The file is first written to a temporary file (with .tmp extension),
    # then atomically renamed to the final path. This prevents partial writes
    # and ensures data integrity.
    #
    # ```
    # doc = MyDocument.new("Hello")
    # storage = FileStorage.new("./data")
    # storage.save(doc) # Creates ./data/MyDocument/uuid
    # ```
    def save(object : Serializable, path : String? = nil)
      object_path = path || File.join(@path, object.class.name, object.sepia_id)
      object_dir = File.dirname(object_path)
      FileUtils.mkdir_p(object_dir) unless File.exists?(object_dir)

      # Track files to avoid triggering watcher callbacks
      temp_path = "#{object_path}.tmp"
      Watcher.add_internal_file(temp_path)
      Watcher.add_internal_file(object_path)

      begin
        # Atomic write: write to temp file first, then rename
        File.write(temp_path, object.to_sepia)
        File.rename(temp_path, object_path)
      ensure
        Watcher.remove_internal_file(temp_path)
        Watcher.remove_internal_file(object_path)
      end
    end

    # Saves a Container object to the filesystem.
    #
    # Creates a directory for the container and saves all nested objects and
    # references. The container's primitive properties are saved to a data.json file,
    # while nested Sepia objects are saved as files or symlinks.
    #
    # ```
    # board = Board.new("My Board")
    # storage = FileStorage.new("./data")
    # storage.save(board) # Creates ./data/Board/uuid/
    # ```
    def save(object : Container, path : String? = nil)
      object_path = path || File.join(@path, object.class.name, object.sepia_id)
      FileUtils.mkdir_p(object_path)

      # Track the container directory to avoid triggering watcher callbacks
      Watcher.add_internal_file(object_path)

      begin
        object.save_references(object_path)
      ensure
        Watcher.remove_internal_file(object_path)
      end
    end

    # Loads an object from the filesystem.
    #
    # Deserializes an object of the specified class with the given ID.
    # For Serializable objects, reads the file content and uses the class's
    # `from_sepia` method. For Container objects, reconstructs the object
    # from its directory structure.
    #
    # Raises an exception if the object is not found.
    #
    # ```
    # # Load a Serializable object
    # doc = storage.load(MyDocument, "doc-uuid")
    #
    # # Load a Container object
    # board = storage.load(MyBoard, "board-uuid")
    # ```
    def load(object_class : Class, id : String, path : String? = nil) : Object
      object_path = path || File.join(@path, object_class.to_s, id)

      case
      when object_class.responds_to?(:from_sepia)
        unless File.exists?(object_path)
          raise "Object with ID #{id} not found in storage for type #{object_class}."
        end
        obj = object_class.from_sepia(File.read(object_path))
        obj.sepia_id = id
        obj
      when object_class < Container
        unless File.directory?(object_path)
          raise "Object with ID #{id} not found in storage for type #{object_class} (directory missing)."
        end
        obj = object_class.new
        obj.sepia_id = id
        obj.as(Container).load_references(object_path)
        obj
      else
        raise "Unsupported class for Sepia storage: #{object_class.name}. Must include Sepia::Serializable or Sepia::Container."
      end
    end

    # Deletes an object from the filesystem.
    #
    # Removes the object's file or directory. For Container objects, recursively
    # removes the entire directory structure including all nested objects.
    #
    # ```
    # doc = MyDocument.load("doc-uuid")
    # storage.delete(doc) # Removes the file
    #
    # board = Board.load("board-uuid")
    # storage.delete(board) # Removes the directory and all contents
    # ```
    def delete(object : Serializable | Container)
      object_path = File.join(@path, object.class.name, object.sepia_id)

      # Track the path to avoid triggering watcher callbacks
      Watcher.add_internal_file(object_path)

      begin
        if object.is_a?(Serializable)
          if File.exists?(object_path)
            File.delete(object_path)
          end
        elsif object.is_a?(Container)
          if Dir.exists?(object_path)
            FileUtils.rm_rf(object_path)
          end
        end
      ensure
        Watcher.remove_internal_file(object_path)
      end
    end

    # Deletes an object by class name and ID.
    #
    # Alternative method to delete objects without loading them first.
    # Requires knowing whether the class is a Container or Serializable type.
    #
    # ```
    # # Delete without loading the object
    # storage.delete("MyDocument", "doc-uuid")
    # storage.delete("MyBoard", "board-uuid")
    # ```
    def delete(class_name : String, id : String)
      object_path = File.join(@path, class_name, id)

      # Track the path to avoid triggering watcher callbacks
      Watcher.add_internal_file(object_path)

      begin
        if Sepia.container?(class_name)
          if Dir.exists?(object_path)
            FileUtils.rm_rf(object_path)
          end
        else
          if File.exists?(object_path)
            File.delete(object_path)
          end
        end
      ensure
        Watcher.remove_internal_file(object_path)
      end
    end

    # Lists all object IDs for a given class.
    #
    # Returns an array of all object IDs found in the class directory.
    # The IDs are sorted alphabetically.
    #
    # ```
    # ids = storage.list_all(MyDocument)
    # ids # => ["doc-uuid1", "doc-uuid2", "doc-uuid3"]
    # ```
    def list_all(object_class : Class) : Array(String)
      class_dir = File.join(@path, object_class.to_s)
      return [] of String unless Dir.exists?(class_dir)

      Dir.entries(class_dir)
        .reject { |e| e == "." || e == ".." }
        .select { |e| File.file?(File.join(class_dir, e)) || File.directory?(File.join(class_dir, e)) }
        .sort!
    end

    # Checks if an object with the given ID exists.
    #
    # For Serializable objects, checks if the file exists.
    # For Container objects, checks if the directory exists.
    #
    # ```
    # if storage.exists?(MyDocument, "doc-uuid")
    #   puts "Document exists"
    # end
    # ```
    def exists?(object_class : Class, id : String) : Bool
      object_path = File.join(@path, object_class.to_s, id)

      if object_class < Serializable
        File.exists?(object_path)
      elsif object_class < Container
        File.directory?(object_path)
      else
        false
      end
    end

    # Returns the count of objects for a given class.
    #
    # This is equivalent to `list_all(object_class).size` but may be
    # more efficient in some implementations.
    #
    # ```
    # count = storage.count(MyDocument)
    # puts "Found #{count} documents"
    # ```
    def count(object_class : Class) : Int32
      list_all(object_class).size
    end

    # Clears all objects from storage.
    #
    # Removes the entire storage directory and recreates it.
    # This permanently deletes all data - use with caution.
    #
    # ```
    # storage.clear # Deletes everything in the storage path
    # ```
    def clear
      if Dir.exists?(@path)
        FileUtils.rm_rf(@path)
        FileUtils.mkdir_p(@path)
      end
    end

    # Exports all data as a portable hash structure.
    #
    # Returns a hash where keys are class names and values are arrays of
    # object data. Each object includes its ID and either its content
    # (for Serializable objects) or a container type marker.
    #
    # Useful for backing up or migrating data between storage backends.
    #
    # ```
    # data = storage.export_data
    # # data = {
    # #   "MyDocument" => [
    # #     {"id" => "doc1", "content" => "Hello"},
    # #     {"id" => "doc2", "content" => "World"}
    # #   ],
    # #   "MyBoard" => [
    # #     {"id" => "board1", "type" => "container"}
    # #   ]
    # # }
    # ```
    def export_data : Hash(String, Array(Hash(String, String)))
      data = {} of String => Array(Hash(String, String))

      return data unless Dir.exists?(@path)

      Dir.each_child(@path) do |class_name|
        class_dir = File.join(@path, class_name)
        next unless File.directory?(class_dir)

        data[class_name] = [] of Hash(String, String)

        Dir.each_child(class_dir) do |id|
          object_path = File.join(class_dir, id)

          if File.file?(object_path)
            # It's a serializable object
            data[class_name] << {
              "id"      => id,
              "content" => File.read(object_path),
            }
          elsif File.directory?(object_path)
            # It's a container object
            data[class_name] << {
              "id"   => id,
              "type" => "container",
            }
          end
        end
      end

      data
    end

    # Imports data from an exported hash structure.
    #
    # Restores objects from the data structure created by `export_data`.
    # Clears any existing data before importing.
    #
    # Useful for restoring backups or migrating from another storage backend.
    #
    # ```
    # data = {
    #   "MyDocument" => [
    #     {"id" => "doc1", "content" => "Hello"},
    #   ],
    # }
    # storage.import_data(data)
    # ```
    def import_data(data : Hash(String, Array(Hash(String, String))))
      clear

      data.each do |class_name, objects|
        class_dir = File.join(@path, class_name)
        FileUtils.mkdir_p(class_dir)

        objects.each do |obj_data|
          object_path = File.join(class_dir, obj_data["id"])

          if obj_data.has_key?("content")
            # It's a serializable object
            File.write(object_path, obj_data["content"])
          elsif obj_data["type"]? == "container"
            # It's a container object
            FileUtils.mkdir_p(object_path)
          end
        end
      end
    end

    # Lists all objects grouped by class name.
    #
    # Returns a hash where keys are class names and values are arrays of
    # object IDs for that class. This provides a complete inventory of
    # all objects in storage.
    #
    # Useful for administrative purposes, data migration, or debugging.
    #
    # ```
    # all_objects = storage.list_all_objects
    # # all_objects = {
    # #   "MyDocument" => ["doc1", "doc2"],
    # #   "MyBoard" => ["board1"],
    # #   "User" => ["user1", "user2", "user3"]
    # # }
    # ```
    def list_all_objects : Hash(String, Array(String))
      objects = Hash(String, Array(String)).new { |hash, key| hash[key] = [] of String }
      return objects unless Dir.exists?(@path)

      Dir.each_child(@path) do |class_name|
        class_dir = File.join(@path, class_name)
        next unless File.directory?(class_dir)

        Dir.each_child(class_dir) do |id|
          objects[class_name] << id
        end
      end
      objects
    end
  end
end

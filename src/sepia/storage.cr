require "file_utils"

module Sepia
  # The `Storage` class is responsible for handling the persistence of
  # `Sepia::Serializable` and `Sepia::Container` objects to the file system.
  # It manages saving and loading these objects based on their `sepia_id`
  # and class name, and provides a configurable storage path.
  class Storage
    INSTANCE = new

    # By default, the storage path is a temporary directory.
    getter path : String = Dir.tempdir

    # But user can override it.
    # Sets the storage path. This is where all serialized objects will be stored.
    def path=(path : String)
      @path = path
    end

    # Saves a Serializable object to its canonical path.
    # The object's `to_sepia` method is used to get the content to be saved.
    def save(object : Serializable, path : String? = nil)
      object_path = path || File.join(@path, object.class.name, "#{object.sepia_id}")
      object_dir = File.dirname(object_path)
      FileUtils.mkdir_p(object_dir) unless File.exists?(object_dir)
      File.write(object_path, object.to_sepia)
    end

    # Saves a Container object to its canonical path as a directory.
    # The container's `save_references` method is called to save its contents.
    def save(object : Container, path : String? = nil)
      object_path = path || File.join(@path, object.class.name, "#{object.sepia_id}")
      FileUtils.mkdir_p(object_path) # Create a directory for the container
      object.save_references(object_path)
    end

    # Load an object from the canonical path in sepia format.
    # T must be a class that includes Sepia::Serializable or Sepia::Container.
    def load(object_class : T.class, id : String) : T forall T
      object_path_base = File.join(@path, object_class.to_s, id)

      case
      when object_class.responds_to?(:from_sepia) # This implies it's a Serializable
        unless File.exists?(object_path_base)
          raise "Object with ID #{id} not found in storage for type #{object_class}."
        end
        obj = object_class.from_sepia(File.read(object_path_base))
        obj.sepia_id = id
        obj
      when object_class < Container              # This implies it's a Container
        unless File.directory?(object_path_base) # Containers are directories
          raise "Object with ID #{id} not found in storage for type #{object_class} (directory missing)."
        end
        obj = object_class.new
        obj.sepia_id = id
        obj.as(Container).load_references(object_path_base)
        obj
      else
        # If it's neither Serializable nor Container, it's an unsupported type for Sepia storage
        raise "Unsupported class for Sepia storage: #{object_class.name}. Must include Sepia::Serializable or Sepia::Container."
      end
    end

    def delete(object : Serializable)
      object_path = File.join(@path, object.class.name, "#{object.sepia_id}")
      if File.exists?(object_path)
        File.delete(object_path)
      else
        raise "Object with ID #{object.sepia_id} not found in storage for type #{object.class.name}."
      end
    end

    def delete(object : Container)
      object_path = File.join(@path, object.class.name, "#{object.sepia_id}")
      if Dir.exists?(object_path)
        FileUtils.rm_rf(object_path)
      else
        raise "Container with ID #{object.sepia_id} not found in storage for type #{object.class.name}."
      end
    end
  end
end

require "file_utils"

module Sepia
  VERSION = "0.1.0"

  class Storage
    INSTANCE = new

    # By default, the storage path is a temporary directory.
    getter path : String = Dir.tempdir

    # But user can override it.
    def path=(path : String)
      @path = path
    end

    # Save the object to the canonical path in sepia format.
    def save(object : Serializable)
      type_name = object.class.name
      object_dir = File.join(@path, type_name)
      FileUtils.mkdir_p(object_dir) unless File.exists?(object_dir)
      object_path = File.join(object_dir, "#{object.sepia_id}")
      File.write(object_path, object.to_sepia)
    end

    # Saves the container object to the canonical path as a folder of references
    def save(object : Container)
      type_name = object.class.name
      object_dir = File.join(@path, type_name)
      object_path = File.join(object_dir, "#{object.sepia_id}")
      FileUtils.mkdir_p(object_path) # Create a directory for the container
      object.save_references(object_path)
    end

    # Load an object from the canonical path in sepia format.
    # T must be a class that includes Sepia::Serializable or Sepia::Container.
    def load(object_class : T.class, id : String) : T forall T
      type_name = object_class.to_s
      object_path_base = File.join(@path, type_name, id)

      if object_class.responds_to?(:from_sepia) # This implies it's a Serializable
        unless File.exists?(object_path_base)
          raise "Object with ID #{id} not found in storage for type #{type_name}."
        end
        obj = object_class.from_sepia(File.read(object_path_base))
        obj.sepia_id = id
        obj
      elsif object_class < Container             # This implies it's a Container
        unless File.directory?(object_path_base) # Containers are directories
          raise "Object with ID #{id} not found in storage for type #{type_name} (directory missing)."
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
  end
end

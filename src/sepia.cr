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
      type_name = typeof(object).to_s
      object_dir = File.join(@path, type_name.to_s)
      FileUtils.mkdir_p(object_dir) unless File.exists?(object_dir)
      object_path = File.join(object_dir, "#{object.sepia_id}")
      File.write(object_path, object.to_sepia)
    end

    # Saves the container object to the canonical path as a folder of references
    def save(object : Container)
      type_name = typeof(object).to_s
      object_dir = File.join(@path, type_name.to_s)
      object_path = File.join(object_dir, "#{object.sepia_id}")
      FileUtils.mkdir_p(object_path) # Create a directory for the container
      object.save_references(object_path)
    end

    # Load the object from the canonical path in sepia format.
    def load(object_class, id : String)
      if object_class.responds_to?(:from_sepia)
        type_name = object_class.to_s
        object_path = File.join(@path, type_name, id)
        if File.exists?(object_path)
          object_class.from_sepia(File.read(object_path))
        else
          raise "Object with ID #{id} not found in storage."
        end
      else
        type_name = object_class.to_s
        object_path = File.join(@path, type_name, id)
        if File.exists?(object_path)
          # Here we would load the container's contents, but for now we just return a new instance
          obj = object_class.new
          obj.sepia_id = id
          obj
        end
      end
    end
  end
end

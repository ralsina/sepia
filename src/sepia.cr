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

    # Load the object from the canonical path in sepia format.
    def load(object_class, id : String)
      type_name = object_class.to_s
      object_path = File.join(@path, type_name, id)
      if File.exists?(object_path)
        object_class.from_sepia(File.read(object_path))
      else
        raise "Object with ID #{id} not found in storage."
      end
    end
  end
end

require "./sepia/*"

require "file_utils"
require "./storage_backend"

module Sepia
  # Filesystem-based storage backend (original implementation).
  # This maintains backward compatibility with the existing Sepia behavior.
  class FileStorage < StorageBackend
    property path : String

    def initialize(@path : String = Dir.tempdir)
    end

    def save(object : Serializable, path : String? = nil)
      object_path = path || File.join(@path, object.class.name, object.sepia_id)
      object_dir = File.dirname(object_path)
      FileUtils.mkdir_p(object_dir) unless File.exists?(object_dir)

      # Atomic write: write to temp file first, then rename
      temp_path = "#{object_path}.tmp"
      File.write(temp_path, object.to_sepia)
      File.rename(temp_path, object_path)
    end

    def save(object : Container, path : String? = nil)
      object_path = path || File.join(@path, object.class.name, object.sepia_id)
      FileUtils.mkdir_p(object_path)
      object.save_references(object_path)
    end

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

    def delete(object : Serializable | Container)
      object_path = File.join(@path, object.class.name, object.sepia_id)

      if object.is_a?(Serializable)
        if File.exists?(object_path)
          File.delete(object_path)
        end
      elsif object.is_a?(Container)
        if Dir.exists?(object_path)
          FileUtils.rm_rf(object_path)
        end
      end
    end

    def delete(class_name : String, id : String)
      object_path = File.join(@path, class_name, id)
      if Sepia.container?(class_name)
        if Dir.exists?(object_path)
          FileUtils.rm_rf(object_path)
        end
      else
        if File.exists?(object_path)
          File.delete(object_path)
        end
      end
    end

    def list_all(object_class : Class) : Array(String)
      class_dir = File.join(@path, object_class.to_s)
      return [] of String unless Dir.exists?(class_dir)

      Dir.entries(class_dir)
        .reject { |e| e == "." || e == ".." }
        .select { |e| File.file?(File.join(class_dir, e)) || File.directory?(File.join(class_dir, e)) }
        .sort!
    end

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

    def count(object_class : Class) : Int32
      list_all(object_class).size
    end

    def clear
      if Dir.exists?(@path)
        FileUtils.rm_rf(@path)
        FileUtils.mkdir_p(@path)
      end
    end

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

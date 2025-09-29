require "uuid"

module Sepia
  class Object
    # Generation separator for versioning
    class_property generation_separator = "."

    # Sepia objects MUST have a sepia_id property which defaults to a lazy UUID
    getter sepia_id : String = UUID.random.to_s

    def sepia_id=(id : String)
      @sepia_id = id
    end

    # Extract generation from current ID
    def generation : Int32
      parts = @sepia_id.split(self.class.generation_separator)
      if parts.size > 1 && parts.last.matches?(/^\d+$/)
        parts.last.to_i
      else
        0 # No generation suffix means generation 0
      end
    end

    # Get base ID without generation
    def base_id : String
      parts = @sepia_id.split(self.class.generation_separator)
      if parts.size > 1 && parts.last.matches?(/^\d+$/)
        parts[0..-2].join(self.class.generation_separator)
      else
        @sepia_id # No generation suffix
      end
    end

    # Check if object has newer version
    def stale?(expected_generation : Int32) : Bool
      self.class.exists?("#{base_id}#{self.class.generation_separator}#{expected_generation + 1}")
    end

    # Create new version with incremented generation
    def save_with_generation : self
      new_id = "#{base_id}#{self.class.generation_separator}#{generation + 1}"

      # Check if we can use serialization (works for Serializable objects)
      if self.responds_to?(:to_sepia) && self.class.responds_to?(:from_sepia)
        new_obj = self.class.from_sepia(self.to_sepia)
        new_obj.sepia_id = new_id
        new_obj.save
        new_obj
      else
        # For Container objects, this method needs to be overridden
        # or the class must have a parameterless constructor
        raise "save_with_generation not implemented for #{self.class.name}. " +
              "Either implement to_sepia/from_sepia or override save_with_generation."
      end
    end

    # Find latest version
    def self.latest(base_id : String) : self?
      all_versions = versions(base_id)
      all_versions.max_by(&.generation)
    end

    # Find all versions sorted by generation
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
              obj = self.load(filename)
              versions << obj
            rescue
              # Skip invalid files
            end
          elsif filename.starts_with?("#{base_id}#{generation_separator}")
            gen_part = filename[base_id.size + generation_separator.size..-1]
            if gen_part.matches?(/^\d+$/)
              begin
                obj = self.load(filename)
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
        while true
          begin
            obj = self.load("#{base_id}#{generation_separator}#{gen}")
            versions << obj
            gen += 1
          rescue
            break
          end
        end

        # Also check base_id without generation (generation 0)
        if versions.empty?
          begin
            obj = self.load(base_id)
            versions << obj
          rescue
            # Not found
          end
        end
      end

      versions.sort_by(&.generation)
    end

    # Check if an object with the given ID exists
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

    # Sepia objects know how to save themselves
    def save(path : String? = nil)
      Sepia::Storage::INSTANCE.save(self, path)
    end

    # Sepia objects can load themselves from storage
    def self.load(id : String, path : String? = nil) : self
      Sepia::Storage::INSTANCE.load(self, id, path)
    end

    # Sepia objects can delete themselves from storage
    def delete
      Sepia::Storage::INSTANCE.delete(self)
    end

    # Returns the canonical path for the object in storage.
    def canonical_path : String
      File.join(Sepia::Storage::INSTANCE.path, self.class.name, sepia_id)
    end
  end
end

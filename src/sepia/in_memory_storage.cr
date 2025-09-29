require "./storage_backend"

module Sepia
  # In-memory storage backend for Sepia objects.
  #
  # This backend stores all data in memory hashes without any filesystem
  # operations. It's primarily useful for:
  #
  # - Testing: Fast operations without disk I/O
  # - Demos: Self-contained examples that don't persist data
  # - Temporary data: Caching or session storage
  #
  # ### Data Structure
  #
  # The storage uses three main hashes:
  # - `@serializable_storage`: Maps class_name/id to serialized content
  # - `@container_storage`: Maps class_name/id to property data and references
  # - `@container_references`: Maps container paths to reference mappings
  #
  # ### Example
  #
  # ```
  # # Configure Sepia to use in-memory storage
  # Sepia::Storage.configure(:memory)
  #
  # # Objects will be stored in memory only
  # doc = MyDocument.new("Hello")
  # doc.save # Stored in @serializable_storage
  # ```
  class InMemoryStorage < StorageBackend
    # Storage for Serializable objects.
    #
    # Maps full path strings to serialized content.
    # Format: `{ "path/to/ClassName/id" => "serialized_content" }`
    @serializable_storage = {} of String => String

    # Storage for Container objects.
    #
    # Maps class_name/id to container data including primitive properties.
    # Format: `{ "ClassName/id" => { "_type" => "container", "_data" => "json" } }`
    @container_storage = {} of String => Hash(String, String)

    # Storage for container object references.
    #
    # Maps container paths to their contained object references.
    # Format: `{ "container_path" => { "ref_name" => "target_class/target_id" } }`
    @container_references = {} of String => Hash(String, String)

    # Base path for compatibility with FileStorage.
    #
    # Not actually used for storage, but provides path compatibility
    # when working with objects that expect filesystem-style paths.
    @path = "/tmp"

    # Saves a Serializable object to memory storage.
    #
    # Stores the object's serialized content in the `@serializable_storage` hash.
    # The key is the full path (including the base path) to maintain
    # compatibility with FileStorage.
    #
    # ```
    # doc = MyDocument.new("Hello")
    # storage = InMemoryStorage.new
    # storage.save(doc) # Stored in @serializable_storage
    # ```
    def save(object : Serializable, path : String? = nil)
      object_path = path || File.join(@path, object.class.name, object.sepia_id)
      content = object.to_sepia

      # Save to the specified path only (matching filesystem behavior)
      @serializable_storage[object_path] = content
    end

    # Saves a Container object to memory storage.
    #
    # Stores the container's metadata and primitive properties in the
    # `@container_storage` hash. Primitive properties are serialized to JSON
    # and stored under the "_data" key.
    #
    # ```
    # board = Board.new("My Board")
    # storage = InMemoryStorage.new
    # storage.save(board) # Stored in @container_storage
    # ```
    def save(object : Container, path : String? = nil)
      object_key = "#{object.class.name}/#{object.sepia_id}"
      @container_storage[object_key] = {} of String => String

      # Store container metadata
      @container_storage[object_key]["_type"] = "container"

      # Store primitive properties from JSON serialization
      @container_storage[object_key]["_data"] = object.to_filtered_json

      # Store references
      if path
        object.save_references(path)
      end
    end

    # Loads an object from memory storage.
    #
    # Retrieves and deserializes an object of the specified class.
    # For Serializable objects, uses the class's `from_sepia` method.
    # For Container objects, restores primitive properties from JSON and
    # loads references if a path is provided.
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
      case
      when object_class.responds_to?(:from_sepia)
        # It's a Serializable
        object_path = path || File.join(@path, object_class.to_s, id)

        unless @serializable_storage.has_key?(object_path)
          raise "Object with ID #{id} not found in storage for type #{object_class}"
        end

        obj = object_class.from_sepia(@serializable_storage[object_path])
        obj.sepia_id = id
        obj
      when object_class < Container
        # It's a Container
        object_key = "#{object_class}/#{id}"

        unless @container_storage.has_key?(object_key)
          raise "Object with ID #{id} not found in storage for type #{object_class}"
        end

        obj = object_class.new
        obj.sepia_id = id

        # Load primitive properties from stored JSON
        if data = @container_storage[object_key]["_data"]?
          unless data.empty?
            obj.as(Container).restore_properties_from_json(data)
          end
        end

        # Load references if path is provided
        if path
          obj.as(Container).load_references(path)
        end

        obj
      else
        raise "Unsupported class for Sepia storage: #{object_class.name}"
      end
    end

    def delete(object : Serializable | Container)
      object_key = "#{object.class.name}/#{object.sepia_id}"

      if object.is_a?(Serializable)
        @serializable_storage.delete(object_key)
      elsif object.is_a?(Container)
        @container_storage.delete(object_key)
        # Also clean up any references
        @container_references.each do |_path, refs|
          refs.reject! { |_, target| target.starts_with?(object_key) }
        end
      end
    end

    def delete(class_name : String, id : String)
      if Sepia.container?(class_name)
        object_key = "#{class_name}/#{id}"
        @container_storage.delete(object_key)
      else
        object_path = File.join(@path, class_name, id)
        @serializable_storage.delete(object_path)
      end
    end

    def list_all(object_class : Class) : Array(String)
      class_name = object_class.to_s
      ids = [] of String

      if object_class < Serializable
        @serializable_storage.each_key do |key|
          # Only include objects in canonical location
          canonical_path = File.join(@path, class_name)
          if key.starts_with?("#{canonical_path}/")
            id = File.basename(key)
            ids << id
          end
        end
      elsif object_class < Container
        @container_storage.each_key do |key|
          if key.starts_with?("#{class_name}/")
            ids << key.split('/', 2)[1]
          end
        end
      end

      ids.sort
    end

    def exists?(object_class : Class, id : String) : Bool
      if object_class < Serializable
        canonical_path = File.join(@path, object_class.to_s, id)
        @serializable_storage.has_key?(canonical_path)
      elsif object_class < Container
        object_key = "#{object_class}/#{id}"
        @container_storage.has_key?(object_key)
      else
        false
      end
    end

    def count(object_class : Class) : Int32
      list_all(object_class).size
    end

    # Clears all data from memory storage.
    #
    # Empties all internal hashes, effectively resetting the storage
    # to its initial empty state.
    #
    # ```
    # storage.clear # All data is now gone
    # ```
    def clear
      @serializable_storage.clear
      @container_storage.clear
      @container_references.clear
    end

    def export_data : Hash(String, Array(Hash(String, String)))
      data = {} of String => Array(Hash(String, String))

      # Export serializable objects (only canonical locations)
      @serializable_storage.each do |key, content|
        # Check if this is a canonical path
        if key.starts_with?(@path)
          relative_path = key[@path.size + 1..-1]
          parts = relative_path.split('/')
          if parts.size == 2 # class_name/id
            class_name, id = parts
            data[class_name] ||= [] of Hash(String, String)
            data[class_name] << {"id" => id, "content" => content}
          end
        end
      end

      # Export container objects
      @container_storage.each do |key, _|
        class_name, id = key.split('/', 2)
        data[class_name] ||= [] of Hash(String, String)
        data[class_name] << {"id" => id, "type" => "container"}
      end

      data
    end

    def import_data(data : Hash(String, Array(Hash(String, String))))
      clear

      data.each do |class_name, objects|
        objects.each do |obj_data|
          if obj_data.has_key?("content")
            # It's a serializable object
            id = obj_data["id"]
            # Use full path format to match what save creates
            key = File.join(@path, class_name, id)
            @serializable_storage[key] = obj_data["content"]
          elsif obj_data["type"]? == "container"
            # It's a container object
            id = obj_data["id"]
            key = "#{class_name}/#{id}"
            @container_storage[key] = {"_type" => "container"}
          end
        end
      end
    end

    # Methods to support container references (for internal use by Container module)
    def store_reference(container_path : String, ref_name : String, target_class : String, target_id : String)
      @container_references[container_path] ||= {} of String => String
      @container_references[container_path][ref_name] = "#{target_class}/#{target_id}"
    end

    def get_reference(container_path : String, ref_name : String) : String?
      if refs = @container_references[container_path]?
        refs[ref_name]?
      end
    end

    def store_container_reference(container_path : String, ref_name : String, target_container : Container)
      @container_references[container_path] ||= {} of String => String
      @container_references[container_path][ref_name] = "#{target_container.class.name}/#{target_container.sepia_id}"
    end

    def get_container_references(container_path : String) : Hash(String, String)
      @container_references[container_path] || {} of String => String
    end

    def list_all_objects : Hash(String, Array(String))
      objects = Hash(String, Array(String)).new { |hash, key| hash[key] = [] of String }
      prefix = @path + "/"

      @serializable_storage.each_key do |key|
        if key.starts_with?(prefix)
          # key is like "/tmp/ClassName/id"
          # remove prefix -> "ClassName/id"
          class_and_id = key[prefix.size..-1]
          parts = class_and_id.split('/')
          if parts.size == 2 # Should be just [class, id]
            class_name, id = parts
            objects[class_name] << id
          end
        end
      end

      @container_storage.each_key do |key|
        # key is "ClassName/id"
        class_name, id = key.split('/', 2)
        objects[class_name] << id
      end

      objects
    end
  end
end

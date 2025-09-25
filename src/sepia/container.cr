module Sepia
  # Sepia::Container tagged objects can contain Sepia::Serializable objects or
  # other Sepia::Container objects.
  #
  # Containers serialize as directories with references (links) to other containers
  # or to Sepia::Serializable objects.
  module Container
    macro included
      Sepia.register_class_type({{@type.name.stringify}}, true)
    end

    # Returns a list of all Sepia objects referenced by this object.
    def sepia_references : Enumerable(Sepia::Object)
      refs = [] of Sepia::Object
      {% for ivar in @type.instance_vars %}
        value = @{{ivar.name}}
        if value.is_a?(Sepia::Object)
          refs << value
        elsif value.is_a?(Enumerable)
          value.each do |item|
            add_sepia_object_to_refs(item, refs)
          end
        elsif value.is_a?(Hash)
          value.each_value do |item|
            add_sepia_object_to_refs(item, refs)
          end
        end
      {% end %}
      refs
    end

    private def add_sepia_object_to_refs(item, refs : Array(Sepia::Object))
      if item.is_a?(Sepia::Object)
        refs << item
      end
    end

    # Saves all references (Serializable, Container, Enumerable of either)
    # to the container's path.
    def save_references(path : String)
      {% for ivar in @type.instance_vars %}
        save_value(path, @{{ivar.name}}, {{ivar.name.stringify}})
      {% end %}
    end

    private def save_value(path, value : Serializable?, name)
      # Saves a Serializable object by saving it and then creating a symlink
      # to its canonical location within the container's directory.
      if obj = value
        obj.save

        # Check if we're using InMemoryStorage
        if Sepia::Storage.backend.is_a?(InMemoryStorage)
          # Use in-memory reference storage
          Sepia::Storage.backend.as(InMemoryStorage).store_reference(path, name, obj.class.name, obj.sepia_id)
        else
          # Use filesystem symlinks
          symlink_path = File.join(path, name)
          obj_path = File.join(Sepia::Storage::INSTANCE.path, obj.class.name, obj.sepia_id)
          FileUtils.ln_s(Path[obj_path].relative_to(Path[symlink_path].parent), symlink_path)
        end
      end
    end

    private def save_value(path, value : Container?, name)
      # Saves a nested Container object by creating a subdirectory for it
      # and recursively calling `save_references` on it.
      if container = value
        container.save # <-- THE FIX
        container_path = File.join(path, name)
        FileUtils.mkdir_p(container_path)
        container.save_references(container_path)
      end
    end

    private def save_value(path, value : Enumerable(Sepia::Object)?, name)
      # Saves an Enumerable (e.g., Array, Set) of Serializable or Container objects.
      if array = value
        return if array.empty?
        array_dir = File.join(path, name)
        FileUtils.rm_rf(array_dir)
        FileUtils.mkdir_p(array_dir)

        array.each_with_index do |obj, index|
          save_value(array_dir, obj, "#{index.to_s.rjust(4, '0')}_#{obj.sepia_id}")
        end
      end
    end

    private def save_value(path, value : Hash(String, Sepia::Object)?, name)
      # Saves a Hash with String keys and Serializable or Container values.
      if hash = value
        return if hash.empty?
        hash_dir = File.join(path, name)
        FileUtils.rm_rf(hash_dir)
        FileUtils.mkdir_p(hash_dir)

        hash.each do |key, obj|
          save_value(hash_dir, obj, key)
        end
      end
    end

    private def save_value(path, value, name)
      # This is a catch-all for types that are not Serializable, Container,
      # or collections of them. These types are not persisted by Sepia.
      # Do nothing for other types
    end

    # Loads all references (Serializable, Container, Enumerable of either)
    # from the container's path.
    def load_references(path : String)
      {% for ivar in @type.instance_vars %}
        # For each instance variable, check if it's a Serializable or a Container.
        # Handle both direct Serializable types and nilable Serializables (unions)
        {% if ivar.type < Sepia::Serializable || (ivar.type.union? && ivar.type.union_types.any? { |type| type < Sepia::Serializable }) %}
          # Determine the actual Serializable type (for union types, find the non-nil type)
          {% if ivar.type < Sepia::Serializable %}
            {% serializable_type = ivar.type %}
          {% else %}
            {% serializable_type = nil %}
            {% for type in ivar.type.union_types %}
              {% if type < Sepia::Serializable %}
                {% serializable_type = type %}
              {% end %}
            {% end %}
          {% end %}
          # Check if we're using InMemoryStorage
          if Sepia::Storage.backend.is_a?(InMemoryStorage)
            # Load from in-memory reference storage
            ref_key = Sepia::Storage.backend.as(InMemoryStorage).get_reference(path, {{ivar.name.stringify}})
            if ref_key
              obj_class_name, obj_id = ref_key.split('/', 2)
              @{{ ivar.name }} = Sepia::Storage::INSTANCE.load({{serializable_type}}, obj_id).as({{ ivar.type }})
            else
              {% if ivar.type.nilable? %}
                @{{ ivar.name }} = nil
              {% else %}
                raise "Missing required reference for '" + {{ivar.name.stringify}} + "' in container at " + path
              {% end %}
            end
          else
            # Load from filesystem symlinks
            symlink_path = File.join(path, {{ivar.name.stringify}})
            if File.symlink?(symlink_path)
              # See where the symlink points to and get the object ID
              obj_path = File.readlink(symlink_path)
              obj_id = File.basename(obj_path)
              @{{ ivar.name }} = Sepia::Storage::INSTANCE.load({{serializable_type}}, obj_id).as({{ ivar.type }})
            else
              {% if ivar.type.nilable? %}
                @{{ ivar.name }} = nil
              {% else %}
                raise "Missing required reference for '#{symlink_path}' for non-nilable property '{{ivar.name}}'"
              {% end %}
            end
          end
        {% elsif ivar.type < Sepia::Container %}
          container_path = File.join(path, {{ivar.name.stringify}})
          if Dir.exists?(container_path)
            @{{ivar.name}} = {{ivar.type}}.new
            @{{ivar.name}}.as({{ivar.type}}).sepia_id = {{ivar.name.stringify}}
            @{{ivar.name}}.as(Container).load_references(container_path)
          else
            {% if ivar.type.nilable? %}
              @{{ivar.name}} = nil
            {% end %}
          end
        {% elsif ivar.type < Enumerable && ivar.type.type_vars.first < Sepia::Serializable %}
          array_dir = File.join(path, {{ivar.name.stringify}})
          if Dir.exists?(array_dir)
            @{{ivar.name}} = load_enumerable_of_references(path, {{ivar.name.stringify}}, {{ivar.type}}, {{ivar.type.type_vars.first}})
          else
            {% if ivar.type.union? %} # It's nilable
              @{{ivar.name}} = nil
            {% else %} # It's not nilable, so create empty array
              @{{ivar.name}} = {{ivar.type}}.new
            {% end %}
          end
        {% elsif ivar.type < Enumerable && ivar.type.type_vars.first < Sepia::Container %}
          array_dir = File.join(path, {{ivar.name.stringify}})
          if Dir.exists?(array_dir)
            @{{ivar.name}} = load_enumerable_of_containers(path, {{ivar.name.stringify}}, {{ivar.type}}, {{ivar.type.type_vars.first}})
          else
            {% if ivar.type.union? %} # It's nilable
              @{{ivar.name}} = nil
            {% else %} # It's not nilable, so create empty array
              @{{ivar.name}} = {{ivar.type}}.new
            {% end %}
          end
        {% elsif ivar.type < Hash && ivar.type.type_vars.first == String && ivar.type.type_vars.last < Sepia::Serializable %}
          hash_dir = File.join(path, {{ivar.name.stringify}})
          if Dir.exists?(hash_dir)
            @{{ivar.name}} = load_hash_of_references(path, {{ivar.name.stringify}}, {{ivar.type}}, {{ivar.type.type_vars.last}})
          else
            {% if ivar.type.union? %} # It's nilable
              @{{ivar.name}} = nil
            {% else %} # It's not nilable, so create empty hash
              @{{ivar.name}} = {{ivar.type}}.new
            {% end %}
          end
        {% elsif ivar.type < Hash && ivar.type.type_vars.first == String && ivar.type.type_vars.last < Sepia::Container %}
          hash_dir = File.join(path, {{ivar.name.stringify}})
          if Dir.exists?(hash_dir)
            @{{ivar.name}} = load_hash_of_containers(path, {{ivar.name.stringify}}, {{ivar.type}}, {{ivar.type.type_vars.last}})
          else
            {% if ivar.type.union? %} # It's nilable
              @{{ivar.name}} = nil
            {% else %} # It's not nilable, so create empty hash
              @{{ivar.name}} = {{ivar.type}}.new
            {% end %}
          end
        {% end %}
      {% end %}
    end

    # Loads an enumerable of serializable objects from a directory of symlinks.
    def load_enumerable_of_references(path : String, name : String, collection_type : T.class, item_type : U.class) forall T, U
      array_dir = File.join(path, name)
      loaded_collection = T.new
      if Dir.exists?(array_dir)
        symlinks = Dir.entries(array_dir).reject { |e| e == "." || e == ".." }.sort!
        symlinks.each do |entry|
          symlink_path = File.join(array_dir, entry)
          if File.symlink?(symlink_path)
            obj_path = File.readlink(symlink_path)
            obj_id = File.basename(obj_path)
            loaded_obj = Sepia::Storage::INSTANCE.load(item_type, obj_id)
            if loaded_obj.is_a?(Container)
              loaded_obj.load_references(obj_path)
            end
            loaded_collection << loaded_obj.as(U)
          end
        end
      end
      loaded_collection
    end

    # Loads an enumerable of containers from a directory of subdirectories.
    def load_enumerable_of_containers(path : String, name : String, collection_type : T.class, item_type : U.class) forall T, U
      array_dir = File.join(path, name)
      loaded_collection = T.new
      if Dir.exists?(array_dir)
        dirs = Dir.entries(array_dir).reject { |e| e == "." || e == ".." }.sort!
        dirs.each do |entry|
          container_path = File.join(array_dir, entry)
          if Dir.exists?(container_path)
            container = U.new
            # Extract the sepia_id from the filename (e.g., "00000_some_id" -> "some_id")
            container.sepia_id = entry.split("_", 2)[1]
            container.load_references(container_path)
            loaded_collection << container
          end
        end
      end
      loaded_collection
    end

    # Loads a hash of serializable objects from a directory of symlinks.
    def load_hash_of_references(path : String, name : String, collection_type : T.class, item_type : U.class) forall T, U
      hash_dir = File.join(path, name)
      loaded_hash = T.new
      if Dir.exists?(hash_dir)
        symlinks = Dir.entries(hash_dir).reject { |e| e == "." || e == ".." }
        symlinks.each do |entry|
          symlink_path = File.join(hash_dir, entry)
          if File.symlink?(symlink_path)
            obj_path = File.readlink(symlink_path)
            obj_id = File.basename(obj_path)
            loaded_obj = Sepia::Storage::INSTANCE.load(item_type, obj_id)
            loaded_hash[entry] = loaded_obj.as(U)
          end
        end
      end
      loaded_hash
    end

    # Loads a hash of containers from a directory of subdirectories.
    def load_hash_of_containers(path : String, name : String, collection_type : T.class, item_type : U.class) forall T, U
      hash_dir = File.join(path, name)
      loaded_hash = T.new
      if Dir.exists?(hash_dir)
        dirs = Dir.entries(hash_dir).reject { |e| e == "." || e == ".." }
        dirs.each do |entry|
          container_path = File.join(hash_dir, entry)
          if Dir.exists?(container_path)
            container = U.new
            container.sepia_id = entry
            container.load_references(container_path)
            loaded_hash[entry] = container
          end
        end
      end
      loaded_hash
    end
  end
end

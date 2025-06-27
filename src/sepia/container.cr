module Sepia
  # Sepia::Container tagged objects can contain Sepia::Serializable objects or
  # other Sepia::Container objects.
  #
  # Containers serialize as directories with references (links) to other containers
  # or to Sepia::Serializable objects.
  module Container
    macro included
      # Container classes MUST have a sepia_id property which defaults to a lazy UUID
      getter sepia_id : String = UUID.random.to_s

      def sepia_id=(id : String)
        @sepia_id = id
      end

      # Container classes know how to save themselves
      def save(path : String? = nil)
        Sepia::Storage::INSTANCE.save(self, path)
      end

      # Container classes know how to load themselves
      def self.load(id : String)
        Sepia::Storage::INSTANCE.load(self, id)
      end

      # Sepia-serializable containers can delete themselves from storage
      def delete
        Sepia::Storage::INSTANCE.delete(self)
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
        symlink_path = File.join(path, name)
        obj_path = File.join(Sepia::Storage::INSTANCE.path, obj.class.name, obj.sepia_id)
        FileUtils.ln_s(obj_path, symlink_path)
      end
    end

    private def save_value(path, value : Container?, name)
      # Saves a nested Container object by creating a subdirectory for it
      # and recursively calling `save_references` on it.
      if container = value
        container_path = File.join(path, name)
        FileUtils.mkdir_p(container_path)
        container.save_references(container_path)
      end
    end

    private def save_value(path, value : Enumerable(Serializable)?, name)
      # Saves an Enumerable (e.g., Array, Set) of Serializable objects.
      # Each serializable object is saved and then symlinked into a subdirectory
      # named after the enumerable, using its index as the symlink name.
      if array = value
        return if array.empty?
        array_dir = File.join(path, name)
        FileUtils.rm_rf(array_dir) if File.exists?(array_dir)
        FileUtils.mkdir_p(array_dir)

        array.each_with_index do |obj, index|
          save_value(array_dir, obj, index.to_s)
        end
      end
    end

    private def save_value(path, value : Enumerable(Container)?, name)
      # Saves an Enumerable (e.g., Array, Set) of Container objects.
      # Each container object is saved as a subdirectory within a subdirectory
      # named after the enumerable, using its index as the subdirectory name.
      if array = value
        return if array.empty?
        array_dir = File.join(path, name)
        FileUtils.rm_rf(array_dir) if File.exists?(array_dir)
        FileUtils.mkdir_p(array_dir)

        array.each_with_index do |container, index|
          save_value(array_dir, container, index.to_s)
        end
      end
    end

    private def save_value(path, value : Hash(String, Serializable)?, name)
      # Saves a Hash with String keys and Serializable values.
      # Each serializable object is saved and then symlinked into a subdirectory
      # named after the hash, using its key as the symlink name.
      if hash = value
        return if hash.empty?
        hash_dir = File.join(path, name)
        FileUtils.rm_rf(hash_dir) if File.exists?(hash_dir)
        FileUtils.mkdir_p(hash_dir)

        hash.each do |key, obj|
          save_value(hash_dir, obj, key)
        end
      end
    end

    private def save_value(path, value : Hash(String, Container)?, name)
      # Saves a Hash with String keys and Container values.
      # Each container object is saved as a subdirectory within a subdirectory
      # named after the hash, using its key as the subdirectory name.
      if hash = value
        return if hash.empty?
        hash_dir = File.join(path, name)
        FileUtils.rm_rf(hash_dir) if File.exists?(hash_dir)
        FileUtils.mkdir_p(hash_dir)

        hash.each do |key, container|
          save_value(hash_dir, container, key)
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
        {% if ivar.type < Sepia::Serializable %}
          symlink_path = File.join(path, {{ivar.name.stringify}})
          if File.symlink?(symlink_path)
            # See where the symlink points to and get the object ID
            obj_path = File.readlink(symlink_path)
            obj_id = File.basename(obj_path)
            @{{ ivar.name }} = Sepia::Storage::INSTANCE.load({{ivar.type}}, obj_id).as({{ ivar.type }})
          else
            {% if ivar.type.nilable? %}
              @{{ ivar.name }} = nil
            {% else %}
              raise "Missing required reference for '#{symlink_path}' for non-nilable property '{{ivar.name}}'"
            {% end %}
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
        symlinks = Dir.entries(array_dir).reject { |e| e == "." || e == ".." }.sort_by(&.to_i)
        symlinks.each do |entry|
          symlink_path = File.join(array_dir, entry)
          if File.symlink?(symlink_path)
            obj_path = File.readlink(symlink_path)
            obj_id = File.basename(obj_path)
            loaded_obj = Sepia::Storage::INSTANCE.load(item_type, obj_id)
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
        dirs = Dir.entries(array_dir).reject { |e| e == "." || e == ".." }.sort_by(&.to_i)
        dirs.each do |entry|
          container_path = File.join(array_dir, entry)
          if Dir.exists?(container_path)
            container = U.new
            container.sepia_id = entry
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

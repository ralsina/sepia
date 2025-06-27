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
      def save
        Sepia::Storage::INSTANCE.save(self)
      end

      # Container classes know how to load themselves
      def self.load(id : String)
        Sepia::Storage::INSTANCE.load(self, id)
      end
    end

    def save_references(path : String)
      {% for ivar in @type.instance_vars %}
        # For each instance variable, check if it's a Serializable or a Container.
        # We need to ensure the object is not nil before attempting to save it.
        {% if ivar.type < Sepia::Serializable %}
          obj = {{ ivar.name }}
          # Only save if the object is not nil (for nilable properties)
          if obj
            # Save the referenced object (which could be Serializable or Container)
            obj.save
            # Create a symlink to the saved object
            symlink_path = File.join(path, {{ivar.name.stringify}})
            obj_path = File.join(Sepia::Storage::INSTANCE.path, obj.class.name, obj.sepia_id)
            FileUtils.ln_s(obj_path, symlink_path)
          end
        {% elsif ivar.type < Sepia::Container %}
          if container = @{{ivar.name}}
            container_path = File.join(path, {{ivar.name.stringify}})
            FileUtils.mkdir_p(container_path)
            container.save_references(container_path)
          end
        {% elsif ivar.type < Enumerable && ivar.type.type_vars.first < Sepia::Serializable %}
          if array = @{{ivar.name}}
            save_array_of_references(path, array, {{ivar.name.stringify}})
          end
        {% elsif ivar.type < Enumerable && ivar.type.type_vars.first < Sepia::Container %}
          if array = @{{ivar.name}}
            save_array_of_references(path, array, {{ivar.name.stringify}})
          end
        {% else %}
            # If it's not a Serializable or Container, we don't need to do anything.
        {% end %}
      {% end %}
    end

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
              # If the symlink doesn't exist and the ivar is nilable, set to nil.
              @{{ ivar.name }} = nil
            {% else %}
              # If the symlink doesn't exist and the ivar is NOT nilable, it's an error.
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
        {% end %}
      {% end %}
    end

    # Saves a collection of Serializable objects as a directory of references.
    #
    # It creates a subdirectory named `name` inside the container's `path`.
    # For each object in the `array`, it saves the object and then creates a
    # symlink inside the subdirectory, pointing to the saved object's canonical location.
    def save_array_of_references(path : String, array : Enumerable(Serializable|Container), name : String)
      return if array.empty?
      array_dir = File.join(path, name)
      FileUtils.rm_rf(array_dir) if File.exists?(array_dir)
      FileUtils.mkdir_p(array_dir)

      array.each_with_index do |obj, index|
        # Save the object to its canonical location
        obj.save

        # Create a symlink inside the container's array-property directory
        FileUtils.ln_s(File.join(Sepia::Storage::INSTANCE.path, obj.class.name, obj.sepia_id), File.join(array_dir, index.to_s))
      end
    end

    def save_array_of_references(path : String, array : Enumerable(Container), name : String)
      return if array.empty?
      array_dir = File.join(path, name)
      FileUtils.rm_rf(array_dir) if File.exists?(array_dir)
      FileUtils.mkdir_p(array_dir)

      array.each_with_index do |container, index|
        container_path = File.join(array_dir, index.to_s)
        FileUtils.mkdir_p(container_path)
        container.save_references(container_path)
      end
    end

    # Loads a collection of Serializable objects from a directory of references.
    def load_enumerable_of_references(path : String, name : String, collection_type : T.class, item_type : U.class) forall T, U
      array_dir = File.join(path, name)
      loaded_collection = T.new

      if Dir.exists?(array_dir)
        # Read all symlinks, filter out '.' and '..', sort them numerically to preserve order
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

    def load_enumerable_of_containers(path : String, name : String, collection_type : T.class, item_type : U.class) forall T, U
      array_dir = File.join(path, name)
      loaded_collection = T.new

      if Dir.exists?(array_dir)
        # Read all directories, filter out '.' and '..'
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
  end
end
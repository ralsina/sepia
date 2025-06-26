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
        {% if ivar.type < Sepia::Serializable || ivar.type < Sepia::Container %}
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
        {% end %}
      {% end %}
    end

    def load_references(path : String)
      {% for ivar in @type.instance_vars %}
        # For each instance variable, check if it's a Serializable or a Container.
        {% if ivar.type < Sepia::Serializable || ivar.type < Sepia::Container %}
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
        {% end %}
      {% end %}
    end
  end
end

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
        # For each instance variable, check if it's a Serializable or a Container
        if {{ ivar.name }}.is_a? Sepia::Serializable
          obj = {{ ivar.name }}.as(Sepia::Serializable)
          # Save the serializable object
          obj.save
          # Create a symlink to the saved object
          symlink_path = File.join(path, {{ivar.name.stringify}})
          obj_path = File.join(Sepia::Storage::INSTANCE.path, typeof({{ ivar.name }}).to_s, obj.sepia_id)
          FileUtils.ln_s(obj_path, symlink_path)
        end
      {% end %}
    end
  end
end

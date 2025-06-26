require "uuid"

module Sepia
  # Sepia serializable objects decide their own serialization .
  # This is intentional.
  module Serializable
    # When Sepia::Serializable is included, define the `to_sepia`
    # and `self.from_sepia` methods for the class.
    macro included
      def to_sepia() : String
        {% begin %}
        raise "to_sepia must be implemented by the class including Sepia::Serializable"
        {% end %}
      end

      def self.from_sepia(sepia_string : String)
        {% begin %}
        raise "self.from_sepia must be implemented by the class including Sepia::Serializable"
        {% end %}
      end

      # Sepia-serializable classes MUST have a sepia_id property which defaults to a lazy UUID
      getter sepia_id : String = UUID.random.to_s
      def sepia_id=(id : String)
        @sepia_id = id
      end

      # Sepia-serializable classes know how to save themselves
      def save
        Sepia::Storage::INSTANCE.save(self)
      end

      # Sepia-serializable classes can load themselves from storage
      def self.load(id : String)
        Sepia::Storage::INSTANCE.load(self, id)
      end
    end
  end
end

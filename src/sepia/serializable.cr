require "uuid"

module Sepia
  # The `Serializable` module provides a contract for objects that can be
  # serialized to a single file. Classes including this module must implement
  # `to_sepia` to define the file content and `self.from_sepia` to deserialize.
  module Serializable
    # When Sepia::Serializable is included, define the `to_sepia`
    # and `self.from_sepia` methods for the class.
    macro included
      # Defines how the object's content is serialized into a String.
      # Classes including `Sepia::Serializable` must implement this method.
      def to_sepia : String
        raise "to_sepia must be implemented by the class including Sepia::Serializable"
      end

      # Defines how the object is deserialized from a String.
      # Classes including `Sepia::Serializable` must implement this class method.
      def self.from_sepia(sepia_string : String)
        raise "self.from_sepia must be implemented by the class including Sepia::Serializable"
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

      # Sepia-serializable classes can delete themselves from storage
      def delete
        Sepia::Storage::INSTANCE.delete(self)
      end
    end
  end
end

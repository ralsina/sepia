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
    end

    # Returns a list of all Sepia objects referenced by this object.
    # By default, a Serializable object references nothing.
    def sepia_references : Enumerable(Sepia::Object)
      [] of Sepia::Object
    end
  end
end

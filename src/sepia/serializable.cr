module Sepia
  # Module for objects that serialize to a single file.
  #
  # The `Serializable` module provides a contract for objects that can be
  # serialized to and deserialized from a single string representation.
  #
  # ⚠️ **WARNING**: The Serializable API and on-disk format are subject to change.
  # Data migrations will be required when upgrading Sepia versions.
  # Classes including this module must implement two methods:
  #
  # - `to_sepia : String` - Serializes the object to a string
  # - `self.from_sepia(sepia_string : String)` - Creates an object from a string
  #
  # ## File Storage
  #
  # Serializable objects are stored as individual files in the filesystem.
  # The file contains the exact string returned by `to_sepia`.
  #
  # ### Example
  #
  # ```
  # class SimpleNote < Sepia::Object
  #   include Sepia::Serializable
  #
  #   property text : String
  #
  #   def initialize(@text = "")
  #   end
  #
  #   # Serialize to a simple string
  #   def to_sepia : String
  #     @text
  #   end
  #
  #   # Deserialize from a string
  #   def self.from_sepia(sepia_string : String) : self
  #     new(sepia_string)
  #   end
  # end
  #
  # note = SimpleNote.new("Hello, World!")
  # note.save # Creates a file containing "Hello, World!"
  #
  # loaded = SimpleNote.load(note.sepia_id)
  # loaded.text # => "Hello, World!"
  # ```
  #
  # ### JSON Serialization
  #
  # For more complex objects, you can serialize to JSON:
  #
  # ```
  # class User < Sepia::Object
  #   include Sepia::Serializable
  #
  #   property name : String
  #   property email : String
  #
  #   def initialize(@name = "", @email = "")
  #   end
  #
  #   def to_sepia : String
  #     {name: @name, email: @email}.to_json
  #   end
  #
  #   def self.from_sepia(json : String) : self
  #     data = JSON.parse(json)
  #     new(data["name"].as_s, data["email"].as_s)
  #   end
  # end
  # ```
  module Serializable
    # When included, defines the required serialization methods.
    #
    # This macro injects abstract methods that must be implemented
    # by the including class. The methods raise helpful error messages
    # if not implemented.
    macro included
      # Serializes the object to a string.
      #
      # This method must be implemented by classes including `Serializable`.
      # It should return a string representation of the object that can
      # be used to reconstruct it later.
      #
      # ### Returns
      #
      # A string containing the serialized form of the object.
      #
      # ### Example
      #
      # ```
      # def to_sepia : String
      #   # For simple objects: return a simple string
      #   @content
      #
      #   # For complex objects: return JSON
      #   {title: @title, content: @content}.to_json
      # end
      # ```
      def to_sepia : String
        raise "to_sepia must be implemented by the class including Sepia::Serializable"
      end

      # Deserializes an object from a string.
      #
      # This class method must be implemented by classes including `Serializable`.
      # It should parse the string and return a new instance of the class.
      #
      # ### Parameters
      #
      # - *sepia_string* : The string representation of the object
      #
      # ### Returns
      #
      # A new instance of the class reconstructed from the string.
      #
      # ### Example
      #
      # ```
      # def self.from_sepia(sepia_string : String) : self
      #   # For simple objects
      #   new(sepia_string)
      #
      #   # For JSON objects
      #   data = JSON.parse(sepia_string)
      #   new(data["title"].as_s, data["content"].as_s)
      # end
      # ```
      def self.from_sepia(sepia_string : String)
        raise "self.from_sepia must be implemented by the class including Sepia::Serializable"
      end
    end

    # Returns all Sepia objects referenced by this object.
    #
    # This method is used by the garbage collector to track object
    # relationships. By default, Serializable objects don't reference
    # other Sepia objects.
    #
    # Override this method if your Serializable contains references
    # to other Sepia objects that should be tracked.
    #
    # ### Returns
    #
    # An Enumerable of Sepia::Object instances referenced by this object.
    #
    # ### Example
    #
    # ```
    # class Document < Sepia::Object
    #   include Sepia::Serializable
    #
    #   property author : User
    #
    #   def sepia_references : Enumerable(Sepia::Object)
    #     [@author] if @author
    #   end
    # end
    # ```
    def sepia_references : Enumerable(Sepia::Object)
      [] of Sepia::Object
    end
  end
end

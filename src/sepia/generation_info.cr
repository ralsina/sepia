module Sepia
  # Module that adds generation tracking information to JSON serialization.
  #
  # Include this module in your Serializable classes to automatically
  # include generation metadata (`_generation` and `_base_id`) in the
  # serialized JSON output. This is useful for:
  #
  # - Auditing: Track which version of an object was exported
  # - Migration: Identify objects that need version updates
  # - Debugging: See generation information in serialized data
  #
  # ### Example
  #
  # ```
  # class VersionedDocument < Sepia::Object
  #   include Sepia::Serializable
  #   include Sepia::GenerationInfo
  #
  #   property content : String
  #
  #   def initialize(@content = "")
  #   end
  #
  #   def to_sepia : String
  #     {content: @content}.to_json
  #   end
  #
  #   def self.from_sepia(json : String) : self
  #     data = JSON.parse(json)
  #     new(data["content"].as_s)
  #   end
  # end
  #
  # doc = VersionedDocument.new("Hello")
  # doc.sepia_id = "doc-123.2"
  # json = doc.to_sepia
  # # json includes: {"content":"Hello","_generation":2,"_base_id":"doc-123"}
  # ```
  module GenerationInfo
    # Enhanced serialization method that includes generation metadata.
    #
    # Parses the original JSON from the class's `to_sepia` method,
    # adds `_generation` and `_base_id` fields, and returns the
    # augmented JSON string.
    #
    # The generation metadata helps track:
    # - `_generation`: The version number of this object
    # - `_base_id`: The base identifier without generation suffix
    #
    # ```
    # # When called on an object with ID "note-123.2"
    # obj.to_sepia # Returns JSON with _generation: 2, _base_id: "note-123"
    # ```
    def to_sepia : String
      data = JSON.parse(super)
      data["_generation"] = generation
      data["_base_id"] = base_id
      data.to_json
    end

    # Helper method for deserializing objects with generation metadata.
    #
    # This method processes JSON that may contain generation information
    # from previous serialization. It removes the generation metadata
    # before passing the cleaned JSON to the original `from_sepia` method.
    #
    # ### Parameters
    #
    # - *sepia_string* : The JSON string potentially containing generation metadata
    # - *&block* : A block that calls the original `from_sepia` method
    #
    # ### Example Usage
    #
    # ```
    # def self.from_sepia(json : String) : self
    #   GenerationInfo.from_sepia_with_generation(json) do |clean_json|
    #     # clean_json has _generation and _base_id removed
    #     # Parse and create object normally
    #     data = JSON.parse(clean_json)
    #     new(data["content"].as_s)
    #   end
    # end
    # ```
    def self.from_sepia_with_generation(sepia_string : String, &)
      data = JSON.parse(sepia_string)

      # Extract generation info if present
      if data.has_key?("_generation")
        # Store generation info in the object after creation
        # This will be handled by the including class
        data.delete("_generation")
      end
      if data.has_key?("_base_id")
        data.delete("_base_id")
      end

      # Call the original from_sepia with cleaned data
      yield data.to_json
    end
  end
end

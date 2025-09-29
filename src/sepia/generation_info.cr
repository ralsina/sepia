module Sepia
  # Module that can be included to add generation information to JSON serialization
  module GenerationInfo
    # Override to_sepia to include generation info
    def to_sepia : String
      data = JSON.parse(super)
      data["_generation"] = generation
      data["_base_id"] = base_id
      data.to_json
    end

    # Override from_sepia to handle generation info
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

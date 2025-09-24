require "uuid"

module Sepia
  class Object
    # Sepia objects MUST have a sepia_id property which defaults to a lazy UUID
    getter sepia_id : String = UUID.random.to_s

    def sepia_id=(id : String)
      @sepia_id = id
    end

    # Sepia objects know how to save themselves
    def save(path : String? = nil)
      Sepia::Storage::INSTANCE.save(self, path)
    end

    # Sepia objects can load themselves from storage
    def self.load(id : String, path : String? = nil) : self
      Sepia::Storage::INSTANCE.load(self, id, path)
    end

    # Sepia objects can delete themselves from storage
    def delete
      Sepia::Storage::INSTANCE.delete(self)
    end

    # Returns the canonical path for the object in storage.
    def canonical_path : String
      File.join(Sepia::Storage::INSTANCE.path, self.class.name, sepia_id)
    end
  end
end
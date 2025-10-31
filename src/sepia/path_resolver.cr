module Sepia
  # Utility class for resolving file system paths to Sepia objects
  #
  # This helper provides methods to convert file system paths back to
  # Sepia objects, which is particularly useful for file system watchers
  # and other tools that need to map file paths back to object instances.
  #
  # ### Example
  #
  # ```
  # # Given a file path like "/data/MyDocument/uuid-123"
  # resolver = Sepia::PathResolver.new("/data")
  #
  # info = resolver.resolve_path("/data/MyDocument/uuid-123")
  # info.class_name # => "MyDocument"
  # info.object_id  # => "uuid-123"
  # info.full_path  # => "/data/MyDocument/uuid-123"
  # ```
  class PathResolver
    # Information about a resolved Sepia object path
    struct ObjectInfo
      property class_name : String
      property object_id : String
      property full_path : String
      property relative_path : String
      property storage_path : String

      def initialize(@class_name : String, @object_id : String, @full_path : String, @relative_path : String, @storage_path : String)
      end

      # Check if this path represents a Container object
      def container? : Bool
        File.directory?(@full_path)
      end

      # Check if this path represents a Serializable object
      def serializable? : Bool
        File.file?(@full_path)
      end

      # Load the actual Sepia object from storage using a given class
      #
      # ```
      # obj = info.object(TestDocument)
      # if obj
      #   puts "Loaded #{obj.class.name} with ID #{obj.sepia_id}"
      # end
      # ```
      def object(klass : Class) : Object?
        # Create a temporary storage backend for this specific path
        # This ensures we load from the correct location
        file_storage = Sepia::FileStorage.new(@storage_path)

        begin
          file_storage.load(klass, @object_id, @full_path)
        rescue ex
          nil
        end
      end
    end

    # Base storage path for resolving objects
    property storage_path : String

    # Creates a new PathResolver
    #
    # ```
    # resolver = PathResolver.new("/data/sepia")
    # resolver = PathResolver.new(Sepia::Storage.instance.path)
    # ```
    def initialize(@storage_path : String)
    end

    # Resolve a file system path to Sepia object information
    #
    # ```
    # info = resolver.resolve_path("/data/MyDocument/uuid-123")
    # info.class_name # => "MyDocument"
    # info.object_id  # => "uuid-123"
    # ```
    def resolve_path(full_path : String) : ObjectInfo?
      # Normalize paths
      storage_path = File.expand_path(@storage_path)
      full_path = File.expand_path(full_path)

      # Check if the path is within the storage directory
      return nil unless full_path.starts_with?(storage_path)

      # Extract relative path
      relative_path = full_path[storage_path.size..-1]
      relative_path = relative_path.lstrip('/')

      # Split path components
      parts = relative_path.split('/')
      return nil unless parts.size >= 2

      class_name = parts[0]
      object_id = parts[1]

      return nil if class_name.empty? || object_id.empty?

      ObjectInfo.new(
        class_name: class_name,
        object_id: object_id,
        full_path: full_path,
        relative_path: relative_path,
        storage_path: storage_path
      )
    end

    # Resolve a path and load the actual Sepia object
    #
    # This is a convenience method that combines resolve_path and object loading
    #
    # ```
    # obj = resolver.resolve_and_load("/data/MyDocument/uuid-123", TestDocument)
    # if obj
    #   puts "Loaded: #{obj.class.name} (#{obj.sepia_id})"
    # end
    # ```
    def resolve_and_load(full_path : String, klass : Class) : Object?
      info = resolve_path(full_path)
      return nil unless info

      info.object(klass)
    end

    # List all Sepia objects in the storage directory
    #
    # Returns an array of ObjectInfo for all found objects
    #
    # ```
    # resolver = PathResolver.new("/data")
    # objects = resolver.list_all_objects
    # objects.each do |info|
    #   puts "#{info.class_name}: #{info.object_id}"
    # end
    # ```
    def list_all_objects : Array(ObjectInfo)
      objects = [] of ObjectInfo
      return objects unless Dir.exists?(@storage_path)

      Dir.each_child(@storage_path) do |class_name|
        class_dir = File.join(@storage_path, class_name)
        next unless File.directory?(class_dir)

        Dir.each_child(class_dir) do |object_id|
          object_path = File.join(class_dir, object_id)
          next unless File.file?(object_path) || File.directory?(object_path)

          info = ObjectInfo.new(
            class_name: class_name,
            object_id: object_id,
            full_path: object_path,
            relative_path: File.join(class_name, object_id),
            storage_path: @storage_path
          )
          objects << info
        end
      end

      objects
    end

    # Check if a path is a valid Sepia object path
    #
    # ```
    # if resolver.valid_sepia_path?("/data/MyDocument/uuid-123")
    #   puts "This is a valid Sepia object path"
    # end
    # ```
    def valid_sepia_path?(path : String) : Bool
      !resolve_path(path).nil?
    end
  end
end

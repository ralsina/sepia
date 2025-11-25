require "json"
require "./event_logger"
require "./watcher"

module Sepia
  # Module for objects that contain other Sepia objects.
  #
  # The `Container` module enables objects to contain nested Serializable or
  # Container objects. Containers serialize as directories on disk, with
  # contained objects stored as files, subdirectories, or symlinks.
  #
  # ⚠️ **WARNING**: The Container API and on-disk format are subject to change.
  # Data migrations will be required when upgrading Sepia versions.
  #
  # ### Key Features
  #
  # - **Automatic JSON Serialization**: Primitive properties are automatically
  #   serialized to a `data.json` file
  # - **Nested Object Storage**: Contained Sepia objects are stored as references
  # - **Complex Structure Support**: Handles Arrays, Hashes, Sets, and nilable references
  # - **Symlink References**: Serializable objects are stored as symlinks to avoid duplication
  #
  # ### Directory Structure
  #
  # ```
  # container_id/
  #   ├── data.json           # Primitive properties (automatic)
  #   ├── simple_array/       # Array of primitives
  #   │   ├── 0000_value1
  #   │   └── 0001_value2
  #   ├── object_array/       # Array of Sepia objects
  #   │   ├── 0000 -> ../../ClassName/id1
  #   │   └── 0001 -> ../../ClassName/id2
  #   ├── nested_object/      # Single Sepia object
  #   │   └── 0000 -> ../../OtherClass/id
  #   └── complex_hash/       # Hash with mixed types
  #       ├── key1/value1     # Primitive value
  #       └── key2 -> ../../RefClass/id  # Sepia object reference
  # ```
  #
  # ### Example
  #
  # ```
  # class Project < Sepia::Object
  #   include Sepia::Container
  #
  #   # Primitive properties - automatically serialized
  #   property name : String
  #   property created_at : Time
  #   property tags : Array(String)
  #
  #   # Sepia object references - stored as symlinks
  #   owner : User?
  #   tasks : Array(Task)
  #   metadata : Hash(String, Document)?
  #
  #   def initialize(@name = "")
  #     @created_at = Time.utc
  #     @tags = [] of String
  #     @tasks = [] of Task
  #   end
  # end
  #
  # project = Project.new("My Project")
  # project.owner = user            # User object
  # project.tasks << task1 << task2 # Task objects
  # project.save                    # Creates directory structure
  # ```
  module Container
    # When included, sets up JSON serialization and registers the class.
    #
    # This macro:
    # - Includes JSON::Serializable for automatic JSON support
    # - Registers the class as a Container type with Sepia
    macro included
      include JSON::Serializable
      Sepia.register_class_type({{@type.name.stringify}}, true)

      # Add class property for event logging configuration
      #
      # This property controls whether events for this class should be logged.
      # Set to true to enable event logging for all instances of this class.
      #
      # ### Example
      #
      # ```
      # class MyProject < Sepia::Object
      #   include Sepia::Container
      #   sepia_log_events true
      # end
      #
      # MyProject.sepia_log_events # => true
      # ```
      class_property sepia_log_events : Bool = false

      # Enable event logging for this class.
      #
      # This macro configures whether instances of this class should have
      # their save operations logged to the event system.
      #
      # ### Example
      #
      # ```
      # class Project < Sepia::Object
      #   include Sepia::Container
      #   sepia_log_events true # Enable logging for this class
      # end
      # ```
      macro sepia_log_events_enabled
        @@sepia_log_events = true
      end

      # Disable event logging for this class.
      #
      # This macro configures whether instances of this class should have
      # their save operations logged to the event system.
      #
      # ### Example
      #
      # ```
      # class Project < Sepia::Object
      #   include Sepia::Container
      #   sepia_log_events false # Disable logging for this class
      # end
      # ```
      macro sepia_log_events_disabled
        @@sepia_log_events = false
      end

      # Legacy macro for backward compatibility
      macro sepia_log_events(enabled)
        sepia_log_events_enabled
      end
    end

    # Serializes only primitive properties to JSON.
    #
    # This method automatically filters out any Sepia object references,
    # serializing only primitive types (String, Int32, Bool, Time, etc.)
    # and collections of primitives. The resulting JSON is stored in
    # the container's `data.json` file.
    #
    # ### Returns
    #
    # A JSON string containing only the primitive properties of the container.
    #
    # ### Example
    #
    # ```
    # class UserProfile < Sepia::Object
    #   include Sepia::Container
    #   property name : String         # Included in JSON
    #   property age : Int32           # Included in JSON
    #   property friends : Array(User) # Excluded (Sepia objects)
    #
    #   def initialize(@name = "", @age = 0)
    #     @friends = [] of User
    #   end
    # end
    #
    # profile = UserProfile.new("Alice", 30)
    # json = profile.to_filtered_json
    # # json = {"name":"Alice","age":30,"friends":[]}
    # ```
    def to_filtered_json : String
      String.build do |io|
        JSON.build(io) do |json|
          json.object do
            {% for ivar in @type.instance_vars %}
              {% unless ivar.type < Sepia::Object ||
                          (ivar.type.union? && ivar.type.union_types.any? { |t| t < Sepia::Object }) ||
                          (ivar.type.stringify.includes?("Array") && ivar.type.type_vars.size > 0 && ivar.type.type_vars.first < Sepia::Object) ||
                          (ivar.type.stringify.includes?("Set") && ivar.type.type_vars.size > 0 && ivar.type.type_vars.first < Sepia::Object) ||
                          (ivar.type.stringify.includes?("Hash") && ivar.type.type_vars.size > 1 && ivar.type.type_vars.last < Sepia::Object) ||
                          ivar.name.stringify == "sepia_id" %}
                json.field {{ivar.name.stringify}}, @{{ivar.name}}
              {% end %}
            {% end %}
          end
        end
      end
    end

    # Returns all Sepia objects referenced by this container.
    #
    # This method automatically inspects all instance variables and collects
    # any Sepia objects, including those nested in Arrays, Hashes, and Sets.
    # Used by the garbage collector to track object relationships.
    #
    # ### Returns
    #
    # An Enumerable containing all Sepia objects referenced by this container.
    #
    # ### Example
    #
    # ```
    # class Team < Sepia::Object
    #   include Sepia::Container
    #   property members : Array(User)
    #   property lead : User?
    #   property projects : Hash(String, Project)
    #
    #   def initialize
    #     @members = [] of User
    #     @projects = {} of String => Project
    #   end
    # end
    #
    # team = Team.new
    # team.members << user1 << user2
    # team.lead = user3
    # team.projects["web"] = project1
    #
    # refs = team.sepia_references
    # # refs contains [user1, user2, user3, project1]
    # ```
    def sepia_references : Enumerable(Sepia::Object)
      refs = [] of Sepia::Object
      {% for ivar in @type.instance_vars %}
        value = @{{ivar.name}}
        if value.is_a?(Sepia::Object)
          refs << value
        elsif value.is_a?(Enumerable)
          value.each do |item|
            add_sepia_object_to_refs(item, refs)
          end
        elsif value.is_a?(Hash)
          value.each_value do |item|
            add_sepia_object_to_refs(item, refs)
          end
        end
      {% end %}
      refs
    end

    private def add_sepia_object_to_refs(item, refs : Array(Sepia::Object))
      if item.is_a?(Sepia::Object)
        refs << item
      end
    end

    # Saves all references (Serializable, Container, Enumerable of either)
    # to the container's path.
    def save_references(path : String)
      # Mark the container directory and data.json as internal
      Watcher.add_internal_file(path)
      data_file = File.join(path, "data.json")
      Watcher.add_internal_file(data_file)

      begin
        # Save object references (existing behavior)
        {% for ivar in @type.instance_vars %}
          save_value(path, @{{ivar.name}}, {{ivar.name.stringify}})
        {% end %}

        # Save primitive properties to JSON
        File.write(data_file, to_filtered_json)

        # Remove files from internal tracking after a brief delay
        spawn do
          sleep 0.3.seconds
          Watcher.remove_internal_file(path)
          Watcher.remove_internal_file(data_file)
        end
      rescue ex
        # Ensure cleanup even on error
        Watcher.remove_internal_file(path)
        Watcher.remove_internal_file(data_file)
        raise ex
      end
    end

    private def save_value(path, value : Serializable?, name)
      # Creates a reference to a Serializable object within the container's directory.
      #
      # SMART SAVE BEHAVIOR: Objects are only saved if they don't already exist
      # in storage. This prevents duplicate saves and unnecessary I/O operations
      # when users save both individual objects and their containers.
      #
      # Example workflow:
      # note.save           # Saves note (gen 1)
      # list.notes << note
      # list.save           # Smart: note not saved again, just reference created
      #
      # note.content = "Updated"
      # note.save           # Saves note (gen 2)
      # list.save           # Smart: note not saved again
      if obj = value
        # Smart save: only save if object doesn't exist in storage yet
        unless Sepia::Storage.exists?(obj.class, obj.sepia_id)
          obj.save
        end

        # Check if we're using InMemoryStorage
        if Sepia::Storage.backend.is_a?(InMemoryStorage)
          # Use in-memory reference storage
          Sepia::Storage.backend.as(InMemoryStorage).store_reference(path, name, obj.class.name, obj.sepia_id)
        else
          # Use filesystem symlinks
          symlink_path = File.join(path, name)
          obj_path = File.join(Sepia::Storage::INSTANCE.path, obj.class.name, obj.sepia_id)

          # Mark symlink as internal
          Watcher.add_internal_file(symlink_path)

          begin
            FileUtils.ln_s(Path[obj_path].relative_to(Path[symlink_path].parent), symlink_path)

            # Remove symlink from internal tracking after a brief delay
            spawn do
              sleep 0.3.seconds
              Watcher.remove_internal_file(symlink_path)
            end
          rescue ex
            # Ensure cleanup even on error
            Watcher.remove_internal_file(symlink_path)
            raise ex
          end
        end
      end
    end

    private def save_value(path, value : Container?, name)
      # Saves a nested Container object by creating a subdirectory for it
      # and recursively calling `save_references` on it.
      #
      # SMART SAVE BEHAVIOR: Container is only saved if it doesn't already
      # exist in storage. This prevents duplicate saves and maintains
      # consistency with Serializable object handling.
      if container = value
        # Smart save: only save if container doesn't exist in storage yet
        unless Sepia::Storage.exists?(container.class, container.sepia_id)
          container.save
        end
        container_path = File.join(path, name)
        Watcher.add_internal_file(container_path)
        begin
          FileUtils.mkdir_p(container_path)
          container.save_references(container_path)

          # Remove from internal tracking after a brief delay
          spawn do
            sleep 0.3.seconds
            Watcher.remove_internal_file(container_path)
          end
        rescue ex
          # Ensure cleanup even on error
          Watcher.remove_internal_file(container_path)
          raise ex
        end
      end
    end

    private def save_value(path, value : Enumerable(Sepia::Object)?, name)
      # Saves an Enumerable (e.g., Array, Set) of Serializable or Container objects.
      #
      # SMART SAVE BEHAVIOR: Each object in the enumerable is only saved if it
      # doesn't already exist in storage. The recursive save_value calls will
      # handle the existence checking automatically.
      if array = value
        return if array.empty?
        array_dir = File.join(path, name)
        Watcher.add_internal_file(array_dir)
        begin
          FileUtils.rm_rf(array_dir)
          FileUtils.mkdir_p(array_dir)

          array.each_with_index do |obj, index|
            save_value(array_dir, obj, "#{index.to_s.rjust(4, '0')}_#{obj.sepia_id}")
          end

          # Remove from internal tracking after a brief delay
          spawn do
            sleep 0.3.seconds
            Watcher.remove_internal_file(array_dir)
          end
        rescue ex
          # Ensure cleanup even on error
          Watcher.remove_internal_file(array_dir)
          raise ex
        end
      end
    end

    private def save_value(path, value : Hash(String, Sepia::Object)?, name)
      # Saves a Hash with String keys and Serializable or Container values.
      if hash = value
        return if hash.empty?
        hash_dir = File.join(path, name)
        Watcher.add_internal_file(hash_dir)
        begin
          FileUtils.rm_rf(hash_dir)
          FileUtils.mkdir_p(hash_dir)

          hash.each do |key, obj|
            save_value(hash_dir, obj, key)
          end

          # Remove from internal tracking after a brief delay
          spawn do
            sleep 0.3.seconds
            Watcher.remove_internal_file(hash_dir)
          end
        rescue ex
          # Ensure cleanup even on error
          Watcher.remove_internal_file(hash_dir)
          raise ex
        end
      end
    end

    private def save_value(path, value, name)
      # This is a catch-all for types that are not Serializable, Container,
      # or collections of them. These types are not persisted by Sepia.
      # Do nothing for other types
    end

    # Loads all references (Serializable, Container, Enumerable of either)
    # from the container's path.
    def load_references(path : String)
      {% for ivar in @type.instance_vars %}
        # For each instance variable, check if it's a Serializable or a Container.
        # Handle both direct Serializable types and nilable Serializables (unions)
        {% if ivar.type < Sepia::Serializable || (ivar.type.union? && ivar.type.union_types.any? { |type| type < Sepia::Serializable }) %}
          # Determine the actual Serializable type (for union types, find the non-nil type)
          {% if ivar.type < Sepia::Serializable %}
            {% serializable_type = ivar.type %}
          {% else %}
            {% serializable_type = nil %}
            {% for type in ivar.type.union_types %}
              {% if type < Sepia::Serializable %}
                {% serializable_type = type %}
              {% end %}
            {% end %}
          {% end %}
          # Check if we're using InMemoryStorage
          if Sepia::Storage.backend.is_a?(InMemoryStorage)
            # Load from in-memory reference storage
            ref_key = Sepia::Storage.backend.as(InMemoryStorage).get_reference(path, {{ivar.name.stringify}})
            if ref_key
              obj_class_name, obj_id = ref_key.split('/', 2)
              @{{ ivar.name }} = Sepia::Storage::INSTANCE.load({{serializable_type}}, obj_id).as({{ ivar.type }})
            else
              {% if ivar.type.nilable? %}
                @{{ ivar.name }} = nil
              {% else %}
                raise "Missing required reference for '" + {{ivar.name.stringify}} + "' in container at " + path
              {% end %}
            end
          else
            # Load from filesystem symlinks
            symlink_path = File.join(path, {{ivar.name.stringify}})
            if File.symlink?(symlink_path)
              # See where the symlink points to - it might be relative or absolute
              obj_path = File.readlink(symlink_path)
              # Resolve to absolute path
              abs_obj_path = if obj_path.starts_with?("/")
                               obj_path
                             else
                               File.expand_path(obj_path, File.dirname(symlink_path))
                             end
              obj_id = File.basename(abs_obj_path)
              # Read the file directly
              obj = {{serializable_type}}.from_sepia(File.read(abs_obj_path))
              obj.sepia_id = obj_id
              @{{ ivar.name }} = obj.as({{ ivar.type }})
            else
              {% if ivar.type.nilable? %}
                @{{ ivar.name }} = nil
              {% else %}
                raise "Missing required reference for '#{symlink_path}' for non-nilable property '{{ivar.name}}'"
              {% end %}
            end
          end
        {% elsif ivar.type < Sepia::Container %}
          container_path = File.join(path, {{ivar.name.stringify}})
          if Dir.exists?(container_path)
            @{{ivar.name}} = {{ivar.type}}.new
            @{{ivar.name}}.as({{ivar.type}}).sepia_id = {{ivar.name.stringify}}
            @{{ivar.name}}.as(Container).load_references(container_path)
          else
            {% if ivar.type.nilable? %}
              @{{ivar.name}} = nil
            {% end %}
          end
        {% elsif ivar.type < Enumerable && ivar.type.type_vars.first < Sepia::Serializable %}
          array_dir = File.join(path, {{ivar.name.stringify}})
          if Dir.exists?(array_dir)
            @{{ivar.name}} = load_enumerable_of_references(path, {{ivar.name.stringify}}, {{ivar.type}}, {{ivar.type.type_vars.first}})
          else
            {% if ivar.type.union? %} # It's nilable
              @{{ivar.name}} = nil
            {% else %} # It's not nilable, so create empty array
              @{{ivar.name}} = {{ivar.type}}.new
            {% end %}
          end
        {% elsif ivar.type < Enumerable && ivar.type.type_vars.first < Sepia::Container %}
          array_dir = File.join(path, {{ivar.name.stringify}})
          if Dir.exists?(array_dir)
            @{{ivar.name}} = load_enumerable_of_containers(path, {{ivar.name.stringify}}, {{ivar.type}}, {{ivar.type.type_vars.first}})
          else
            {% if ivar.type.union? %} # It's nilable
              @{{ivar.name}} = nil
            {% else %} # It's not nilable, so create empty array
              @{{ivar.name}} = {{ivar.type}}.new
            {% end %}
          end
        {% elsif ivar.type < Hash && ivar.type.type_vars.first == String && ivar.type.type_vars.last < Sepia::Serializable %}
          hash_dir = File.join(path, {{ivar.name.stringify}})
          if Dir.exists?(hash_dir)
            @{{ivar.name}} = load_hash_of_references(path, {{ivar.name.stringify}}, {{ivar.type}}, {{ivar.type.type_vars.last}})
          else
            {% if ivar.type.union? %} # It's nilable
              @{{ivar.name}} = nil
            {% else %} # It's not nilable, so create empty hash
              @{{ivar.name}} = {{ivar.type}}.new
            {% end %}
          end
        {% elsif ivar.type < Hash && ivar.type.type_vars.first == String && ivar.type.type_vars.last < Sepia::Container %}
          hash_dir = File.join(path, {{ivar.name.stringify}})
          if Dir.exists?(hash_dir)
            @{{ivar.name}} = load_hash_of_containers(path, {{ivar.name.stringify}}, {{ivar.type}}, {{ivar.type.type_vars.last}})
          else
            {% if ivar.type.union? %} # It's nilable
              @{{ivar.name}} = nil
            {% else %} # It's not nilable, so create empty hash
              @{{ivar.name}} = {{ivar.type}}.new
            {% end %}
          end
        {% end %}
      {% end %}

      # Load primitive properties from JSON
      data_file = File.join(path, "data.json")
      if File.exists?(data_file)
        json_data = File.read(data_file)
        unless json_data.empty?
          # Parse JSON and extract primitive properties
          parser = JSON::Parser.new(json_data)
          data = parser.parse

          if data_hash = data.as_h?
            {% for ivar in @type.instance_vars %}
                {% unless ivar.type < Sepia::Object ||
                            (ivar.type.union? && ivar.type.union_types.any? { |t| t < Sepia::Object }) ||
                            (ivar.type.stringify.includes?("Array") && ivar.type.type_vars.size > 0 && ivar.type.type_vars.first < Sepia::Object) ||
                            (ivar.type.stringify.includes?("Set") && ivar.type.type_vars.size > 0 && ivar.type.type_vars.first < Sepia::Object) ||
                            (ivar.type.stringify.includes?("Hash") && ivar.type.type_vars.size > 1 && ivar.type.type_vars.last < Sepia::Object) ||
                            ivar.name.stringify == "sepia_id" %}
                  # Find the key (it might be a JSON::Any)
                  key = data_hash.keys.find { |k| k.to_s == {{ivar.name.stringify}} }
                  if key
                    value = data_hash[key]
                    # Use JSON::Serializable's built-in parsing
                    {% if ivar.type.stringify.includes?("Array") %}
                      parsed_value = Array({{ivar.type.type_vars.first}}).from_json(value.to_json)
                    {% elsif ivar.type.stringify.includes?("Hash") %}
                      parsed_value = Hash({{ivar.type.type_vars.first}}, {{ivar.type.type_vars.last}}).from_json(value.to_json)
                    {% else %}
                      parsed_value = {{ivar.type}}.from_json(value.to_json)
                    {% end %}
                    @{{ivar.name}} = parsed_value
                  end
                {% end %}
              {% end %}
          end
        end
      end
    end

    # Restore primitive properties from JSON without creating a new instance
    def restore_properties_from_json(json_data : String)
      return if json_data.empty?

      # Parse JSON and extract primitive properties
      parser = JSON::Parser.new(json_data)
      data = parser.parse

      if data_hash = data.as_h?
        {% for ivar in @type.instance_vars %}
          {% unless ivar.type < Sepia::Object ||
                      (ivar.type.union? && ivar.type.union_types.any? { |t| t < Sepia::Object }) ||
                      (ivar.type.stringify.includes?("Array") && ivar.type.type_vars.size > 0 && ivar.type.type_vars.first < Sepia::Object) ||
                      (ivar.type.stringify.includes?("Set") && ivar.type.type_vars.size > 0 && ivar.type.type_vars.first < Sepia::Object) ||
                      (ivar.type.stringify.includes?("Hash") && ivar.type.type_vars.size > 1 && ivar.type.type_vars.last < Sepia::Object) ||
                      ivar.name.stringify == "sepia_id" %}
            key = data_hash.keys.find { |k| k.to_s == {{ivar.name.stringify}} }
            if key
              value = data_hash[key]
              # Parse the value based on type
              {% if ivar.type.stringify.includes?("Array") %}
                parsed_value = Array({{ivar.type.type_vars.first}}).from_json(value.to_json)
              {% elsif ivar.type.stringify.includes?("Hash") %}
                parsed_value = Hash({{ivar.type.type_vars.first}}, {{ivar.type.type_vars.last}}).from_json(value.to_json)
              {% else %}
                parsed_value = {{ivar.type}}.from_json(value.to_json)
              {% end %}
              @{{ivar.name}} = parsed_value
            end
          {% end %}
        {% end %}
      end
    end

    # Loads an enumerable of serializable objects from a directory of symlinks.
    def load_enumerable_of_references(path : String, name : String, collection_type : T.class, item_type : U.class) forall T, U
      array_dir = File.join(path, name)
      loaded_collection = T.new
      if Dir.exists?(array_dir)
        symlinks = Dir.entries(array_dir).reject { |e| e == "." || e == ".." }.sort!
        symlinks.each do |entry|
          symlink_path = File.join(array_dir, entry)
          if File.symlink?(symlink_path)
            obj_path = File.readlink(symlink_path)
            # Resolve to absolute path
            abs_obj_path = if obj_path.starts_with?("/")
                             obj_path
                           else
                             File.expand_path(obj_path, File.dirname(symlink_path))
                           end
            obj_id = File.basename(abs_obj_path)
            # Load the object directly from file
            loaded_obj = item_type.from_sepia(File.read(abs_obj_path))
            loaded_obj.sepia_id = obj_id
            if loaded_obj.is_a?(Container)
              # For containers, obj_path might be relative, resolve it
              container_path = abs_obj_path
              loaded_obj.load_references(File.dirname(container_path))
            end
            loaded_collection << loaded_obj.as(U)
          end
        end
      end
      loaded_collection
    end

    # Loads an enumerable of containers from a directory of subdirectories.
    def load_enumerable_of_containers(path : String, name : String, collection_type : T.class, item_type : U.class) forall T, U
      array_dir = File.join(path, name)
      loaded_collection = T.new
      if Dir.exists?(array_dir)
        dirs = Dir.entries(array_dir).reject { |e| e == "." || e == ".." }.sort!
        dirs.each do |entry|
          container_path = File.join(array_dir, entry)
          if Dir.exists?(container_path)
            container = U.new
            # Extract the sepia_id from the filename (e.g., "00000_some_id" -> "some_id")
            container.sepia_id = entry.split("_", 2)[1]
            container.load_references(container_path)
            loaded_collection << container
          end
        end
      end
      loaded_collection
    end

    # Loads a hash of serializable objects from a directory of symlinks.
    def load_hash_of_references(path : String, name : String, collection_type : T.class, item_type : U.class) forall T, U
      hash_dir = File.join(path, name)
      loaded_hash = T.new
      if Dir.exists?(hash_dir)
        symlinks = Dir.entries(hash_dir).reject { |e| e == "." || e == ".." }
        symlinks.each do |entry|
          symlink_path = File.join(hash_dir, entry)
          if File.symlink?(symlink_path)
            obj_path = File.readlink(symlink_path)
            obj_id = File.basename(obj_path)
            loaded_obj = Sepia::Storage::INSTANCE.load(item_type, obj_id)
            loaded_hash[entry] = loaded_obj.as(U)
          end
        end
      end
      loaded_hash
    end

    # Loads a hash of containers from a directory of subdirectories.
    def load_hash_of_containers(path : String, name : String, collection_type : T.class, item_type : U.class) forall T, U
      hash_dir = File.join(path, name)
      loaded_hash = T.new
      if Dir.exists?(hash_dir)
        dirs = Dir.entries(hash_dir).reject { |e| e == "." || e == ".." }
        dirs.each do |entry|
          container_path = File.join(hash_dir, entry)
          if Dir.exists?(container_path)
            container = U.new
            container.sepia_id = entry
            container.load_references(container_path)
            loaded_hash[entry] = container
          end
        end
      end
      loaded_hash
    end

    # Logs an activity event for this container.
    #
    # This method allows containers to log arbitrary activities that are not
    # related to object persistence (save/delete operations). Activities
    # are stored in the container's event log alongside other events.
    #
    # ### Parameters
    #
    # - *action* : Description of the activity (e.g., "moved_lane", "edited")
    # - *metadata* : Optional metadata for the activity (caller's responsibility for JSON serializability)
    #
    # ### Example
    #
    # ```
    # board.log_activity("lane_created", {"lane_name" => "Review", "user" => "alice"})
    #
    # # Simple version
    # board.log_activity("color_changed")
    # ```
    def log_activity(action : String, metadata)
      # Combine action with metadata
      activity_metadata = {"action" => action}.merge(metadata)

      # Log the activity event if this class has logging enabled
      if self.class.responds_to?(:sepia_log_events) && self.class.sepia_log_events
        # Get the current generation for this object
        current_generation = EventLogger.current_generation(self.class, self.sepia_id)
        EventLogger.append_event(self, LogEventType::Activity, current_generation, activity_metadata)
      end
    end

    # Logs an activity event for this object (without metadata).
    #
    # This method allows objects to log arbitrary activities that are not
    # related to object persistence (save/delete operations). Activities
    # are stored in the object's event log alongside other events.
    #
    # ### Parameters
    #
    # - *action* : Description of the activity (e.g., "moved_lane", "edited")
    #
    # ### Example
    #
    # ```
    # board.log_activity("color_changed")
    # ```
    def log_activity(action : String)
      # Create metadata with just the action
      activity_metadata = {"action" => action}

      # Log the activity event if this class has logging enabled
      if self.class.responds_to?(:sepia_log_events) && self.class.sepia_log_events
        # Get the current generation for this object
        current_generation = EventLogger.current_generation(self.class, self.sepia_id)
        EventLogger.append_event(self, LogEventType::Activity, current_generation, activity_metadata)
      end
    end
  end
end

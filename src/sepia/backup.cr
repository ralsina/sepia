require "crystar"
require "file_utils"
require "json"

module Sepia
  # Backup-specific exception classes
  class BackupError < Exception
  end

  class BackendNotSupportedError < BackupError
  end

  class BackupCreationError < BackupError
  end

  class BackupCorruptionError < BackupError
  end

  class Backup
    # Backup and restore functionality for Sepia object trees
    #
    # This class provides comprehensive backup/restore capabilities using tar archives.
    # It preserves object relationships, symlinks, and directory structures.
    #
    # ### Example
    #
    # ```
    # # Create backup of object tree
    # root_objects = [document, project, user]
    # backup_path = Sepia::Backup.create(root_objects, "backup.sepia.tar")
    #
    # # Restore from backup
    # restored_objects = Sepia::Backup.restore("backup.sepia.tar")
    # ```
    # Object type classification for backup purposes
    enum ObjectType
      Serializable
      Container
    end

    # Simple configuration options for backup creation
    struct Configuration
      # Basic backup behavior
      # ameba:disable Naming/QueryBoolMethods
      property follow_symlinks : Bool = false # false preserves symlinks as-is

      def initialize
      end
    end

    # Represents a reference to an object in the backup
    struct ObjectReference
      property class_name : String
      property object_id : String
      property relative_path : String
      property object_type : ObjectType

      def initialize(@class_name : String, @object_id : String, @relative_path : String, @object_type : ObjectType)
      end

      def to_json(json : JSON::Builder)
        json.object do
          json.field "class_name", @class_name
          json.field "object_id", @object_id
          json.field "relative_path", @relative_path
          json.field "object_type", @object_type.to_s
        end
      end

      def self.from_json(json : JSON::PullParser)
        class_name = ""
        object_id = ""
        relative_path = ""
        object_type_str = ""

        json.read_object do |key|
          case key
          when "class_name"
            class_name = json.read_string
          when "object_id"
            object_id = json.read_string
          when "relative_path"
            relative_path = json.read_string
          when "object_type"
            object_type_str = json.read_string
          else
            json.skip
          end
        end

        object_type = object_type_str == "Container" ? ObjectType::Container : ObjectType::Serializable
        new(class_name, object_id, relative_path, object_type)
      end
    end

    # Represents a file to be included in the backup tarball
    struct BackupFile
      property path : String
      property content : Bytes
      property type : String
      property mode : Int64
      property symlink_target : String?

      def initialize(@path : String, @content : Bytes, @type : String, @mode : Int64, @symlink_target : String? = nil)
      end

      def initialize(@path : String, content_string : String, @type : String, @mode : Int64, @symlink_target : String? = nil)
        @content = content_string.to_slice
      end
    end

    # Manifest containing backup metadata and object information
    class BackupManifest
      property version : String = "1.0"
      property created_at : Time = Time.utc
      property root_objects : Array(ObjectReference)
      property all_objects : Hash(String, Array(ObjectReference))

      def initialize(@root_objects = [] of ObjectReference)
        # ameba:disable Naming/BlockParameterName
        @all_objects = Hash(String, Array(ObjectReference)).new { |h, k| h[k] = [] of ObjectReference }
      end

      def add_object(class_name : String, object_ref : ObjectReference)
        @all_objects[class_name] << object_ref
      end

      def to_json(json : JSON::Builder)
        json.object do
          json.field "version", @version
          json.field "created_at", @created_at.to_rfc3339
          json.field "root_objects" do
            @root_objects.to_json(json)
          end
          json.field "all_objects" do
            json.object do
              @all_objects.each do |class_name, objects|
                json.field class_name do
                  objects.to_json(json)
                end
              end
            end
          end
        end
      end

      def self.from_json(json : JSON::PullParser)
        manifest = new
        json.read_object do |key|
          case key
          when "version"
            manifest.version = json.read_string
          when "created_at"
            manifest.created_at = Time.parse_rfc3339(json.read_string)
          when "root_objects"
            manifest.root_objects = Array(ObjectReference).from_json(json)
          when "all_objects"
            json.read_object do |class_name|
              manifest.all_objects[class_name] = Array(ObjectReference).from_json(json)
            end
          else
            json.skip
          end
        end
        manifest
      end
    end

    # Result of backup verification
    struct BackupVerificationResult
      # ameba:disable Naming/QueryBoolMethods
      property valid : Bool
      property errors : Array(String)
      property statistics : BackupStatistics

      def initialize(@valid = true)
        @errors = [] of String
        @statistics = BackupStatistics.new
      end

      def add_error(error : String)
        @valid = false
        @errors << error
      end
    end

    # Statistics about backup contents
    struct BackupStatistics
      property total_objects : Int32 = 0
      property serializable_objects : Int32 = 0
      property container_objects : Int32 = 0
      property total_files : Int32 = 0
      property total_size : Int64 = 0
      property classes : Set(String) = Set(String).new

      def add_object(class_name : String, object_type : ObjectType)
        @total_objects += 1
        @classes << class_name

        case object_type
        when .serializable?
          @serializable_objects += 1
        when .container?
          @container_objects += 1
        end
      end
    end

    # Main backup class methods
    def self.create(root_objects : Array(Sepia::Object), output_path : String) : String
      create(root_objects, output_path, Configuration.new)
    end

    # Create backup with custom configuration
    def self.create(root_objects : Array(Sepia::Object), output_path : String, config : Configuration) : String
      manifest = BackupManifest.new

      # Add root objects to manifest
      root_objects.each do |obj|
        object_ref = ObjectReference.new(
          obj.class.name,
          obj.sepia_id,
          "#{obj.class.name}/#{obj.sepia_id}",
          determine_object_type(obj)
        )
        manifest.root_objects << object_ref
      end

      # Collect all objects by traversing references
      collected_objects = collect_all_objects(root_objects)

      # Update manifest with all objects
      collected_objects.each do |class_name, ids|
        ids.each do |id|
          object_ref = ObjectReference.new(
            class_name,
            id,
            "#{class_name}/#{id}",
            ObjectType::Serializable # Will be updated in file collection
          )
          manifest.add_object(class_name, object_ref)
        end
      end

      # Collect files for backup
      storage_path = get_storage_path()
      backup_files = collect_files_for_backup(collected_objects, storage_path, config)

      # Update manifest with correct object types based on actual files
      update_manifest_object_types(manifest, backup_files)

      # Create tar archive
      create_tar_archive(backup_files, manifest, output_path, config)

      output_path
    end

    # Lists contents of a backup without restoring
    #
    # This method allows applications to inspect what objects are contained in a backup
    # archive without performing a full restore. It extracts and parses the metadata
    # to return information about the backup contents.
    #
    # ### Parameters
    #
    # - *backup_path* : Path to the backup tar file
    #
    # ### Returns
    #
    # A BackupManifest containing information about the backup contents
    #
    # ### Example
    #
    # ```
    # # Inspect backup contents
    # manifest = Sepia::Backup.list_contents("user_backup.tar")
    # puts "Backup created: #{manifest.created_at}"
    # puts "Contains #{manifest.all_objects.values.map(&.size).sum} objects"
    # puts "Root objects: #{manifest.root_objects.map(&.object_id).join(", ")}"
    # ```
    #
    # ### Raises
    #
    # - `BackupCorruptionError` if the backup file is corrupted or missing metadata
    def self.list_contents(backup_path : String) : BackupManifest
      unless File.exists?(backup_path)
        raise BackupCorruptionError.new("Backup file does not exist: #{backup_path}")
      end

      metadata_content = extract_metadata_from_backup(backup_path)

      begin
        # Manually parse the JSON to avoid complex JSON parsing issues
        json_data = JSON.parse(metadata_content)

        # Create new manifest
        manifest = BackupManifest.new

        # Parse basic fields
        if json_data["version"]?
          manifest.version = json_data["version"].as_s
        end

        if json_data["created_at"]?
          manifest.created_at = Time.parse_rfc3339(json_data["created_at"].as_s)
        end

        # Parse root objects
        if json_data["root_objects"]?
          json_data["root_objects"].as_a.each do |root_obj|
            obj_ref = ObjectReference.new(
              root_obj["class_name"].as_s,
              root_obj["object_id"].as_s,
              root_obj["relative_path"].as_s,
              root_obj["object_type"].as_s == "Container" ? ObjectType::Container : ObjectType::Serializable
            )
            manifest.root_objects << obj_ref
          end
        end

        # Parse all objects
        if json_data["all_objects"]?
          json_data["all_objects"].as_h.each do |class_name, objects|
            objects.as_a.each do |obj_data|
              obj_ref = ObjectReference.new(
                obj_data["class_name"].as_s,
                obj_data["object_id"].as_s,
                obj_data["relative_path"].as_s,
                obj_data["object_type"].as_s == "Container" ? ObjectType::Container : ObjectType::Serializable
              )
              manifest.add_object(class_name, obj_ref)
            end
          end
        end
      rescue ex
        raise BackupCorruptionError.new("Failed to parse backup metadata: #{ex.message}")
      end

      manifest
    end

    # Extracts metadata from a backup file
    def self.get_metadata(backup_path : String) : BackupManifest
      list_contents(backup_path)
    end

    # Verifies backup integrity and structure
    #
    # This method checks that the backup file is well-formed and that all expected
    # files are present and readable. It provides detailed information about the
    # backup contents and any issues found.
    #
    # ### Parameters
    #
    # - *backup_path* : Path to the backup tar file
    #
    # ### Returns
    #
    # A BackupVerificationResult containing verification status and statistics
    #
    # ### Example
    #
    # ```
    # result = Sepia::Backup.verify("user_backup.tar")
    # if result.valid
    #   puts "Backup is valid"
    #   puts "Contains #{result.statistics.total_objects} objects"
    # else
    #   puts "Backup has issues:"
    #   result.errors.each { |error| puts "  - #{error}" }
    # end
    # ```
    #
    # ### Raises
    #
    # - `BackupCorruptionError` if the backup file is severely corrupted
    def self.verify(backup_path : String) : BackupVerificationResult
      result = BackupVerificationResult.new

      # Check file exists and is readable
      unless File.exists?(backup_path)
        result.add_error("Backup file does not exist: #{backup_path}")
        return result
      end

      begin
        # Extract and verify metadata
        manifest = list_contents(backup_path)

        # Populate statistics
        manifest.all_objects.each do |class_name, objects|
          objects.each do |obj_ref|
            result.statistics.add_object(class_name, obj_ref.object_type)
          end
        end

        # Verify tar structure
        backup_file_list = get_backup_file_list(backup_path)

        # Check for expected files
        expected_files = ["metadata.json", "README"]
        expected_files.each do |expected_file|
          unless backup_file_list.includes?(expected_file)
            result.add_error("Missing expected file: #{expected_file}")
          end
        end

        # Verify object files exist in tar
        manifest.all_objects.each do |class_name, objects|
          objects.each do |obj_ref|
            expected_path = "objects/#{class_name}/#{obj_ref.object_id}"
            if obj_ref.object_type.container?
              # For containers, check if directory structure exists
              container_files = backup_file_list.select(&.starts_with?("#{expected_path}/"))
              if container_files.empty?
                result.add_error("Missing container directory structure: #{expected_path}/")
              end
            else
              # For serializable objects, check if file exists
              unless backup_file_list.includes?(expected_path)
                result.add_error("Missing object file: #{expected_path}")
              end
            end
          end
        end
      rescue ex : BackupCorruptionError
        result.add_error("Backup corruption detected: #{ex.message}")
      rescue ex
        result.add_error("Unexpected error during verification: #{ex.message}")
      end

      result
    end

    # Restores objects from a backup archive
    #
    # This method is left for application-specific implementations as restore
    # logic varies greatly depending on business requirements, data migration
    # policies, and application-specific validation rules.
    #
    # ### Parameters
    #
    # - *backup_path* : Path to the backup tar file
    # - *target_storage_path* : Optional target storage path
    #
    # ### Returns
    #
    # Array of restored Sepia::Object instances
    #
    # ### Note
    #
    # This method raises NotImplementedError as restore functionality should be
    # implemented by applications based on their specific requirements.
    def self.restore(backup_path : String, target_storage_path : String? = nil) : Array(Sepia::Object)
      raise NotImplementedError.new("Restore functionality should be implemented by applications based on their specific requirements. Use list_contents() and verify() to analyze backups before implementing custom restore logic.")
    end

    # Private methods for backup implementation
    private def self.collect_all_objects(root_objects : Array(Sepia::Object)) : Hash(String, Set(String))
      # ameba:disable Naming/BlockParameterName
      collected = Hash(String, Set(String)).new { |h, k| h[k] = Set(String).new }

      root_objects.each do |obj|
        collect_object_recursive(obj, collected)
      end

      collected
    end

    private def self.collect_object_recursive(obj : Sepia::Object, collected : Hash(String, Set(String)))
      return if collected[obj.class.name]?.try(&.includes?(obj.sepia_id))

      collected[obj.class.name] << obj.sepia_id

      # If object responds to sepia_references, traverse them
      if obj.responds_to?(:sepia_references)
        references = obj.sepia_references
        references.each do |ref|
          collect_object_recursive(ref, collected) if ref.is_a?(Sepia::Object)
        end
      end
    end

    private def self.determine_object_type(obj : Sepia::Object) : ObjectType
      # Check if this is a Container object by checking if it has sepia_references method
      # and is not a simple Serializable object
      if obj.responds_to?(:sepia_references)
        # Check if it's a Container by looking at its storage structure
        storage_path = get_storage_path()
        if storage_path
          object_path = File.join(storage_path, obj.class.name, obj.sepia_id)

          if File.directory?(object_path)
            ObjectType::Container
          else
            ObjectType::Serializable
          end
        else
          # InMemoryStorage - assume Serializable
          ObjectType::Serializable
        end
      else
        ObjectType::Serializable
      end
    end

    # ameba:disable Naming/AccessorMethodName
    private def self.get_storage_path : String?
      backend = Sepia::Storage.backend
      if backend.is_a?(Sepia::FileStorage)
        backend.path
      else
        nil
      end
    end

    private def self.collect_files_for_backup(objects : Hash(String, Set(String)), storage_path : String?) : Array(BackupFile)
      collect_files_for_backup(objects, storage_path, Configuration.new)
    end

    private def self.collect_files_for_backup(objects : Hash(String, Set(String)), storage_path : String?, config : Configuration) : Array(BackupFile)
      backup_files = [] of BackupFile

      # If no storage path (InMemoryStorage), backup is not supported
      raise "Backup not supported with InMemoryStorage. Use FileStorage instead." unless storage_path

      objects.each do |class_name, ids|
        class_dir = File.join(storage_path, class_name)
        ids.each do |id|
          object_path = File.join(class_dir, id)

          if File.file?(object_path)
            # Serializable object - add the file
            content = File.read(object_path)
            backup_files << BackupFile.new(
              path: "objects/#{class_name}/#{id}",
              content_string: content,
              type: "file",
              mode: File.info(object_path).permissions.to_i64
            )
          elsif File.directory?(object_path)
            # Container object - recursively add directory contents
            collect_directory_contents(object_path, "objects/#{class_name}/#{id}", backup_files)
          else
            # Object not found, skip but could log warning
            puts "Warning: Object #{class_name}/#{id} not found at #{object_path}"
          end
        end
      end

      backup_files
    end

    private def self.collect_directory_contents(dir_path : String, relative_path : String, backup_files : Array(BackupFile))
      Dir.each_child(dir_path) do |entry_name|
        entry_path = File.join(dir_path, entry_name)
        entry_relative_path = File.join(relative_path, entry_name)

        info = File.info(entry_path)

        if info.file?
          # Regular file
          content = File.read(entry_path)
          backup_files << BackupFile.new(
            path: entry_relative_path,
            content_string: content,
            type: "file",
            mode: info.permissions.to_i64
          )
        elsif info.symlink?
          # Symlink - preserve the link target
          target = File.readlink(entry_path)
          backup_files << BackupFile.new(
            path: entry_relative_path,
            content: Bytes.new(0), # Empty content for symlink
            type: "symlink",
            mode: info.permissions.to_i64,
            symlink_target: target
          )
        elsif info.directory?
          # Subdirectory - recurse
          collect_directory_contents(entry_path, entry_relative_path, backup_files)
        end
      end
    end

    private def self.update_manifest_object_types(manifest : BackupManifest, backup_files : Array(BackupFile))
      # Update object types based on actual files found
      manifest.all_objects.each do |_class_name, object_refs|
        object_refs.each do |obj_ref|
          # Check if this object has a directory structure (container) or is just a file (serializable)
          dir_path = "objects/#{obj_ref.class_name}/#{obj_ref.object_id}"
          file_path = "objects/#{obj_ref.class_name}/#{obj_ref.object_id}"

          # Look for backup files that indicate the structure
          is_container = backup_files.any? do |backup_file|
            backup_file.path.starts_with?("#{dir_path}/") || backup_file.path == "#{file_path}/data.json"
          end

          if is_container
            obj_ref.object_type = ObjectType::Container
          else
            obj_ref.object_type = ObjectType::Serializable
          end
        end
      end
    end

    private def self.create_tar_archive(backup_files : Array(BackupFile), manifest : BackupManifest, output_path : String)
      create_tar_archive(backup_files, manifest, output_path, Configuration.new)
    end

    private def self.create_tar_archive(backup_files : Array(BackupFile), manifest : BackupManifest, output_path : String, config : Configuration)
      File.open(output_path, "wb") do |file|
        Crystar::Writer.open(file) do |tar|
          # Add all object files to the archive
          backup_files.each do |backup_file|
            add_file_to_tar(tar, backup_file)
          end

          # Add metadata file
          add_metadata_to_tar(tar, manifest)

          # Add README file
          add_readme_to_tar(tar, config)
        end
      end
    end

    private def self.add_file_to_tar(tar : Crystar::Writer, backup_file : BackupFile)
      if backup_file.type == "symlink"
        # Create symlink header using the flag parameter for type
        header = Crystar::Header.new(
          flag: 2_u8, # Symlink flag
          name: backup_file.path,
          mode: backup_file.mode,
          link_name: backup_file.symlink_target.not_nil!
        )
        tar.write_header(header)
      else
        # Create regular file header
        header = Crystar::Header.new(
          flag: 0_u8, # Regular file flag
          name: backup_file.path,
          mode: backup_file.mode,
          size: backup_file.content.size.to_i64
        )
        tar.write_header(header)
        tar.write(backup_file.content)
      end
    end

    private def self.add_metadata_to_tar(tar : Crystar::Writer, manifest : BackupManifest)
      metadata_json = manifest.to_json

      header = Crystar::Header.new(
        flag: 0_u8,
        name: "metadata.json",
        mode: 0o644_i64,
        size: metadata_json.size.to_i64
      )
      tar.write_header(header)
      tar.write(metadata_json.to_slice)
    end

    private def self.add_readme_to_tar(tar : Crystar::Writer)
      add_readme_to_tar(tar, Configuration.new)
    end

    private def self.add_readme_to_tar(tar : Crystar::Writer, config : Configuration)
      readme_content = <<-README
Sepia Backup Archive
==================

This is a Sepia object tree backup created at #{Time.utc}.

Archive Structure:
- metadata.json: Backup manifest containing object information
- objects/: All objects from the backup organized by class name and ID
  - ClassName/object_id: Serializable objects (files)
  - ClassName/object_id/: Container objects (directories with data.json and references)

The backup preserves:
- Object data and relationships
- Directory structure for Container objects
- Symlink relationships between objects

To inspect this backup, use:
  manifest = Sepia::Backup.list_contents("backup.sepia.tar")

For more information, see the Sepia documentation.
README

      header = Crystar::Header.new(
        flag: 0_u8,
        name: "README",
        mode: 0o644_i64,
        size: readme_content.size.to_i64
      )
      tar.write_header(header)
      tar.write(readme_content.to_slice)
    end

    # ## Private Helper Methods for Utility Functions

    # Extracts metadata.json from a backup tar file using system tar command
    private def self.extract_metadata_from_backup(backup_path : String) : String
      # Use system tar command to extract metadata.json to stdout
      result = IO::Memory.new
      status = Process.run("tar", {"-xOf", backup_path, "metadata.json"}, output: result, error: result)

      unless status.success?
        raise BackupCorruptionError.new("Failed to extract metadata from backup: tar command failed (exit code: #{status.exit_code})")
      end

      metadata_content = result.to_s
      if metadata_content.empty?
        raise BackupCorruptionError.new("No metadata.json found in backup")
      end

      metadata_content
    end

    # Gets a list of all files in the backup tar archive using system tar command
    private def self.get_backup_file_list(backup_path : String) : Array(String)
      result = IO::Memory.new
      status = Process.run("tar", {"-tf", backup_path}, output: result, error: result)

      unless status.success?
        raise BackupCorruptionError.new("Failed to list backup contents: tar command failed")
      end

      file_list = result.to_s.split('\n').map(&.strip).reject(&.empty?)
      file_list
    end
  end
end

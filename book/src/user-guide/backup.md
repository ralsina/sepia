# Backup and Restore

Sepia provides comprehensive backup functionality that allows you to create tar archives of object trees, inspect backup contents, and verify backup integrity.

## Overview

Sepia's backup system enables you to:

- Create complete backups of object trees with all relationships
- Inspect backup contents without restoring
- Verify backup integrity and structure
- Preserve symlinks and object relationships
- Generate human-readable metadata

## Basic Usage

### Creating Backups

#### Backup Multiple Objects

```crystal
# Backup a list of root objects
root_objects = [document1, project1, user_profile]
backup_path = Sepia::Backup.create(root_objects, "project_backup.tar")
puts "Backup created: #{backup_path}"
```

#### Backup from Storage

```crystal
# Backup specific objects from storage
objects = [
  Sepia::Storage.get(Document, "doc1"),
  Sepia::Storage.get(Project, "proj1")
]
backup_path = Sepia::Storage.backup(objects, "selected_backup.tar")

# Backup a single object
backup_path = Sepia::Storage.backup(document, "single_doc_backup.tar")

# Backup all objects in storage
backup_path = Sepia::Storage.backup_all("complete_backup.tar")
```

#### Backup from Individual Objects

```crystal
# Simple backup to specific path
document.backup_to("doc_backup.tar")

# Backup with auto-generated filename (includes timestamp)
backup_path = document.create_backup()  # e.g., "document_abc123_20251125.tar"

# Backup to custom directory
document.backup_to("backups/docs/doc_backup.tar")
```

### Inspecting Backups

#### List Backup Contents

```crystal
manifest = Sepia::Backup.list_contents("project_backup.tar")

puts "Backup created at: #{manifest.created_at}"
puts "Version: #{manifest.version}"
puts "Root objects: #{manifest.root_objects.size}"

manifest.root_objects.each do |root_obj|
  puts "  - #{root_obj.class_name}/#{root_obj.object_id} (#{root_obj.object_type})"
end

puts "All objects by class:"
manifest.all_objects.each do |class_name, objects|
  puts "  - #{class_name}: #{objects.size} objects"
end
```

#### Get Backup Metadata

```crystal
metadata = Sepia::Backup.get_metadata("project_backup.tar")
# Returns the same manifest as list_contents()
```

#### Verify Backup Integrity

```crystal
result = Sepia::Backup.verify("project_backup.tar")

puts "Backup is #{result.valid ? "valid" : "invalid"}"
puts "Total objects: #{result.statistics.total_objects}"
puts "Serializable objects: #{result.statistics.serializable_objects}"
puts "Container objects: #{result.statistics.container_objects}"
puts "Object classes: #{result.statistics.classes.size}"

if result.errors.empty?
  puts "No verification errors"
else
  puts "Verification errors:"
  result.errors.each { |error| puts "  - #{error}" }
end
```

## Backup Archive Structure

Sepia backups are standard tar archives with this structure:

```
backup.sepia.tar
├── metadata.json     # Backup manifest with object information
├── README           # Human-readable backup information
└── objects/         # All objects organized by class and ID
    ├── ClassName/object_id        # Serializable objects (files)
    └── ClassName/object_id/       # Container objects (directories)
        ├── data.json
        └── references/
```

### metadata.json Format

```json
{
  "version": "1.0",
  "created_at": "2025-11-25T17:30:00Z",
  "root_objects": [
    {
      "class_name": "Document",
      "object_id": "doc-123",
      "relative_path": "objects/Document/doc-123",
      "object_type": "Serializable"
    }
  ],
  "all_objects": {
    "Document": [
      {
        "class_name": "Document",
        "object_id": "doc-123",
        "relative_path": "objects/Document/doc-123",
        "object_type": "Serializable"
      }
    ],
    "Project": [...]
  }
}
```

## Configuration

Sepia supports simple configuration for backup creation:

```crystal
config = Sepia::Backup::Configuration.new

# Configure symlink handling
config.follow_symlinks = false  # Default: preserves symlinks as-is

# Create backup with configuration
backup_path = Sepia::Backup.create(root_objects, "backup.tar", config)
```

### Configuration Presets

```crystal
# Fast backup (no compression, minimal verification)
fast_config = Sepia::Backup::Configuration.fast

# Minimal backup (basic functionality only)
minimal_config = Sepia::Backup::Configuration.minimal

# Archive backup (maximum preservation)
archive_config = Sepia::Backup::Configuration.archive

backup_path = Sepia::Backup.create(root_objects, "archive.tar", archive_config)
```

## Use Cases

### Application Backup

```crystal
class BackupService
  def backup_user_data(user : User)
    # Backup all objects related to a user
    root_objects = [user] + user.documents + user.projects

    timestamp = Time.utc.to_s("%Y%m%d_%H%M%S")
    backup_path = "backups/user_#{user.id}_#{timestamp}.tar"

    backup_path = Sepia::Backup.create(root_objects, backup_path)

    # Verify backup was successful
    result = Sepia::Backup.verify(backup_path)
    unless result.valid
      raise "Backup verification failed"
    end

    backup_path
  end
end
```

### Project Export

```crystal
def export_project(project : Project)
  # Create backup of entire project tree
  root_objects = [project] + find_all_related_objects(project)

  export_path = "exports/#{project.name}_export.tar"
  backup_path = Sepia::Backup.create(root_objects, export_path)

  puts "Project exported to: #{backup_path}"

  # Show what's in the export
  manifest = Sepia::Backup.list_contents(backup_path)
  puts "Export contains #{manifest.all_objects.values.map(&.size).sum} objects"
end
```

### Data Migration

```crystal
def migrate_data(source_storage, target_storage)
  # 1. Backup current data
  all_objects = source_storage.list_all_objects
  backup_path = Sepia::Backup.create(all_objects, "migration_backup.tar")

  # 2. Transfer data to new storage
  all_objects.each do |obj|
    target_storage.save(obj)
  end

  # 3. Verify migration
  result = Sepia::Backup.verify(backup_path)
  puts "Migration completed, backup verified: #{result.valid ? "✓" : "✗"}"
end
```

### Scheduled Backups

```crystal
class ScheduledBackup
  def initialize(@backup_dir : String)
    Dir.mkdir_p(@backup_dir)
  end

  def daily_backup
    timestamp = Time.utc.to_s("%Y%m%d")
    backup_path = File.join(@backup_dir, "daily_#{timestamp}.tar")

    # Backup all objects
    backup_path = Sepia::Storage.backup_all(backup_path)

    # Keep only last 30 daily backups
    cleanup_old_backups("daily_", 30)

    backup_path
  end

  private def cleanup_old_backups(prefix : String, keep_count : Int32)
    backups = Dir.glob(File.join(@backup_dir, "#{prefix}*.tar"))
      .sort_by { |f| File.basename(f) }
      .reverse

    if backups.size > keep_count
      backups[keep_count..-1].each do |old_backup|
        File.delete(old_backup)
        puts "Deleted old backup: #{old_backup}"
      end
    end
  end
end
```

## Error Handling

Sepia provides specific exception types for backup operations:

```crystal
begin
  backup_path = Sepia::Backup.create(root_objects, "backup.tar")
rescue Sepia::BackendNotSupportedError
  puts "Backup not supported with current storage backend"
rescue Sepia::BackupCreationError
  puts "Failed to create backup: check permissions and disk space"
rescue Sepia::BackupCorruptionError
  puts "Backup file is corrupted or invalid"
rescue ex : Exception
  puts "Unexpected error: #{ex.message}"
end
```

## Performance Considerations

### Large Backups

For large object trees:

- Consider filtering objects to exclude unnecessary data
- Use streaming for very large backups
- Monitor disk space availability
- Consider compression for network transfers

### Backup Frequency

```crystal
# Smart backup based on changes since last backup
class SmartBackup
  def backup_if_changed(last_backup_time : Time)
    modified_objects = find_objects_modified_since(last_backup_time)

    if modified_objects.empty?
      puts "No changes since last backup"
      return nil
    end

    backup_path = create_backup(modified_objects)
    puts "Backup created with #{modified_objects.size} modified objects"
    backup_path
  end

  private def find_objects_modified_since(time : Time)
    # Implementation depends on your storage backend
    # Could use file modification times or event logs
  end
end
```

## Integration with External Tools

### rsync Integration

```crystal
backup_path = Sepia::Storage.backup_all("local_backup.tar")

# Sync to remote server
system("rsync", "-av", "local_backup.tar", "user@server:/backups/")
```

### Cloud Storage

```crystal
# After creating backup, upload to cloud service
backup_path = create_backup(objects)

# Upload using system tools
if File.exists?(backup_path)
  system("aws", "s3", "cp", backup_path, "s3://my-bucket/backups/")
  system("rclone", "copy", backup_path, "remote:backups/")
end
```

## Best Practices

1. **Always verify** backups after creation
2. **Regular testing** of restore procedures
3. **Monitor disk space** for backup directories
4. **Use meaningful filenames** with timestamps
5. **Document backup procedures** for your team
6. **Test backup restoration** in staging environments
7. **Consider encryption** for sensitive data backups
8. **Implement cleanup** strategies for old backups

## Restore Strategy

While Sepia focuses on backup creation (restore is application-specific), here's a general pattern:

```crystal
class RestoreService
  def restore_from_backup(backup_path : String, target_storage)
    # 1. Inspect backup contents
    manifest = Sepia::Backup.list_contents(backup_path)

    # 2. Extract backup (application-specific logic)
    extract_and_process_backup(backup_path, target_storage, manifest)

    # 3. Rebuild relationships
    rebuild_object_relationships(manifest, target_storage)
  end

  # Implementation depends on your specific application requirements
  private def extract_and_process_backup(backup_path, storage, manifest)
    # Extract tar archive and process files according to your needs
  end
end
```
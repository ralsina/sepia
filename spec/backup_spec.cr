require "./spec_helper"
require "file_utils"

# Test classes for backup specs
class BackupTestDocument < Sepia::Object
  include Sepia::Serializable

  property title : String
  property content : String

  def initialize(@title = "", @content = "")
  end

  def to_sepia : String
    "#{@title}|#{@content}"
  end

  def self.from_sepia(sepia_string : String) : self
    parts = sepia_string.split('|', 2)
    title = parts[0]? || ""
    content = parts[1]? || ""
    new(title, content)
  end
end

class BackupTestProject < Sepia::Object
  include Sepia::Container

  property name : String
  property documents : Array(BackupTestDocument)
  property subprojects : Hash(String, BackupTestProject)
  property metadata : Hash(String, String)

  def initialize(@name = "")
    @documents = [] of BackupTestDocument
    @subprojects = Hash(String, BackupTestProject).new
    @metadata = Hash(String, String).new
  end
end

class BackupTestComplexContainer < Sepia::Object
  include Sepia::Container

  property name : String
  property nested_containers : Array(BackupTestComplexContainer)
  property document : BackupTestDocument?
  property tags : Set(String)

  def initialize(@name = "")
    @nested_containers = [] of BackupTestComplexContainer
    @tags = Set(String).new
  end
end

describe Sepia::Backup do
  describe "backup creation" do
    before_each do
      # Setup isolated storage for each test
      storage_dir = File.join(Dir.tempdir, "sepia_backup_test_#{Time.utc.to_unix_ms}")
      Dir.mkdir_p(storage_dir)
      Sepia::Storage.backend = Sepia::FileStorage.new(storage_dir)
    end

    after_each do
      # Cleanup - find and remove all test directories
      Dir.glob("#{Dir.tempdir}/sepia_backup_test_*").each do |test_dir|
        FileUtils.rm_rf(test_dir) if Dir.exists?(test_dir)
      end
    end

    describe "simple object backup" do
      it "backs up a single serializable object" do
        doc = BackupTestDocument.new("Test Document", "Test content")
        doc.sepia_id = "test-doc"
        doc.save

        backup_path = File.join(Dir.tempdir, "single_object_backup.tar")
        Sepia::Backup.create([doc], backup_path)

        backup_path.should be_a(String)
        File.exists?(backup_path).should be_true
        File.size(backup_path).should be > 0

        # Verify backup contents
        tar_output = `tar -tf #{backup_path}`
        tar_output.should contain("objects/BackupTestDocument/test-doc")
        tar_output.should contain("metadata.json")
        tar_output.should contain("README")
      end

      it "backs up a single container object" do
        project = BackupTestProject.new("Test Project")
        project.sepia_id = "test-project"
        project.save

        backup_path = File.join(Dir.tempdir, "single_container_backup.tar")
        Sepia::Backup.create([project], backup_path)

        backup_path.should be_a(String)
        File.exists?(backup_path).should be_true
        File.size(backup_path).should be > 0

        # Verify backup contents
        tar_output = `tar -tf #{backup_path}`
        tar_output.should contain("objects/BackupTestProject/test-project/data.json")
        tar_output.should contain("metadata.json")
        tar_output.should contain("README")
      end
    end

    describe "object tree backup" do
      it "backs up object with references" do
        # Create documents
        doc1 = BackupTestDocument.new("Doc 1", "Content 1")
        doc1.sepia_id = "doc1"
        doc1.save

        doc2 = BackupTestDocument.new("Doc 2", "Content 2")
        doc2.sepia_id = "doc2"
        doc2.save

        # Create project with references to documents
        project = BackupTestProject.new("Test Project")
        project.sepia_id = "project1"
        project.documents << doc1
        project.documents << doc2
        project.save

        backup_path = File.join(Dir.tempdir, "object_tree_backup.tar")
        Sepia::Backup.create([project], backup_path)

        File.exists?(backup_path).should be_true
        File.size(backup_path).should be > 0

        # Verify all objects are included
        tar_output = `tar -tf #{backup_path}`
        tar_output.should contain("objects/BackupTestProject/project1/data.json")
        tar_output.should contain("objects/BackupTestProject/project1/documents/0000_doc1")
        tar_output.should contain("objects/BackupTestProject/project1/documents/0001_doc2")
        tar_output.should contain("objects/BackupTestDocument/doc1")
        tar_output.should contain("objects/BackupTestDocument/doc2")
      end

      it "backs up nested container structures" do
        # Create nested containers
        inner_doc = BackupTestDocument.new("Inner Doc", "Inner content")
        inner_doc.sepia_id = "inner-doc"
        inner_doc.save

        inner_container = BackupTestComplexContainer.new("Inner Container")
        inner_container.sepia_id = "inner-container"
        inner_container.document = inner_doc
        inner_container.save

        outer_container = BackupTestComplexContainer.new("Outer Container")
        outer_container.sepia_id = "outer-container"
        outer_container.nested_containers << inner_container
        outer_container.save

        backup_path = File.join(Dir.tempdir, "nested_backup.tar")
        Sepia::Backup.create([outer_container], backup_path)

        File.exists?(backup_path).should be_true

        # Verify nested structure is preserved
        tar_output = `tar -tf #{backup_path}`
        tar_output.should contain("objects/BackupTestComplexContainer/outer-container/data.json")
        tar_output.should contain("objects/BackupTestComplexContainer/inner-container/data.json")
        tar_output.should contain("objects/BackupTestDocument/inner-doc")
      end

      it "backs up multiple root objects" do
        doc1 = BackupTestDocument.new("Doc 1", "Content 1")
        doc1.sepia_id = "doc1"
        doc1.save

        doc2 = BackupTestDocument.new("Doc 2", "Content 2")
        doc2.sepia_id = "doc2"
        doc2.save

        project = BackupTestProject.new("Project")
        project.sepia_id = "project"
        project.documents << doc1
        project.save

        # Backup with multiple root objects
        backup_path = File.join(Dir.tempdir, "multi_root_backup.tar")
        Sepia::Backup.create([doc2, project], backup_path)

        File.exists?(backup_path).should be_true

        # Check metadata contains all root objects
        metadata_output = `tar -xf #{backup_path} metadata.json -O`
        metadata_output.should contain("doc2")
        metadata_output.should contain("project")
        metadata_output.should contain("BackupTestDocument")
        metadata_output.should contain("BackupTestProject")
      end
    end

    describe "edge cases" do
      it "handles empty object tree" do
        # Create an empty container
        empty_project = BackupTestProject.new("Empty Project")
        empty_project.sepia_id = "empty"
        empty_project.save

        backup_path = File.join(Dir.tempdir, "empty_backup.tar")
        Sepia::Backup.create([empty_project], backup_path)

        File.exists?(backup_path).should be_true
        File.size(backup_path).should be > 0

        tar_output = `tar -tf #{backup_path}`
        tar_output.should contain("objects/BackupTestProject/empty/data.json")
      end

      it "handles container with only primitive data" do
        project = BackupTestProject.new("Primitive Project")
        project.sepia_id = "primitive"
        project.metadata["version"] = "1.0"
        project.metadata["author"] = "test"
        project.save

        backup_path = File.join(Dir.tempdir, "primitive_backup.tar")
        Sepia::Backup.create([project], backup_path)

        File.exists?(backup_path).should be_true
        tar_output = `tar -tf #{backup_path}`
        tar_output.should contain("objects/BackupTestProject/primitive/data.json")
      end

      it "handles shared references (object referenced by multiple containers)" do
        shared_doc = BackupTestDocument.new("Shared Document", "Shared content")
        shared_doc.sepia_id = "shared-doc"
        shared_doc.save

        project1 = BackupTestProject.new("Project 1")
        project1.sepia_id = "project1"
        project1.documents << shared_doc
        project1.save

        project2 = BackupTestProject.new("Project 2")
        project2.sepia_id = "project2"
        project2.documents << shared_doc
        project2.save

        backup_path = File.join(Dir.tempdir, "shared_refs_backup.tar")
        Sepia::Backup.create([project1, project2], backup_path)

        File.exists?(backup_path).should be_true

        # Verify the shared document structure
        tar_output = `tar -tf #{backup_path}`

        # Check that the canonical file exists
        tar_output.should contain("objects/BackupTestDocument/shared-doc")

        # Check that multiple references exist
        tar_output.should contain("objects/BackupTestProject/project1/documents/0000_shared-doc")
        tar_output.should contain("objects/BackupTestProject/project2/documents/0000_shared-doc")

        # Count actual files vs symlinks
        all_lines = tar_output.split('\n')
        canonical_file = all_lines.select { |line| line == "objects/BackupTestDocument/shared-doc" }
        symlink_files = all_lines.select { |line| line.includes?("shared-doc") && line != "objects/BackupTestDocument/shared-doc" }

        canonical_file.size.should eq(1) # Only one actual file
        symlink_files.size.should eq(2)  # Two symlinks to it
      end

      it "handles special characters in object content" do
        special_doc = BackupTestDocument.new("Special \"Chars\"", "Content with\nnewlines and\ttabs and\0nulls")
        special_doc.sepia_id = "special-chars"
        special_doc.save

        backup_path = File.join(Dir.tempdir, "special_chars_backup.tar")
        Sepia::Backup.create([special_doc], backup_path)

        File.exists?(backup_path).should be_true
        File.size(backup_path).should be > 0
      end

      it "handles very long object IDs" do
        long_id = "a" * 200
        long_doc = BackupTestDocument.new("Long ID Document", "Content")
        long_doc.sepia_id = long_id
        long_doc.save

        backup_path = File.join(Dir.tempdir, "long_id_backup.tar")
        Sepia::Backup.create([long_doc], backup_path)

        File.exists?(backup_path).should be_true
        tar_output = `tar -tf #{backup_path}`
        tar_output.should contain(long_id)
      end
    end

    describe "metadata generation" do
      it "generates correct metadata structure" do
        doc = BackupTestDocument.new("Test", "Content")
        doc.sepia_id = "test-doc"
        doc.save

        backup_path = File.join(Dir.tempdir, "metadata_backup.tar")
        Sepia::Backup.create([doc], backup_path)

        # Extract and parse metadata
        metadata_json = `tar -xf #{backup_path} metadata.json -O`
        metadata = JSON.parse(metadata_json)

        metadata["version"].should eq("1.0")
        metadata["created_at"].should_not be_nil
        metadata["root_objects"].as_a.size.should eq(1)
        metadata["all_objects"].should_not be_nil
      end

      it "includes README file" do
        doc = BackupTestDocument.new("Test", "Content")
        doc.sepia_id = "test-doc"
        doc.save

        backup_path = File.join(Dir.tempdir, "readme_backup.tar")
        Sepia::Backup.create([doc], backup_path)

        # Check README exists
        tar_output = `tar -tf #{backup_path}`
        tar_output.should contain("README")

        # Extract README content
        readme_content = `tar -xf #{backup_path} README -O`
        readme_content.should contain("Sepia Backup Archive")
        readme_content.should contain("metadata.json")
        readme_content.should contain("objects/")
      end
    end

    describe "error handling" do
      it "raises error with InMemoryStorage" do
        # Switch to InMemoryStorage
        Sepia::Storage.backend = Sepia::InMemoryStorage.new

        doc = BackupTestDocument.new("Test", "Content")
        doc.sepia_id = "test-doc"
        doc.save

        backup_path = File.join(Dir.tempdir, "memory_backup.tar")

        expect_raises(Exception, "Backup not supported with InMemoryStorage") do
          Sepia::Backup.create([doc], backup_path)
        end
      end

      it "handles non-existent objects gracefully" do
        # Create a document but don't save it
        doc = BackupTestDocument.new("Missing", "Not saved")
        doc.sepia_id = "missing-doc"
        # Note: not calling doc.save()

        backup_path = File.join(Dir.tempdir, "missing_backup.tar")

        # Should still create backup but show warning about missing object
        Sepia::Backup.create([doc], backup_path)
        File.exists?(backup_path).should be_true
      end
    end

    describe "performance and scale" do
      it "handles medium-sized object trees efficiently" do
        start_time = Time.monotonic

        # Create a moderately sized tree
        documents = [] of BackupTestDocument
        100.times do |i|
          doc = BackupTestDocument.new("Doc #{i}", "Content #{i}")
          doc.sepia_id = "doc-#{i}"
          doc.save
          documents << doc
        end

        project = BackupTestProject.new("Big Project")
        project.sepia_id = "big-project"
        project.documents.concat(documents)
        project.save

        backup_path = File.join(Dir.tempdir, "scale_backup.tar")
        Sepia::Backup.create([project], backup_path)

        end_time = Time.monotonic
        duration = end_time - start_time

        File.exists?(backup_path).should be_true
        duration.should be < 5.seconds # Should complete within reasonable time
      end
    end
  end
end

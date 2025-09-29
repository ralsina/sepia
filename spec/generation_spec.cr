require "./spec_helper"
require "json"
require "file_utils"

class GenerationTestUser < Sepia::Object
  include Sepia::Serializable

  property name : String
  property email : String?

  def initialize(@name : String, @email : String? = nil)
  end

  def to_sepia : String
    data = {} of String => String | Nil
    data["name"] = @name
    data["email"] = @email
    data.to_json
  end

  def self.from_sepia(sepia_string : String) : self
    data = JSON.parse(sepia_string)
    new(
      data["name"].as_s,
      data["email"]?.try(&.as_s?)
    )
  end
end

class GenerationTestNote < Sepia::Object
  include Sepia::Serializable

  property title : String
  property content : String
  property tags : Array(String)

  def initialize(@title : String, @content : String, @tags : Array(String) = [] of String)
  end

  def to_sepia : String
    {
      "title"   => @title,
      "content" => @content,
      "tags"    => @tags,
    }.to_json
  end

  def self.from_sepia(sepia_string : String) : self
    data = JSON.parse(sepia_string)
    new(
      data["title"].as_s,
      data["content"].as_s,
      data["tags"].as_a.map(&.as_s)
    )
  end
end

describe "Generation tracking" do
  it "parses generation from ID without suffix" do
    user = GenerationTestUser.new("John")
    user.generation.should eq 0
    user.base_id.should eq user.sepia_id
  end

  it "parses generation from ID with suffix" do
    user = GenerationTestUser.new("John")
    user.sepia_id = "note-123.3"
    user.generation.should eq 3
    user.base_id.should eq "note-123"
  end

  it "handles complex IDs with dots" do
    user = GenerationTestUser.new("John")
    user.sepia_id = "note.title.v2.5"
    user.generation.should eq 5
    user.base_id.should eq "note.title.v2"
  end

  it "checks for stale data" do
    # Clean up any existing files first
    backend = Sepia::Storage.backend
    if backend.is_a?(Sepia::FileStorage)
      test_dir = File.join(backend.path, "GenerationTestUser")
      FileUtils.rm_rf(test_dir) if Dir.exists?(test_dir)
    end

    user1 = GenerationTestUser.new("John")
    user1.sepia_id = "user-123.2"
    user1.save

    # Check if next generation exists (it shouldn't)
    user1.stale?(2).should be_false

    # Create next generation
    user2 = GenerationTestUser.new("John Doe")
    user2.sepia_id = "user-123.3"
    user2.save

    # Now user1 should be stale
    user1.stale?(2).should be_true
  end

  it "creates new generation with save_with_generation" do
    user = GenerationTestUser.new("Original")
    user.sepia_id = "user-gen-test.0"
    user.save

    # Create new version
    v2 = user.save_with_generation
    v2.sepia_id.should eq "user-gen-test.1"
    v2.generation.should eq 1
    v2.name.should eq "Original"

    # Create another version
    v3 = v2.save_with_generation
    v3.sepia_id.should eq "user-gen-test.2"
    v3.generation.should eq 2
  end

  it "finds latest version" do
    # Create multiple versions
    base_id = "latest-test"
    user1 = GenerationTestUser.new("v1")
    user1.sepia_id = "#{base_id}.0"
    user1.save

    user2 = GenerationTestUser.new("v2")
    user2.sepia_id = "#{base_id}.1"
    user2.save

    user3 = GenerationTestUser.new("v3")
    user3.sepia_id = "#{base_id}.2"
    user3.save

    latest = GenerationTestUser.latest(base_id)
    latest.should_not be_nil
    if latest
      latest.sepia_id.should eq "#{base_id}.2"
      latest.name.should eq "v3"
    end
  end

  it "finds all versions" do
    base_id = "versions-test"
    versions = [] of GenerationTestUser

    # Create multiple versions
    3.times do |i|
      user = GenerationTestUser.new("Version #{i}")
      user.sepia_id = "#{base_id}.#{i}"
      user.save
      versions << user
    end

    # Get all versions
    all_versions = GenerationTestUser.versions(base_id)
    all_versions.size.should eq 3
    all_versions[0].generation.should eq 0
    all_versions[1].generation.should eq 1
    all_versions[2].generation.should eq 2
  end

  it "handles objects without generation suffix" do
    # Legacy object without generation
    user = GenerationTestUser.new("Legacy")
    user.sepia_id = "legacy-user"
    user.save

    # Should still work
    found = GenerationTestUser.latest("legacy-user")
    found.should_not be_nil
    if found
      found.sepia_id.should eq "legacy-user"
      found.generation.should eq 0
    end
  end

  it "checks if object exists" do
    user = GenerationTestUser.new("Exists Test")
    user.sepia_id = "exists-test.1"
    user.save

    GenerationTestUser.exists?("exists-test.1").should be_true
    GenerationTestUser.exists?("exists-test.2").should be_false
    GenerationTestUser.exists?("nonexistent").should be_false
  end

  it "copies all attributes when creating new generation" do
    note = GenerationTestNote.new(
      "Original Title",
      "Original Content",
      ["tag1", "tag2"]
    )
    note.sepia_id = "note-copy-test.0"
    note.save

    v2 = note.save_with_generation
    v2.title.should eq "Original Title"
    v2.content.should eq "Original Content"
    v2.tags.should eq ["tag1", "tag2"]
    v2.sepia_id.should eq "note-copy-test.1"
  end
end

describe "Generation tracking with InMemoryStorage" do
  before_all do
    # Switch to in-memory storage for these tests
    Sepia::Storage.configure(:memory)
  end

  after_all do
    # Switch back to filesystem storage
    Sepia::Storage.configure(:filesystem)
  end

  it "works with in-memory storage" do
    user = GenerationTestUser.new("Memory User")
    user.sepia_id = "memory-test.0"
    user.save

    v2 = user.save_with_generation
    v2.generation.should eq 1

    latest = GenerationTestUser.latest("memory-test")
    latest.should_not be_nil
    if latest
      latest.generation.should eq 1
    end
  end
end

describe "Atomic writes" do
  it "creates .tmp file during write" do
    user = GenerationTestUser.new("Atomic Test")
    storage_path = Sepia::Storage::INSTANCE.path
    user_dir = File.join(storage_path, "GenerationTestUser")
    FileUtils.mkdir_p(user_dir) unless Dir.exists?(user_dir)

    user.save

    # Check that no .tmp file remains
    tmp_files = Dir.children(user_dir).select(&.ends_with?(".tmp"))
    tmp_files.should be_empty
  end
end

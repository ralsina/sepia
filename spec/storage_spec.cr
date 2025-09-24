require "./spec_helper"
require "file_utils"

# A simple Container for testing.
# It includes Serializable to get the .delete method.
class DeletableContainer < Sepia::Object
  include Sepia::Container

  # These are needed to satisfy the Serializable contract,
  # but won't be called if it's treated as a Container.
  def to_sepia
    ""
  end

  def self.from_sepia(s)
    new
  end
end

describe Sepia::Storage do
  # Use a temporary directory for all storage tests
  before_each do
    Sepia::Storage.configure(:filesystem, {"path" => "sepia-storage-spec"})
  end

  after_each do
    FileUtils.rm_rf("sepia-storage-spec") if Dir.exists?("sepia-storage-spec")
  end

  it "roundtrips an object to the storage" do
    # No need to create a new storage instance, use the singleton
    storage = Sepia::Storage::INSTANCE
    user = TestUser.new("Roundtrip User")
    storage.save(user)
    loaded = storage.load(TestUser, user.sepia_id)
    loaded.should be_a(TestUser)
    loaded.name.should eq("Roundtrip User")
  end

  it "has a singleton instance" do
    storage = Sepia::Storage::INSTANCE
    # The path is already set in before_each
    storage.path.should eq "sepia-storage-spec"
    storage.should be_a(Sepia::Storage)
  end

  describe "#delete for Serializable" do
    it "deletes a serializable object's file" do
      obj = TestUser.new("to be deleted")
      obj.sepia_id = "test_serializable"
      obj.save

      file_path = File.join("sepia-storage-spec", "TestUser", "test_serializable")
      File.exists?(file_path).should be_true

      obj.delete

      File.exists?(file_path).should be_false
    end

    it "does not raise an error if the serializable object to delete is not found" do
      obj = TestUser.new
      obj.sepia_id = "non_existent_serializable"
      obj.delete
    end
  end

  describe "#delete for Container" do
    it "deletes a container object's directory" do
      container = DeletableContainer.new
      container.sepia_id = "test_container"
      container.save

      dir_path = File.join("sepia-storage-spec", "DeletableContainer", "test_container")
      Dir.exists?(dir_path).should be_true

      container.delete

      Dir.exists?(dir_path).should be_false
    end

    it "does not raise an error if the container object to delete is not found" do
      container = DeletableContainer.new
      container.sepia_id = "non_existent_container"
      container.delete
    end
  end
end

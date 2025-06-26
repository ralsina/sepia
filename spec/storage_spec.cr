require "./spec_helper"
require "file_utils"

describe Sepia::Storage do
  path = File.join(Dir.tempdir, "sepia_storage_test")
  before_each do
    FileUtils.rm_rf(path) if File.exists?(path)
    FileUtils.mkdir_p(path)
  end
  after_each do
    FileUtils.rm_rf(path) if File.exists?(path)
  end

  it "roundtrips an object to the storage" do
    storage = Sepia::Storage.new
    storage.path = path
    user = TestUser.new
    storage.save(user)
    loaded = storage.load(TestUser, user.sepia_id)
    loaded.should be_a(TestUser)
  end

  it "has a singleton instance" do
    storage = Sepia::Storage::INSTANCE
    storage.path="foo"
    storage.should be_a(Sepia::Storage)
    storage.path.should eq "foo"
  end
end

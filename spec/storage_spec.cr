require "./spec_helper"
require "file_utils"
require "./sepia_spec"

describe Sepia::Storage do
  it "roundtrips an object to the storage" do
    storage = Sepia::Storage.new
    storage.path = PATH
    user = TestUser.new
    storage.save(user)
    loaded = storage.load(TestUser, user.sepia_id)
    loaded.should be_a(TestUser)
  end

  it "has a singleton instance" do
    storage = Sepia::Storage::INSTANCE
    storage.path = "foo"
    storage.should be_a(Sepia::Storage)
    storage.path.should eq "foo"
  end
end

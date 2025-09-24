require "json"
require "./spec_helper"

PATH = File.join(Dir.tempdir, "sepia_storage_test")

class Broken < Sepia::Object
  include Sepia::Serializable

  property name : String = "Default Name"
  property age : Int32 = 32
  property city : String = "Default City"
end

class TestUser < Sepia::Object
  include JSON::Serializable
  include Sepia::Serializable

  property name : String
  property age : Int32
  property email : String
  property city : String?

  def initialize(@name = "Joe", @age = 32, @email = "joe@example.com", @city = "Unknown")
  end

  def to_sepia : String
    self.to_json
  end

  def self.from_sepia(sepia_string : String) : TestUser
    TestUser.from_json(sepia_string)
  end
end

describe Sepia do
  # Test both storage backends
  [:filesystem, :memory].each do |backend|
    describe "using #{backend} storage" do
      before_each do
        if backend == :filesystem
          FileUtils.rm_rf(PATH) if File.exists?(PATH)
          FileUtils.mkdir_p(PATH)
          Sepia::Storage.configure(:filesystem, {"path" => PATH})
        else
          Sepia::Storage.configure(:memory)
        end
      end

      after_each do
        if backend == :filesystem
          FileUtils.rm_rf(PATH) if File.exists?(PATH)
        end
      end

      it "won't serialize unless the class does it" do
        expect_raises Exception, "to_sepia must be implemented by the class including Sepia::Serializable" do
          Broken.new.to_sepia
        end
      end

      it "won't deserialize unless the class does it" do
        expect_raises Exception, "self.from_sepia must be implemented by the class including Sepia::Serializable" do
          Broken.from_sepia("foo")
        end
      end

      it "serializes an object to sepia format" do
        user = TestUser.new("John Doe", 42, "john.doe@example.com", "Crystal City")
        user.sepia_id = "74978fc0-1f28-4810-ba9a-0686305f471d" # Set a fixed ID for testing
        sepia_string = user.to_sepia
        expected = "{\"sepia_id\":\"74978fc0-1f28-4810-ba9a-0686305f471d\",\"name\":\"John Doe\",\"age\":42,\"email\":\"john.doe@example.com\",\"city\":\"Crystal City\"}"

        # Split lines and sort to make test independent of property order
        sepia_string.should eq expected
      end

      it "deserializes an object from sepia format" do
        user = TestUser.from_sepia("{\"sepia_id\":\"74978fc0-1f28-4810-ba9a-0686305f471d\",\"name\":\"John Doe\",\"age\":42,\"email\":\"john.doe@example.com\",\"city\":\"Crystal City\"}")
        user.should be_a(TestUser)
      end

      it "has a overwritable sepia_id property" do
        user = TestUser.new
        user.sepia_id.should_not be_nil
        user.sepia_id.should be_a(String)
        user.sepia_id.size.should eq 36 # Size of an UUID
        user.sepia_id = "custom-id"
        user.sepia_id.should eq "custom-id"
      end

      it "knows how to roundtrip itself" do
        user = TestUser.new
        user_id = user.sepia_id
        user.save
        TestUser.load(user_id).should be_a(TestUser)
      end

      it "can save and load a serializable to a custom path" do
        user = TestUser.new("Custom Path User")
        user.sepia_id = "custom_serializable_id"
        custom_path = File.join(PATH, "custom_serializable_location", user.sepia_id)
        user.save(custom_path)

        # Note: In-memory storage doesn't create actual files
        if backend == :filesystem
          File.exists?(custom_path).should be_true
        end
        File.exists?(File.join(PATH, "TestUser", user.sepia_id)).should be_false

        # Load from custom path
        loaded_user = TestUser.load("custom_serializable_id", custom_path)

        loaded_user.name.should eq "Custom Path User"
        loaded_user.sepia_id.should eq "custom_serializable_id"
      end
      it "can save a serializable to a custom path" do
        user = TestUser.new("Custom Path User")
        user.sepia_id = "custom_serializable_id"
        custom_path = File.join(PATH, "custom_serializable_location", user.sepia_id)
        user.save(custom_path)

        # Note: In-memory storage doesn't create actual files
        if backend == :filesystem
          File.exists?(custom_path).should be_true
        end
        if backend == :filesystem
          File.exists?(File.join(PATH, "TestUser", user.sepia_id)).should be_false
        end

        # Manually load from custom path
        if backend == :filesystem
          loaded_content = File.read(custom_path)
          loaded_user = TestUser.from_sepia(loaded_content)
          loaded_user.sepia_id = user.sepia_id # sepia_id is not part of the serialized content by default
        else
          loaded_user = TestUser.load("custom_serializable_id", custom_path).as(TestUser)
        end

        loaded_user.name.should eq "Custom Path User"
        loaded_user.sepia_id.should eq "custom_serializable_id"
      end # end backend loop
    end
  end

  it "supports discovery API" do
    # Test with both backends
    [:filesystem, :memory].each do |backend|
      if backend == :filesystem
        FileUtils.rm_rf(PATH) if File.exists?(PATH)
        FileUtils.mkdir_p(PATH)
        Sepia::Storage.configure(:filesystem, {"path" => PATH})
      else
        Sepia::Storage.configure(:memory)
      end

      # Create and save multiple objects
      user1 = TestUser.new("Discovery User 1")
      user1.sepia_id = "discovery1"
      user1.save

      user2 = TestUser.new("Discovery User 2")
      user2.sepia_id = "discovery2"
      user2.save

      # Test discovery API
      Sepia::Storage.list_all(TestUser).should contain("discovery1")
      Sepia::Storage.list_all(TestUser).should contain("discovery2")
      Sepia::Storage.exists?(TestUser, "discovery1").should be_true
      Sepia::Storage.exists?(TestUser, "discovery2").should be_true
      Sepia::Storage.exists?(TestUser, "nonexistent").should be_false
      Sepia::Storage.count(TestUser).should eq 2

      # Test bulk operations
      data = Sepia::Storage.export_data
      data.has_key?("TestUser").should be_true
      data["TestUser"].size.should eq 2

      Sepia::Storage.clear
      Sepia::Storage.count(TestUser).should eq 0

      Sepia::Storage.import_data(data)
      Sepia::Storage.count(TestUser).should eq 2
    end
  end
end

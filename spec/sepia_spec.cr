require "./spec_helper"

class Broken
  include Sepia::Serializable

  property name : String = "Default Name"
  property age : Int32 = 32
  property city : String = "Default City"
end

class TestUser
  include Sepia::Serializable

  property name : String
  property age : Int32
  property email : String
  property city : String?

  def initialize(@name="Joe", @age=32, @email="joe@example.com", @city = "Unknown")
  end

  def to_sepia : String
    builder = Hash(String, String).new
    builder["name"] = @name
    builder["age"] = @age.to_s
    builder["user_email"] = @email
    builder["city"] = @city || "Unknown"
    builder.to_s
  end

  def self.from_sepia(sepia_string : String) : TestUser
    TestUser.new
  end
end

describe Sepia do

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
    sepia_string = user.to_sepia
    expected = "{\"name\" => \"John Doe\", \"age\" => \"42\", \"user_email\" => \"john.doe@example.com\", \"city\" => \"Crystal City\"}"

    # Split lines and sort to make test independent of property order
    sepia_string.should eq expected
  end

  it "deserializes an object from sepia format" do
    user = TestUser.from_sepia("whocares")
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
end

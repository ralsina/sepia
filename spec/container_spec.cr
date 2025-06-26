require "./spec_helper"

class MyThing
  include Sepia::Serializable

  property name : String = "Foo"

  def to_sepia : String
    name
  end

  def self.from_sepia(sepia_string : String) : MyThing
    obj = MyThing.new
    obj.name = sepia_string
    obj
  end
end

class MyBox
  include Sepia::Container

  property my_thing : MyThing = MyThing.new
end

describe Sepia::Container do
  before_each do
    FileUtils.rm_rf(PATH) if File.exists?(PATH)
    FileUtils.mkdir_p(PATH)
    Sepia::Storage::INSTANCE.path = PATH
  end
  after_each do
    # FileUtils.rm_rf(PATH) if File.exists?(PATH)
  end

  it "can save itself" do
    box = MyBox.new
    box.sepia_id = "mybox"
    box.save

    loaded = MyBox.load("mybox")
    loaded.should be_a(MyBox)
    loaded.as(MyBox).sepia_id.should eq "mybox"
  end

  it "can load itself" do
    box = MyBox.new
    box.sepia_id = "mybox"
    box.my_thing.sepia_id = "Foobar"
    box.my_thing.name = "Barfoo"
    box.save

    loaded = MyBox.load("mybox")
    loaded.should be_a(MyBox)
    loaded.should_not be_nil
    loaded = loaded.as(MyBox)
    loaded.sepia_id.should eq "mybox"

    loaded.my_thing.should be_a(MyThing)

    loaded.my_thing.sepia_id.should eq "Foobar"
    loaded.my_thing.name.should eq "Barfoo"
  end
end

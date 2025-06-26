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

class MyNestedBox
  include Sepia::Container
  property nested_thing : MyThing = MyThing.new
end

class MyBox
  include Sepia::Container

  property my_thing : MyThing = MyThing.new
  property nested_box : MyNestedBox = MyNestedBox.new
  property my_things : Array(MyThing) = [MyThing.new]
  property not_things : Array(String) = ["foo"] of String
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

  it "can load itself with all features" do
    box = MyBox.new
    box.sepia_id = "mybox"
    box.my_thing.sepia_id = "Foobar"
    box.my_thing.name = "Barfoo"

    box.nested_box.sepia_id = "NestedBoxID"
    box.nested_box.nested_thing.sepia_id = "NestedThingID"
    box.nested_box.nested_thing.name = "NestedThingName"

    box.save

    loaded = MyBox.load("mybox").as(MyBox)

    loaded.should be_a(MyBox)
    loaded.sepia_id.should eq "mybox"

    loaded.my_thing.should be_a(MyThing)
    loaded.my_thing.sepia_id.should eq "Foobar"
    loaded.my_thing.name.should eq "Barfoo"

    loaded.nested_box.should be_a(MyNestedBox)
    loaded.nested_box.sepia_id.should eq "NestedBoxID"
    loaded.nested_box.nested_thing.should be_a(MyThing)
    loaded.nested_box.nested_thing.sepia_id.should eq "NestedThingID"
    loaded.nested_box.nested_thing.name.should eq "NestedThingName"
  end
end

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
  property nested_boxes : Array(MyNestedBox) = [MyNestedBox.new]
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

    # Create a couple of MyThing objects for the array
    thing1 = MyThing.new
    thing1.name = "Thing1"
    thing1.sepia_id = "thing1_id"
    thing2 = MyThing.new
    thing2.name = "Thing2"
    thing2.sepia_id = "thing2_id"
    box.my_things = [thing1, thing2]

    # Create a couple of MyNestedBox objects for the array
    nested_box1 = MyNestedBox.new
    nested_box1.sepia_id = "nested_box1_id"
    nested_box1.nested_thing.name = "NestedInBox1"
    nested_box1.nested_thing.sepia_id = "nested_in_box1_id"
    nested_box2 = MyNestedBox.new
    nested_box2.sepia_id = "nested_box2_id"
    nested_box2.nested_thing.name = "NestedInBox2"
    nested_box2.nested_thing.sepia_id = "nested_in_box2_id"
    box.nested_boxes = [nested_box1, nested_box2]

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

    # Assertions for the array of MyThing
    loaded.my_things.size.should eq 2
    loaded.my_things[0].name.should eq "Thing1"
    loaded.my_things[0].sepia_id.should eq "thing1_id"
    loaded.my_things[1].name.should eq "Thing2"
    loaded.my_things[1].sepia_id.should eq "thing2_id"

    # Assertions for the array of MyNestedBox
    loaded.nested_boxes.size.should eq 2
    loaded.nested_boxes[0].sepia_id.should eq "nested_box1_id"
    loaded.nested_boxes[0].nested_thing.name.should eq "NestedInBox1"
    loaded.nested_boxes[0].nested_thing.sepia_id.should eq "nested_in_box1_id"
    loaded.nested_boxes[1].sepia_id.should eq "nested_box2_id"
    loaded.nested_boxes[1].nested_thing.name.should eq "NestedInBox2"
    loaded.nested_boxes[1].nested_thing.sepia_id.should eq "nested_in_box2_id"
  end
end

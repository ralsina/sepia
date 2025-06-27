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

class MySetBox
  include Sepia::Container
  property my_things : Set(MyThing) = Set(MyThing).new
end

class MySetOfContainersBox
  include Sepia::Container
  property nested_boxes : Set(MyNestedBox) = Set(MyNestedBox).new
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

  describe MyBox do
    it "has the correct top-level properties" do
      box = MyBox.new
      box.sepia_id = "mybox"
      box.save
      loaded = MyBox.load("mybox").as(MyBox)
      loaded.should be_a(MyBox)
      loaded.sepia_id.should eq "mybox"
    end

    it "has the correct nested serializable" do
      box = MyBox.new
      box.my_thing.sepia_id = "Foobar"
      box.my_thing.name = "Barfoo"
      box.save
      loaded = MyBox.load(box.sepia_id).as(MyBox)
      loaded.my_thing.should be_a(MyThing)
      loaded.my_thing.sepia_id.should eq "Foobar"
      loaded.my_thing.name.should eq "Barfoo"
    end

    it "has the correct nested container" do
      box = MyBox.new
      box.nested_box.nested_thing.sepia_id = "NestedThingID"
      box.nested_box.nested_thing.name = "NestedThingName"
      box.save
      loaded = MyBox.load(box.sepia_id).as(MyBox)
      loaded.nested_box.should be_a(MyNestedBox)
      loaded.nested_box.sepia_id.should eq "nested_box"
      loaded.nested_box.nested_thing.should be_a(MyThing)
      loaded.nested_box.nested_thing.sepia_id.should eq "NestedThingID"
      loaded.nested_box.nested_thing.name.should eq "NestedThingName"
    end

    it "has the correct array of serializables" do
      box = MyBox.new
      thing1 = MyThing.new
      thing1.name = "Thing1"
      thing1.sepia_id = "thing1_id"
      thing2 = MyThing.new
      thing2.name = "Thing2"
      thing2.sepia_id = "thing2_id"
      box.my_things = [thing1, thing2]
      box.save
      loaded = MyBox.load(box.sepia_id).as(MyBox)
      loaded.my_things.size.should eq 2
      loaded.my_things[0].name.should eq "Thing1"
      loaded.my_things[0].sepia_id.should eq "thing1_id"
      loaded.my_things[1].name.should eq "Thing2"
      loaded.my_things[1].sepia_id.should eq "thing2_id"
    end

    it "has the correct array of containers" do
      box = MyBox.new
      nested_box1 = MyNestedBox.new
      nested_box1.nested_thing.name = "NestedInBox1"
      nested_box1.nested_thing.sepia_id = "nested_in_box1_id"
      nested_box2 = MyNestedBox.new
      nested_box2.nested_thing.name = "NestedInBox2"
      nested_box2.nested_thing.sepia_id = "nested_in_box2_id"
      box.nested_boxes = [nested_box1, nested_box2]
      box.save
      loaded = MyBox.load(box.sepia_id).as(MyBox)
      loaded.nested_boxes.size.should eq 2
      loaded.nested_boxes[0].sepia_id.should eq "0"
      loaded.nested_boxes[0].nested_thing.name.should eq "NestedInBox1"
      loaded.nested_boxes[0].nested_thing.sepia_id.should eq "nested_in_box1_id"
      loaded.nested_boxes[1].sepia_id.should eq "1"
      loaded.nested_boxes[1].nested_thing.name.should eq "NestedInBox2"
      loaded.nested_boxes[1].nested_thing.sepia_id.should eq "nested_in_box2_id"
    end

    it "has the correct on-disk representation" do
      box = MyBox.new
      box.sepia_id = "mybox"
      nested_box1 = MyNestedBox.new
      box.nested_boxes = [nested_box1]
      box.save
      File.directory?(File.join(PATH, "MyBox", "mybox", "nested_box")).should be_true
      File.symlink?(File.join(PATH, "MyBox", "mybox", "my_thing")).should be_true
      File.directory?(File.join(PATH, "MyBox", "mybox", "nested_boxes")).should be_true
    end

    it "does not create directories for empty arrays" do
      box = MyBox.new
      box.sepia_id = "mybox"
      box.nested_boxes = [] of MyNestedBox
      box.save
      File.directory?(File.join(PATH, "MyBox", "mybox", "nested_boxes")).should be_false
    end
  end

  it "can roundtrip a set" do
    box = MySetBox.new
    box.sepia_id = "mysetbox"

    thing1 = MyThing.new
    thing1.name = "Thing1"
    thing1.sepia_id = "thing1_id"
    thing2 = MyThing.new
    thing2.name = "Thing2"
    thing2.sepia_id = "thing2_id"
    box.my_things = Set{thing1, thing2}

    box.save

    loaded = MySetBox.load("mysetbox").as(MySetBox)
    loaded.should be_a(MySetBox)
    loaded.my_things.size.should eq 2
    loaded.my_things.map(&.name).to_a.sort.should eq ["Thing1", "Thing2"]
  end

  it "can roundtrip a set of containers" do
    box = MySetOfContainersBox.new
    box.sepia_id = "mysetofcontainersbox"

    nested_box1 = MyNestedBox.new
    nested_box1.nested_thing.name = "NestedInBox1"
    nested_box1.nested_thing.sepia_id = "nested_in_box1_id"
    nested_box2 = MyNestedBox.new
    nested_box2.nested_thing.name = "NestedInBox2"
    nested_box2.nested_thing.sepia_id = "nested_in_box2_id"
    box.nested_boxes = Set{nested_box1, nested_box2}

    box.save

    loaded = MySetOfContainersBox.load("mysetofcontainersbox").as(MySetOfContainersBox)
    loaded.should be_a(MySetOfContainersBox)
    loaded.nested_boxes.size.should eq 2
    loaded.nested_boxes.map(&.nested_thing.name).to_a.sort.should eq ["NestedInBox1", "NestedInBox2"]
  end
end

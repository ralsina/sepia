require "./spec_helper"

class MyThing < Sepia::Object
  include Sepia::Serializable
  include JSON::Serializable

  property name : String

  def initialize(@name = "Foo")
  end

  def to_sepia : String
    name
  end

  def self.from_sepia(sepia_string : String) : MyThing
    MyThing.new(sepia_string)
  end
end

class MyNestedBox < Sepia::Object
  include Sepia::Container
  property nested_thing : MyThing

  def initialize
    @nested_thing = MyThing.new
  end
end

class MyBox < Sepia::Object
  include Sepia::Container

  property my_thing : MyThing
  property nested_box : MyNestedBox
  property nested_boxes : Array(MyNestedBox)
  property my_things : Array(MyThing)
  property not_things : Array(String)

  def initialize
    @my_thing = MyThing.new
    @nested_box = MyNestedBox.new
    @nested_boxes = [MyNestedBox.new]
    @my_things = [MyThing.new]
    @not_things = ["foo"] of String
  end
end

class MySetBox < Sepia::Object
  include Sepia::Container
  property my_things : Set(MyThing)

  def initialize
    @my_things = Set(MyThing).new
  end
end

class MySetOfContainersBox < Sepia::Object
  include Sepia::Container
  property nested_boxes : Set(MyNestedBox)

  def initialize
    @nested_boxes = Set(MyNestedBox).new
  end
end

class MyHashBox < Sepia::Object
  include Sepia::Container
  property my_things : Hash(String, MyThing)

  def initialize
    @my_things = Hash(String, MyThing).new
  end
end

class MyHashOfContainersBox < Sepia::Object
  include Sepia::Container
  property nested_boxes : Hash(String, MyNestedBox)

  def initialize
    @nested_boxes = Hash(String, MyNestedBox).new
  end
end

class MyNilableBox < Sepia::Object
  include Sepia::Container
  property nilable_thing : MyThing?
  property required_thing : MyThing

  def initialize
    @nilable_thing = nil
    @required_thing = MyThing.new
  end
end

class PrimitiveOnlyBox < Sepia::Object
  include Sepia::Container
  property name : String
  property count : Int32
  property timestamp : Time
  # ameba:disable Naming/QueryBoolMethods
  property flag : Bool

  def initialize
    @name = "default"
    @count = 42
    @timestamp = Time.utc(2023, 1, 1)
    @flag = true
  end
end

class PrimitiveArraysBox < Sepia::Object
  include Sepia::Container
  property strings : Array(String)
  property ints : Array(Int32)
  property floats : Array(Float64)
  property bools : Array(Bool)

  def initialize
    @strings = [] of String
    @ints = [] of Int32
    @floats = [] of Float64
    @bools = [] of Bool
  end
end

class PrimitiveHashBox < Sepia::Object
  include Sepia::Container
  property string_map : Hash(String, String)
  property int_map : Hash(String, Int32)
  property mixed_map : Hash(String, Float64)

  def initialize
    @string_map = Hash(String, String).new
    @int_map = Hash(String, Int32).new
    @mixed_map = Hash(String, Float64).new
  end
end

describe Sepia::Container do
  path = File.join(Dir.tempdir, "sepia_storage_test")

  before_each do
    FileUtils.rm_rf(path) if File.exists?(path)
    FileUtils.mkdir_p(path)
    Sepia::Storage.configure(:filesystem, {"path" => path})
  end
  after_each do
    # FileUtils.rm_rf(path) if File.exists?(path)
  end

  describe "JSON serialization for primitive properties" do
    it "saves and loads primitive properties via data.json" do
      box = MyBox.new
      box.sepia_id = "json_test_box"
      box.not_things = ["hello", "world", "test"]

      box.save

      # Check that data.json file exists
      data_file = File.join(path, "MyBox", "json_test_box", "data.json")
      File.exists?(data_file).should be_true

      # Check the content of data.json
      json_content = File.read(data_file)
      json_content.should contain(%("not_things":["hello","world","test"]))

      # Load and verify the primitive properties
      loaded = MyBox.load("json_test_box").as(MyBox)
      loaded.not_things.should eq ["hello", "world", "test"]
    end

    it "handles containers with only primitive properties" do
      box = PrimitiveOnlyBox.new
      box.sepia_id = "primitive_only"
      box.name = "test box"
      box.count = 100
      box.timestamp = Time.utc(2024, 6, 15, 12, 30, 45)
      box.flag = false

      box.save

      # Check that data.json exists and contains all primitive properties
      data_file = File.join(path, "PrimitiveOnlyBox", "primitive_only", "data.json")
      File.exists?(data_file).should be_true

      json_content = File.read(data_file)
      json_content.should contain(%("name":"test box"))
      json_content.should contain(%("count":100))
      json_content.should contain(%("flag":false))

      # Load and verify
      loaded = PrimitiveOnlyBox.load("primitive_only").as(PrimitiveOnlyBox)
      loaded.name.should eq "test box"
      loaded.count.should eq 100
      loaded.flag.should eq false
      loaded.timestamp.should eq Time.utc(2024, 6, 15, 12, 30, 45)
    end

    it "correctly excludes Sepia objects from JSON serialization" do
      box = MyBox.new
      box.sepia_id = "exclusion_test"
      box.my_thing.name = "Special Thing"
      box.not_things = ["primitive", "data"]

      box.save

      data_file = File.join(path, "MyBox", "exclusion_test", "data.json")
      json_content = File.read(data_file)

      # Should contain primitive data
      json_content.should contain(%("not_things":["primitive","data"]))

      # Should NOT contain Sepia object references
      json_content.should_not contain("my_thing")
      json_content.should_not contain("nested_box")
      json_content.should_not contain("my_things")
      json_content.should_not contain("nested_boxes")
    end

    it "works with mixed primitive and Sepia object properties" do
      box = MyBox.new
      box.sepia_id = "mixed_test"
      box.not_things = ["array", "of", "strings"]
      box.my_thing.name = "Linked Object"

      box.save

      # Load and verify both types of properties
      loaded = MyBox.load("mixed_test").as(MyBox)

      # Primitive properties should be loaded from JSON
      loaded.not_things.should eq ["array", "of", "strings"]

      # Sepia objects should be loaded via symlinks
      loaded.my_thing.name.should eq "Linked Object"
    end

    it "handles arrays of primitive types" do
      box = PrimitiveArraysBox.new
      box.sepia_id = "arrays_test"
      box.strings = ["one", "two", "three"]
      box.ints = [1, 2, 3]
      box.floats = [1.5, 2.5, 3.5]
      box.bools = [true, false, true]

      box.save

      # Check that data.json contains all arrays
      data_file = File.join(path, "PrimitiveArraysBox", "arrays_test", "data.json")
      json_content = File.read(data_file)

      json_content.should contain(%("strings":["one","two","three"]))
      json_content.should contain(%("ints":[1,2,3]))
      json_content.should contain(%("floats":[1.5,2.5,3.5]))
      json_content.should contain(%("bools":[true,false,true]))

      # Load and verify
      loaded = PrimitiveArraysBox.load("arrays_test").as(PrimitiveArraysBox)
      loaded.strings.should eq ["one", "two", "three"]
      loaded.ints.should eq [1, 2, 3]
      loaded.floats.should eq [1.5, 2.5, 3.5]
      loaded.bools.should eq [true, false, true]
    end

    it "handles hashes of primitive types" do
      box = PrimitiveHashBox.new
      box.sepia_id = "hashes_test"
      box.string_map = {"a" => "apple", "b" => "banana"}
      box.int_map = {"one" => 1, "two" => 2}
      box.mixed_map = {"pi" => 3.14159, "e" => 2.71828}

      box.save

      # Check that data.json contains all hashes
      data_file = File.join(path, "PrimitiveHashBox", "hashes_test", "data.json")
      json_content = File.read(data_file)

      json_content.should contain(%("string_map":{"a":"apple","b":"banana"}))
      json_content.should contain(%("int_map":{"one":1,"two":2}))
      json_content.should contain(%("mixed_map":{"pi":3.14159,"e":2.71828}))

      # Load and verify
      loaded = PrimitiveHashBox.load("hashes_test").as(PrimitiveHashBox)
      loaded.string_map.should eq({"a" => "apple", "b" => "banana"})
      loaded.int_map.should eq({"one" => 1, "two" => 2})
      loaded.mixed_map.should eq({"pi" => 3.14159, "e" => 2.71828})
    end
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
      box.nested_box.sepia_id = "nested_box"
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
      loaded.nested_boxes[0].sepia_id.should eq nested_box1.sepia_id
      loaded.nested_boxes[0].nested_thing.name.should eq "NestedInBox1"
      loaded.nested_boxes[0].nested_thing.sepia_id.should eq "nested_in_box1_id"
      loaded.nested_boxes[1].sepia_id.should eq nested_box2.sepia_id
      loaded.nested_boxes[1].nested_thing.name.should eq "NestedInBox2"
      loaded.nested_boxes[1].nested_thing.sepia_id.should eq "nested_in_box2_id"
    end

    it "has the correct on-disk representation" do
      box = MyBox.new
      box.sepia_id = "mybox"
      nested_box1 = MyNestedBox.new
      box.nested_boxes = [nested_box1]
      box.save
      File.directory?(File.join(path, "MyBox", "mybox", "nested_box")).should be_true
      File.symlink?(File.join(path, "MyBox", "mybox", "my_thing")).should be_true
      File.directory?(File.join(path, "MyBox", "mybox", "nested_boxes")).should be_true
    end

    it "does not create directories for empty arrays" do
      box = MyBox.new
      box.sepia_id = "mybox"
      box.nested_boxes = [] of MyNestedBox
      box.save
      File.directory?(File.join(path, "MyBox", "mybox", "nested_boxes")).should be_false
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

  it "can roundtrip a hash of serializables" do
    box = MyHashBox.new
    box.sepia_id = "myhashbox"

    thing1 = MyThing.new
    thing1.name = "Thing1"
    thing1.sepia_id = "thing1_id"
    thing2 = MyThing.new
    thing2.name = "Thing2"
    thing2.sepia_id = "thing2_id"
    box.my_things = {"a" => thing1, "b" => thing2}

    box.save

    loaded = MyHashBox.load("myhashbox").as(MyHashBox)
    loaded.should be_a(MyHashBox)
    loaded.my_things.size.should eq 2
    loaded.my_things["a"].name.should eq "Thing1"
    loaded.my_things["b"].name.should eq "Thing2"
  end

  it "can roundtrip a hash of containers" do
    box = MyHashOfContainersBox.new
    box.sepia_id = "myhashofcontainersbox"

    nested_box1 = MyNestedBox.new
    nested_box1.nested_thing.name = "NestedInBox1"
    nested_box1.nested_thing.sepia_id = "nested_in_box1_id"
    nested_box2 = MyNestedBox.new
    nested_box2.nested_thing.name = "NestedInBox2"
    nested_box2.nested_thing.sepia_id = "nested_in_box2_id"
    box.nested_boxes = {"a" => nested_box1, "b" => nested_box2}

    box.save

    loaded = MyHashOfContainersBox.load("myhashofcontainersbox").as(MyHashOfContainersBox)
    loaded.should be_a(MyHashOfContainersBox)
    loaded.nested_boxes.size.should eq 2
    loaded.nested_boxes["a"].nested_thing.name.should eq "NestedInBox1"
    loaded.nested_boxes["b"].nested_thing.name.should eq "NestedInBox2"
  end

  it "can save and load a container from a custom path" do
    box = MyBox.new
    box.sepia_id = "custom_path_box"
    box.my_thing.name = "Thing in custom path"
    custom_path = File.join(path, "custom_container_location", box.sepia_id)
    box.save(custom_path)

    File.directory?(custom_path).should be_true
    File.directory?(File.join(path, "MyBox", box.sepia_id)).should be_false

    loaded_box = MyBox.load("custom_path_box", path: custom_path).as(MyBox)

    loaded_box.sepia_id.should eq "custom_path_box"
    loaded_box.my_thing.name.should eq "Thing in custom path"
  end

  describe "nilable Serializable properties" do
    it "correctly saves and loads nilable Serializable objects" do
      container = MyNilableBox.new
      container.nilable_thing = MyThing.new
      container.nilable_thing.not_nil!.name = "Nilable Thing"
      container.required_thing.name = "Required Thing"

      container.save

      loaded = MyNilableBox.load(container.sepia_id).as(MyNilableBox)

      loaded.nilable_thing.should_not be_nil
      loaded.nilable_thing.not_nil!.name.should eq "Nilable Thing"
      loaded.required_thing.name.should eq "Required Thing"
    end

    it "correctly handles nil values for nilable Serializable properties" do
      container = MyNilableBox.new
      container.nilable_thing = nil
      container.required_thing.name = "Required Thing"

      container.save

      loaded = MyNilableBox.load(container.sepia_id).as(MyNilableBox)

      loaded.nilable_thing.should be_nil
      loaded.required_thing.name.should eq "Required Thing"
    end

    it "creates symlinks for nilable Serializable objects when not nil" do
      container = MyNilableBox.new
      container.nilable_thing = MyThing.new
      container.nilable_thing.not_nil!.name = "Nilable Thing"
      container.required_thing.name = "Required Thing"

      container.save

      container_path = File.join(path, "MyNilableBox", container.sepia_id)
      symlink_path = File.join(container_path, "nilable_thing")

      File.symlink?(symlink_path).should be_true
    end

    it "does not create symlinks for nilable Serializable objects when nil" do
      container = MyNilableBox.new
      container.nilable_thing = nil
      container.required_thing.name = "Required Thing"

      container.save

      container_path = File.join(path, "MyNilableBox", container.sepia_id)
      symlink_path = File.join(container_path, "nilable_thing")

      File.symlink?(symlink_path).should be_false
    end

    it "uses smart save behavior to avoid duplicate saves" do
      # Create individual objects
      thing1 = MyThing.new("First Thing")
      thing1.sepia_id = "thing1"
      thing2 = MyThing.new("Second Thing")
      thing2.sepia_id = "thing2"

      # Save individual objects first
      thing1.save
      thing2.save

      # Count events before container save
      initial_events = Sepia::Storage.object_events(MyThing, "thing1").size

      # Create container with references to objects
      box = MyBox.new
      box.my_things.clear # Remove default my_thing
      box.my_things << thing1 << thing2
      box.sepia_id = "test-box"

      # Save container (should NOT save individual objects again)
      box.save

      # Check that individual objects weren't saved again
      final_events = Sepia::Storage.object_events(MyThing, "thing1").size
      final_events.should eq(initial_events) # No duplicate saves

      # Verify container was saved and references exist
      loaded_box = MyBox.load("test-box").as(MyBox)
      loaded_box.my_things.size.should eq(2)
    end
  end
end

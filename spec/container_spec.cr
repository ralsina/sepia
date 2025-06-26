require "./spec_helper"


class MyThing
  include Sepia::Serializable

  property name : String = "Foo"

  def to_sepia : String
    name
  end

  def self.from_sepia(sepia_string : String) : MyThing
    name = sepia_string
    MyThing.new(name: name)
  end
end

class MyBox
  include Sepia::Container

  property my_thing : MyThing = MyThing.new
end


describe Sepia::Container do
  it "can save itself" do
    box = MyBox.new
    box.sepia_id = "mybox"
    box.save

    loaded = MyBox.load("mybox")
    loaded.should be_a(MyBox)
    loaded.not_nil!.sepia_id.should eq "mybox"
  end
end

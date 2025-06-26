require "./spec_helper"

class MyBox
    include Sepia::Container
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
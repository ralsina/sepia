require "./spec_helper"

class ApiTestDoc < Sepia::Object
  include Sepia::Serializable

  property title : String
  property content : String

  def initialize(@title : String, @content : String)
  end

  def to_sepia : String
    {
      "title" => @title,
      "content" => @content,
    }.to_json
  end

  def self.from_sepia(sepia_string : String) : self
    data = JSON.parse(sepia_string)
    new(
      data["title"].as_s,
      data["content"].as_s
    )
  end
end

describe "API Improvements - High Value Tests" do
  test_dir = File.join(Dir.tempdir, "sepia_api_focused_test")

  before_each do
    FileUtils.rm_rf(test_dir) if File.exists?(test_dir)
    FileUtils.mkdir_p(test_dir)
    Sepia::Storage.configure(:filesystem, {"path" => test_dir})
  end

  after_each do
    FileUtils.rm_rf(test_dir) if File.exists?(test_dir)
  end

  describe "Storage.load? methods (NEW FUNCTIONALITY)" do
    it "returns object when it exists" do
      # Create and save an object
      doc = ApiTestDoc.new("Test Title", "Test Content")
      doc.save

      # Test class method
      loaded_doc = Sepia::Storage.load?(ApiTestDoc, doc.sepia_id)
      loaded_doc.should_not be_nil
      loaded_doc.try do |doc|
        doc.title.should eq("Test Title")
        doc.content.should eq("Test Content")
      end

      # Test instance method
      storage = Sepia::Storage::INSTANCE
      loaded_doc2 = storage.load?(ApiTestDoc, doc.sepia_id)
      loaded_doc2.should_not be_nil
      loaded_doc2.try do |doc|
        doc.title.should eq("Test Title")
      end
    end

    it "returns nil when object doesn't exist (THE MAIN BENEFIT)" do
      # Test class method - no try/catch needed!
      loaded_doc = Sepia::Storage.load?(ApiTestDoc, "non-existent-id")
      loaded_doc.should be_nil

      # Test instance method
      storage = Sepia::Storage::INSTANCE
      loaded_doc2 = storage.load?(ApiTestDoc, "non-existent-id")
      loaded_doc2.should be_nil
    end

    it "works with caching enabled/disabled" do
      doc = ApiTestDoc.new("Test", "Content")
      doc.save

      # With caching (default)
      loaded_doc = Sepia::Storage.load?(ApiTestDoc, doc.sepia_id, cache: true)
      loaded_doc.should_not be_nil

      # Without caching
      loaded_doc2 = Sepia::Storage.load?(ApiTestDoc, doc.sepia_id, cache: false)
      loaded_doc2.should_not be_nil
    end
  end

  describe "latest() method bug fix (THE MAIN BUG)" do
    it "returns nil for non-existent base ID (BUG FIX)" do
      # This was the main issue - latest() would throw Enumerable::EmptyError
      # but now should return nil as the type annotation suggests
      latest_doc = ApiTestDoc.latest("completely-non-existent-object")
      latest_doc.should be_nil
    end

    it "returns latest generation when multiple exist" do
      # Create base object
      base_doc = ApiTestDoc.new("Base Title", "Base Content")
      base_doc.sepia_id = "test-fixed"
      base_doc.save

      # Create generation 1 using save_with_generation
      gen1_doc = ApiTestDoc.new("Gen1 Title", "Gen1 Content")
      gen1_doc.sepia_id = "test-fixed"
      gen1 = gen1_doc.save_with_generation

      # Create generation 2 using save_with_generation
      gen2_doc = ApiTestDoc.new("Gen2 Title", "Gen2 Content")
      gen2_doc.sepia_id = gen1.sepia_id
      gen2 = gen2_doc.save_with_generation

      # The fix: this should work without throwing
      latest_doc = ApiTestDoc.latest("test-fixed")
      latest_doc.should_not be_nil
      latest_doc.try do |doc|
        doc.title.should eq("Gen2 Title")
        doc.content.should eq("Gen2 Content")
      end
    end
  end

  describe "latest! method (API CONSISTENCY)" do
    it "throws exception when no generations exist" do
      expect_raises(Enumerable::EmptyError) do
        ApiTestDoc.latest!("non-existent-id")
      end
    end

    it "returns latest generation when it exists" do
      # Create base object
      base_doc = ApiTestDoc.new("Base Title", "Base Content")
      base_doc.sepia_id = "test-latest"
      base_doc.save

      # Create generation 1 using save_with_generation
      gen1_doc = ApiTestDoc.new("Gen1 Title", "Gen1 Content")
      gen1_doc.sepia_id = "test-latest"
      gen1 = gen1_doc.save_with_generation
      puts "Created gen1: #{gen1.sepia_id} (gen #{gen1.generation})"

      # Test latest! returns generation 1 (the only generation created)
      latest_doc = ApiTestDoc.latest!("test-latest")
      latest_doc.title.should eq("Gen1 Title")
      latest_doc.content.should eq("Gen1 Content")
      # Generation should be 1, not expecting 2 since only one save_with_generation call
      latest_doc.generation.should eq(1)
    end
  end

  describe "Storage.load! methods (API CONSISTENCY)" do
    it "returns object when it exists" do
      doc = ApiTestDoc.new("Test Title", "Test Content")
      doc.save

      # Test class method
      loaded_doc = Sepia::Storage.load!(ApiTestDoc, doc.sepia_id)
      loaded_doc.title.should eq("Test Title")
      loaded_doc.content.should eq("Test Content")

      # Test instance method
      storage = Sepia::Storage::INSTANCE
      loaded_doc2 = storage.load!(ApiTestDoc, doc.sepia_id)
      loaded_doc2.title.should eq("Test Title")
    end

    it "throws exception when object doesn't exist (EXPLICIT BEHAVIOR)" do
      # Test class method
      expect_raises(Exception) do
        Sepia::Storage.load!(ApiTestDoc, "non-existent-id")
      end

      # Test instance method
      storage = Sepia::Storage::INSTANCE
      expect_raises(Exception) do
        storage.load!(ApiTestDoc, "non-existent-id")
      end
    end
  end
end
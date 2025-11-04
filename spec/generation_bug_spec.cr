require "./spec_helper"

class GenTestDocument < Sepia::Object
  include Sepia::Serializable

  property content : String

  def initialize(@content = "")
  end

  def to_sepia : String
    @content
  end

  def self.from_sepia(sepia_string : String) : self
    new(sepia_string)
  end
end

describe "Generation Bug Investigation" do
  path = File.join(Dir.tempdir, "sepia_generation_bug_test")

  before_each do
    FileUtils.rm_rf(path) if File.exists?(path)
    FileUtils.mkdir_p(path)
    Sepia::Storage.configure(:filesystem, {"path" => path})
  end

  after_each do
    # FileUtils.rm_rf(path) if File.exists?(path)
  end

  it "demonstrates the force_new_generation fix" do
    # Create and save initial object
    doc = GenTestDocument.new("version 1")
    doc.sepia_id = "test-doc"
    doc.save

    # Verify base file exists
    base_file = File.join(path, "GenTestDocument", "test-doc")
    File.exists?(base_file).should be_true
    File.read(base_file).should eq("version 1")

    # Modify content and save with force_new_generation
    doc.content = "version 2"
    doc.save(force_new_generation: true)

    # FIX: This now correctly creates a generation file!
    gen1_file = File.join(path, "GenTestDocument", "test-doc.1")

    puts "=== Fix Verification ==="
    puts "Base file exists: #{File.exists?(base_file)}"
    puts "Generation file exists: #{File.exists?(gen1_file)}"
    puts "Base file content: #{File.read(base_file)}"
    puts "Generation file content: #{File.read(gen1_file)}"

    # The base file is preserved and generation file is created
    File.read(base_file).should eq("version 1") # Base unchanged
    File.exists?(gen1_file).should be_true      # Generation exists
    File.read(gen1_file).should eq("version 2") # Generation has new content
  end

  it "shows save_with_generation works correctly" do
    # Create and save initial object
    doc = GenTestDocument.new("version 1")
    doc.sepia_id = "test-doc2"
    doc.save

    # Create generation using save_with_generation
    doc.content = "version 2"
    gen_doc = doc.save_with_generation

    # This works correctly
    base_file = File.join(path, "GenTestDocument", "test-doc2")
    gen1_file = File.join(path, "GenTestDocument", "test-doc2.1")

    puts "=== Working save_with_generation ==="
    puts "Base file exists: #{File.exists?(base_file)}"
    puts "Generation file exists: #{File.exists?(gen1_file)}"
    puts "Base file content: #{File.read(base_file)}"
    puts "Generation file content: #{File.read(gen1_file)}"
    puts "Returned object ID: #{gen_doc.sepia_id}"

    File.exists?(base_file).should be_true
    File.exists?(gen1_file).should be_true
    File.read(base_file).should eq("version 1")
    File.read(gen1_file).should eq("version 2")
    gen_doc.sepia_id.should eq("test-doc2.1")
  end

  it "tests generation loading and content isolation" do
    # Create object and test force_new_generation works
    doc = GenTestDocument.new("version 1")
    doc.sepia_id = "test-doc3"
    doc.save

    # Create first generation
    doc.content = "version 2"
    gen1_obj = doc.save(force_new_generation: true)

    # Create second generation - need to modify original and save again
    doc.content = "version 3"
    gen2_obj = doc.save(force_new_generation: true)

    # Test loading different generations
    base_doc = GenTestDocument.load("test-doc3")
    gen1_doc = GenTestDocument.load("test-doc3.1")
    gen2_doc = GenTestDocument.load("test-doc3.2")

    puts "=== Generation Loading Test ==="
    puts "Base doc content: #{base_doc.content}"
    puts "Gen 1 doc content: #{gen1_doc.content}"
    puts "Gen 2 doc content: #{gen2_doc.content}"
    puts "Original doc content: #{doc.content}"

    base_doc.content.should eq("version 3")  # Base returns latest generation (transparent)
    gen1_doc.content.should eq("version 2")
    gen2_doc.content.should eq("version 3")  # Latest generation content

    # Test generation properties
    base_doc.generation.should eq(2)  # Transparent load returns latest generation
    gen1_doc.generation.should eq(1)
    gen2_doc.generation.should eq(2)

    base_doc.base_id.should eq("test-doc3")
    gen1_doc.base_id.should eq("test-doc3")
    gen2_doc.base_id.should eq("test-doc3")

    # Original object should remain unchanged
    doc.sepia_id.should eq("test-doc3")
  end
end

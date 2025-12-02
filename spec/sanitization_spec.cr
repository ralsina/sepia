require "spec"
require "../src/sepia"

class TestDocument < Sepia::Object
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

describe "Sepia::Object sepia_id sanitization" do
  it "replaces forward slashes with underscores in custom sepia_id" do
    doc = TestDocument.new("test content")

    # Set an ID with forward slashes
    doc.sepia_id = "path/to/document"

    # Should have slashes replaced
    doc.sepia_id.should eq("path_to_document")
  end

  it "handles IDs with multiple slashes" do
    doc = TestDocument.new("test content")
    doc.sepia_id = "a/very/complex/path/with/many/slashes"

    doc.sepia_id.should eq("a_very_complex_path_with_many_slashes")
  end

  it "preserves IDs without slashes" do
    doc = TestDocument.new("test content")
    doc.sepia_id = "normal-document-id"

    doc.sepia_id.should eq("normal-document-id")
  end

  it "handles empty string" do
    doc = TestDocument.new("test content")
    doc.sepia_id = ""

    doc.sepia_id.should eq("")
  end

  it "handles edge cases" do
    doc = TestDocument.new("test content")

    # Leading slash
    doc.sepia_id = "/leading/slash"
    doc.sepia_id.should eq("_leading_slash")

    # Trailing slash
    doc.sepia_id = "trailing/slash/"
    doc.sepia_id.should eq("trailing_slash_")

    # Only slashes
    doc.sepia_id = "///"
    doc.sepia_id.should eq("___")
  end
end
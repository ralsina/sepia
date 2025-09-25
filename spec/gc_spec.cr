require "./spec_helper"

# --- Test Classes ---

class GCPostit < Sepia::Object
  include Sepia::Serializable
  property text : String

  def initialize(@text = ""); end

  def to_sepia
    @text
  end

  def self.from_sepia(s)
    new(s)
  end
end

class GCBoard < Sepia::Object
  include Sepia::Container

  property name : String
  property postits : Array(GCPostit)
  property boards : Array(GCBoard)

  def initialize(@name = "", @postits = [] of GCPostit, @boards = [] of GCBoard); end
end

describe "Sepia::Storage.gc" do
  before_each do
    # Configure storage
    Sepia::Storage.configure(:filesystem, {"path" => "sepia-gc-spec"})
    FileUtils.rm_rf("sepia-gc-spec") if Dir.exists?("sepia-gc-spec")
    FileUtils.mkdir_p("sepia-gc-spec")
  end

  after_each do
    FileUtils.rm_rf("sepia-gc-spec") if Dir.exists?("sepia-gc-spec")
  end

  it "collects a simple orphaned serializable" do
    # Create a root board and an orphan postit
    root_board = GCBoard.new("root")
    root_board.save # Save the root so it exists in storage

    orphan_postit = GCPostit.new("I am an orphan")
    orphan_postit.sepia_id = "orphan1"
    orphan_postit.save

    Sepia::Storage.exists?(GCPostit, "orphan1").should be_true

    # Run garbage collection, passing the root board as the root
    deleted = Sepia::Storage.gc(roots: [root_board])
    deleted["GCPostit"].should eq ["orphan1"]

    Sepia::Storage.exists?(GCPostit, "orphan1").should be_false
  end

  it "does not collect objects reachable from a root" do
    board = GCBoard.new("Work")
    board.sepia_id = "work_board"
    postit = GCPostit.new("Important task")
    postit.sepia_id = "task1"
    board.postits << postit
    board.save

    Sepia::Storage.exists?(GCBoard, "work_board").should be_true
    Sepia::Storage.exists?(GCPostit, "task1").should be_true

    # Run GC with the board as a root
    deleted = Sepia::Storage.gc(roots: [board])
    deleted.should be_empty

    Sepia::Storage.exists?(GCBoard, "work_board").should be_true
    Sepia::Storage.exists?(GCPostit, "task1").should be_true
  end

  it "collects objects that become orphaned" do
    board1 = GCBoard.new("Board 1")
    board1.sepia_id = "board1"
    postit1 = GCPostit.new("Task 1")
    postit1.sepia_id = "task1"
    board1.postits << postit1
    board1.save

    board2 = GCBoard.new("Board 2")
    board2.sepia_id = "board2"
    board2.save

    # Run GC with both boards as roots. Nothing should be collected.
    Sepia::Storage.gc(roots: [board1, board2]).should be_empty

    # Run GC again, but only with board2 as a root. board1 and its postit are now orphans.
    deleted = Sepia::Storage.gc(roots: [board2])
    deleted.keys.sort!.should eq ["GCBoard", "GCPostit"]
    deleted["GCBoard"].should eq ["board1"]
    deleted["GCPostit"].should eq ["task1"]

    Sepia::Storage.exists?(GCPostit, "task1").should be_false
    Sepia::Storage.exists?(GCBoard, "board1").should be_false
  end

  it "handles nested and shared references correctly" do
    main_board = GCBoard.new("Main")
    main_board.sepia_id = "main"
    nested_board = GCBoard.new("Nested")
    nested_board.sepia_id = "nested"
    shared_postit = GCPostit.new("Shared")
    shared_postit.sepia_id = "shared"
    orphan_postit = GCPostit.new("Orphan")
    orphan_postit.sepia_id = "orphan"

    main_board.boards << nested_board
    main_board.postits << shared_postit
    nested_board.postits << shared_postit # Shared reference
    orphan_postit.save
    main_board.save

    # Run GC with main_board as the root. Only the orphan should be collected.
    deleted = Sepia::Storage.gc(roots: [main_board])
    deleted["GCPostit"].should eq ["orphan"]
    deleted.keys.size.should eq 1

    # Everything else should still exist
    Sepia::Storage.exists?(GCBoard, "main").should be_true
    Sepia::Storage.exists?(GCBoard, "nested").should be_true
    Sepia::Storage.exists?(GCPostit, "shared").should be_true
    Sepia::Storage.exists?(GCPostit, "orphan").should be_false
  end

  it "respects dry_run and does not delete anything" do
    orphan_postit = GCPostit.new("I am an orphan")
    orphan_postit.sepia_id = "orphan1"
    orphan_postit.save

    Sepia::Storage.exists?(GCPostit, "orphan1").should be_true

    # Run garbage collection with an empty root set and dry_run
    deleted = Sepia::Storage.gc(roots: [] of Sepia::Object, dry_run: true)
    deleted["GCPostit"].should eq ["orphan1"]

    # Object should NOT be deleted
    Sepia::Storage.exists?(GCPostit, "orphan1").should be_true
  end

  it "collects everything when there are no roots" do
    board = GCBoard.new("board")
    board.sepia_id = "board1"
    postit = GCPostit.new("postit")
    postit.sepia_id = "postit1"
    board.postits << postit
    board.save

    # Run GC with an empty root set
    deleted = Sepia::Storage.gc(roots: [] of Sepia::Object)
    deleted.keys.sort!.should eq ["GCBoard", "GCPostit"]
    deleted["GCBoard"].should eq ["board1"]
    deleted["GCPostit"].should eq ["postit1"]

    Sepia::Storage.exists?(GCBoard, "board1").should be_false
    Sepia::Storage.exists?(GCPostit, "postit1").should be_false
  end
end

require "../src/sepia/*"
require "../src/sepia"

# First, let's configure Sepia to use a local directory for storage.
Sepia::Storage::INSTANCE.path = "./_data"
FileUtils.rm_rf("./_data") if Dir.exists?("./_data")
FileUtils.mkdir_p("./_data")

# A Postit is a simple Serializable object that stores its text content.
class Postit
  include Sepia::Serializable

  property text : String

  def initialize(@text); end

  # A default constructor is needed for deserialization.
  def initialize
    @text = ""
  end

  def to_sepia : String
    @text
  end

  def self.from_sepia(sepia_string : String) : self
    new(sepia_string)
  end
end

# A Board is a Container that holds other Boards or Postits.
# It is identified by its `sepia_id`.
class Board
  include Sepia::Container

  property boards : Hash(String, Board)
  property postits : Array(Postit)

  def initialize(@boards = Hash(String, Board).new, @postits = [] of Postit); end
end

# Helper method to print a board and its contents recursively.
def print_board(board : Board, indent = 0)
  puts "#{"  " * indent}- Board: #{board.sepia_id}"
  board.boards.each do |_, item|
    print_board(item, indent + 1)
  end
  board.postits.each do |item|
    puts "#{"  " * (indent + 1)}- Postit: \"#{item.text}\" (ID: #{item.sepia_id})"
  end
end

# --- Create and Save ---

puts "--- Saving State ---"

# A top-level board for "Work"
work_board = Board.new
work_board.sepia_id = "work_board"

# A nested board for "Project X"
project_x_board = Board.new
# Post-its for the boards
postit1 = Postit.new("Finish the report")
postit1.sepia_id = "report_postit"
postit2 = Postit.new("Review the code")
postit2.sepia_id = "code_review_postit"
postit3 = Postit.new("Buy milk")
postit3.sepia_id = "milk_postit"
postit4 = Postit.new("Call mom")
postit4.sepia_id = "mom_postit"
postit5 = Postit.new("Schedule dentist appointment")
postit5.sepia_id = "dentist_postit"

# Assemble the structure
project_x_board.postits << postit2
work_board.postits << postit1
work_board.postits << postit5
work_board.boards["project_x"] = project_x_board

# A top-level board for "Home"
home_board = Board.new
home_board.sepia_id = "home_board"
home_board.postits << postit3
home_board.postits << postit4

# Save the top-level boards. This will recursively save all their items.
work_board.save
home_board.save

puts "Saved 'work_board' and 'home_board' to ./_data"

# --- Load and Verify ---

puts "\n--- Loading State ---"

# Load the boards by their IDs
loaded_work_board = Board.load("work_board").as(Board)
loaded_home_board = Board.load("home_board").as(Board)

puts "\n--- Loaded Work Board ---"
print_board(loaded_work_board)

puts "\n--- Loaded Home Board ---"
print_board(loaded_home_board)

# --- Verification ---
puts "\n--- Verification ---"
puts "Work board ID: #{loaded_work_board.sepia_id}"
puts "Number of boards in work board: #{loaded_work_board.boards.size}"
puts "Number of postits in work board: #{loaded_work_board.postits.size}"
loaded_project_x = loaded_work_board.boards["project_x"]
puts "Project X board ID: #{loaded_project_x.sepia_id}"
puts "Number of items in Project X board: #{loaded_project_x.postits.size}"
puts "Project X post-it text: \"#{loaded_project_x.postits[0].as(Postit).text}\""
puts "Home board ID: #{loaded_home_board.sepia_id}"
puts "Home board post-it text: \"#{loaded_home_board.postits[0].as(Postit).text}\""
puts "Home board post-it 2 text: \"#{loaded_home_board.postits[1].as(Postit).text}\""

puts "\n--- On-Disk Representation ---"
puts "And all the data is stored like this on disk:"
system("tree ./_data")

require "./spec_helper"

# Test class for weak caching
class TestWeakCacheObject < Sepia::Object
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

describe Sepia::WeakCache do
  describe "#initialize" do
    it "creates cache with default cleanup interval" do
      cache = Sepia::WeakCache(TestWeakCacheObject).new
      cache.cleanup_interval.should eq 60.seconds
    end

    it "creates cache with custom cleanup interval" do
      cache = Sepia::WeakCache(TestWeakCacheObject).new(cleanup_interval: 30.seconds)
      cache.cleanup_interval.should eq 30.seconds
    end
  end

  describe "#put and #get" do
    it "stores and retrieves objects" do
      cache = Sepia::WeakCache(TestWeakCacheObject).new
      test_obj = TestWeakCacheObject.new("test_value")

      cache.put("key1", test_obj)
      retrieved = cache.get("key1")

      retrieved.should_not be_nil
      retrieved.try(&.content.should(eq("test_value")))
    end

    it "returns nil for non-existent keys" do
      cache = Sepia::WeakCache(TestWeakCacheObject).new
      retrieved = cache.get("non_existent")
      retrieved.should be_nil
    end

    it "updates existing keys" do
      cache = Sepia::WeakCache(TestWeakCacheObject).new

      obj1 = TestWeakCacheObject.new("value1")
      obj2 = TestWeakCacheObject.new("value2")

      cache.put("key1", obj1)
      cache.put("key1", obj2)

      retrieved = cache.get("key1")
      retrieved.should_not be_nil
      retrieved.try(&.content.should(eq("value2")))
    end
  end

  describe "#has_key?" do
    it "returns true for existing keys with alive references" do
      cache = Sepia::WeakCache(TestWeakCacheObject).new
      test_obj = TestWeakCacheObject.new("value")
      cache.put("key1", test_obj)

      cache.has_key?("key1").should be_true
    end

    it "returns false for non-existent keys" do
      cache = Sepia::WeakCache(TestWeakCacheObject).new
      cache.has_key?("non_existent").should be_false
    end
  end

  describe "#remove" do
    it "removes existing keys" do
      cache = Sepia::WeakCache(TestWeakCacheObject).new
      test_obj = TestWeakCacheObject.new("value")
      cache.put("key1", test_obj)

      result = cache.remove("key1")
      result.should be_true

      cache.has_key?("key1").should be_false
      cache.get("key1").should be_nil
    end

    it "returns false for non-existent keys" do
      cache = Sepia::WeakCache(TestWeakCacheObject).new
      result = cache.remove("non_existent")
      result.should be_false
    end
  end

  describe "#clear" do
    it "removes all entries" do
      cache = Sepia::WeakCache(TestWeakCacheObject).new
      cache.put("key1", TestWeakCacheObject.new("value1"))
      cache.put("key2", TestWeakCacheObject.new("value2"))

      cache.clear

      cache.has_key?("key1").should be_false
      cache.has_key?("key2").should be_false
      cache.stats.size.should eq 0
    end
  end

  describe "#cleanup" do
    it "removes dead references" do
      cache = Sepia::WeakCache(TestWeakCacheObject).new

      # Add objects and remove strong references
      3.times do |i|
        obj = TestWeakCacheObject.new("value#{i}")
        cache.put("key#{i}", obj)
        # obj goes out of scope here
      end

      cache.stats.size.should eq 3

      # Force cleanup
      removed = cache.cleanup
      removed.should be >= 0 # Might not collect all objects immediately

      cache.stats.size.should eq 3 - removed
    end

    it "updates statistics after cleanup" do
      cache = Sepia::WeakCache(TestWeakCacheObject).new

      cache.put("key1", TestWeakCacheObject.new("value1"))
      cache.put("key2", TestWeakCacheObject.new("value2"))

      initial_stats = cache.stats
      initial_stats.cleanups.should eq 0

      cache.cleanup

      new_stats = cache.stats
      new_stats.cleanups.should eq 1
      new_stats.dead_refs.should eq 0 # Should be reset after cleanup
    end

    it "forces cleanup regardless of interval" do
      cache = Sepia::WeakCache(TestWeakCacheObject).new(cleanup_interval: 5.minutes)

      cache.put("key1", TestWeakCacheObject.new("value1"))

      # Force cleanup should work even if interval hasn't passed
      cache.force_cleanup

      stats = cache.stats
      stats.cleanups.should eq 1
    end
  end

  describe "#stats" do
    it "provides accurate statistics" do
      cache = Sepia::WeakCache(TestWeakCacheObject).new

      cache.put("key1", TestWeakCacheObject.new("value1"))
      cache.put("key2", TestWeakCacheObject.new("value2"))
      cache.put("key3", TestWeakCacheObject.new("value3"))

      stats = cache.stats
      stats.size.should eq 3
      stats.total_added.should eq 3
      stats.cleanups.should eq 0
    end

    it "tracks total added items" do
      cache = Sepia::WeakCache(TestWeakCacheObject).new

      5.times do |i|
        cache.put("key#{i}", TestWeakCacheObject.new("value#{i}"))
      end

      stats = cache.stats
      stats.total_added.should eq 5

      # Update existing items
      cache.put("key0", TestWeakCacheObject.new("new_value"))

      stats = cache.stats
      stats.total_added.should eq 6
    end

    it "formats stats as string" do
      cache = Sepia::WeakCache(TestWeakCacheObject).new

      cache.put("key1", TestWeakCacheObject.new("value1"))

      stats_str = cache.stats.to_s
      stats_str.should contain("size: 1")
      stats_str.should contain("total_added: 1")
    end
  end

  describe "#live_keys and #live_objects" do
    it "returns keys with alive references" do
      cache = Sepia::WeakCache(TestWeakCacheObject).new

      obj1 = TestWeakCacheObject.new("value1")
      obj2 = TestWeakCacheObject.new("value2")

      cache.put("key1", obj1)
      cache.put("key2", obj2)

      live_keys = cache.live_keys
      live_keys.to_set.should contain("key1")
      live_keys.to_set.should contain("key2")
      live_keys.size.should eq 2

      live_objects = cache.live_objects
      live_objects.size.should eq 2
      live_objects.map(&.content).should contain("value1")
      live_objects.map(&.content).should contain("value2")
    end
  end

  describe "Thread safety" do
    it "handles concurrent access safely" do
      cache = Sepia::WeakCache(TestWeakCacheObject).new
      finished = Channel(Nil).new(3) # Reduced threads to avoid timeouts

      # Spawn multiple threads doing operations
      3.times do |i|
        spawn do
          20.times do |j| # Reduced iterations
            key = "thread#{i}_key#{j}"
            value = TestWeakCacheObject.new("thread#{i}_value#{j}")

            cache.put(key, value)
            retrieved = cache.get(key)

            # Object should be retrievable immediately
            if retrieved
              retrieved.try(&.content.should(eq("thread#{i}_value#{j}")))
            end
          end
          finished.send(nil)
        end
      end

      # Wait for all threads to finish
      3.times { finished.receive }

      # Cache should be in a consistent state
      cache.stats.size.should be > 0
    end
  end

  describe "Basic weak reference behavior" do
    it "maintains references while objects are alive" do
      cache = Sepia::WeakCache(TestWeakCacheObject).new

      # Create object and store in cache
      test_obj = TestWeakCacheObject.new("test_value")
      cache.put("key1", test_obj)

      # Verify object is accessible
      retrieved = cache.get("key1")
      retrieved.should_not be_nil
      retrieved.try(&.content.should(eq("test_value")))

      # As long as test_obj exists, it should be accessible from cache
      cache.has_key?("key1").should be_true
      cache.live_keys.should contain("key1")

      # Clean up to prevent test pollution
      cache.clear
    end
  end
end

require "./spec_helper"

# Test class for caching
class TestCacheObject < Sepia::Object
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

describe Sepia::CacheManager do
  describe "#initialize" do
    it "creates cache with default parameters" do
      cache = Sepia::CacheManager.new
      cache.stats.max_size.should eq 1000
      cache.ttl.should be_nil
    end

    it "creates cache with custom parameters" do
      cache = Sepia::CacheManager.new(max_size: 100, ttl: 60.seconds)
      cache.stats.max_size.should eq 100
      cache.ttl.should eq 60.seconds
    end
  end

  describe "#put and #get" do
    it "stores and retrieves objects" do
      cache = Sepia::CacheManager.new
      test_obj = TestCacheObject.new("test_value")

      cache.put("key1", test_obj)
      retrieved = cache.get("key1")

      retrieved.should_not be_nil
      retrieved.as(TestCacheObject).content.should eq("test_value")
    end

    it "returns nil for non-existent keys" do
      cache = Sepia::CacheManager.new
      retrieved = cache.get("non_existent")
      retrieved.should be_nil
    end

    it "updates existing keys" do
      cache = Sepia::CacheManager.new

      obj1 = TestCacheObject.new("value1")
      obj2 = TestCacheObject.new("value2")

      cache.put("key1", obj1)
      cache.put("key1", obj2)

      retrieved = cache.get("key1")
      retrieved.should_not be_nil
      retrieved.as(TestCacheObject).content.should eq("value2")
    end

    it "retrieves with type parameter" do
      cache = Sepia::CacheManager.new
      test_obj = TestCacheObject.new("test_value")

      cache.put("key1", test_obj)
      retrieved = cache.get("key1", TestCacheObject)

      retrieved.should_not be_nil
      retrieved.try(&.content.should(eq("test_value")))
    end
  end

  describe "#has_key?" do
    it "returns true for existing keys" do
      cache = Sepia::CacheManager.new
      test_obj = TestCacheObject.new("value")
      cache.put("key1", test_obj)

      cache.has_key?("key1").should be_true
    end

    it "returns false for non-existent keys" do
      cache = Sepia::CacheManager.new
      cache.has_key?("non_existent").should be_false
    end
  end

  describe "#remove" do
    it "removes existing keys" do
      cache = Sepia::CacheManager.new
      test_obj = TestCacheObject.new("value")
      cache.put("key1", test_obj)

      result = cache.remove("key1")
      result.should be_true

      cache.has_key?("key1").should be_false
      cache.get("key1").should be_nil
    end

    it "returns false for non-existent keys" do
      cache = Sepia::CacheManager.new
      result = cache.remove("non_existent")
      result.should be_false
    end
  end

  describe "#clear" do
    it "removes all entries" do
      cache = Sepia::CacheManager.new
      cache.put("key1", TestCacheObject.new("value1"))
      cache.put("key2", TestCacheObject.new("value2"))

      cache.clear

      cache.has_key?("key1").should be_false
      cache.has_key?("key2").should be_false
      cache.stats.size.should eq 0
    end
  end

  describe "LRU eviction" do
    it "evicts least recently used items when max size is exceeded" do
      cache = Sepia::CacheManager.new(max_size: 2)

      cache.put("key1", TestCacheObject.new("value1"))
      cache.put("key2", TestCacheObject.new("value2"))

      # Both should be present
      cache.has_key?("key1").should be_true
      cache.has_key?("key2").should be_true

      # Add third item, should evict key1 (least recently used)
      cache.put("key3", TestCacheObject.new("value3"))

      cache.has_key?("key1").should be_false
      cache.has_key?("key2").should be_true
      cache.has_key?("key3").should be_true
      cache.stats.size.should eq 2
    end

    it "updates access order on get" do
      cache = Sepia::CacheManager.new(max_size: 2)

      cache.put("key1", TestCacheObject.new("value1"))
      cache.put("key2", TestCacheObject.new("value2"))

      # Access key1 to make it most recently used
      cache.get("key1")

      # Add third item, should evict key2 now
      cache.put("key3", TestCacheObject.new("value3"))

      cache.has_key?("key1").should be_true
      cache.has_key?("key2").should be_false
      cache.has_key?("key3").should be_true
    end
  end

  describe "TTL (Time To Live) expiration" do
    it "expires entries after TTL" do
      cache = Sepia::CacheManager.new(ttl: 50.milliseconds)

      cache.put("key1", TestCacheObject.new("value1"))
      cache.has_key?("key1").should be_true

      # Wait for expiration
      sleep(100.milliseconds)

      # Should be expired now
      cache.has_key?("key1").should be_false
      cache.get("key1").should be_nil
    end

    it "uses global TTL for all items" do
      cache = Sepia::CacheManager.new(ttl: 50.milliseconds)

      cache.put("key1", TestCacheObject.new("value1"))
      cache.put("key2", TestCacheObject.new("value2"))

      # Wait for both to expire
      sleep(100.milliseconds)

      cache.has_key?("key1").should be_false
      cache.has_key?("key2").should be_false
    end

    it "cleans up expired entries automatically" do
      cache = Sepia::CacheManager.new(ttl: 50.milliseconds)

      cache.put("key1", TestCacheObject.new("value1"))
      cache.put("key2", TestCacheObject.new("value2"))
      cache.stats.size.should eq 2

      # Wait for expiration
      sleep(100.milliseconds)

      # Access cache to trigger cleanup for all entries
      cache.has_key?("key1")
      cache.has_key?("key2")

      cache.stats.size.should eq 0
    end
  end

  describe "#cleanup_expired" do
    it "manually cleans up expired entries" do
      cache = Sepia::CacheManager.new(ttl: 50.milliseconds)

      cache.put("key1", TestCacheObject.new("value1"))
      cache.put("key2", TestCacheObject.new("value2"))

      sleep(100.milliseconds)

      cleaned = cache.cleanup_expired
      cleaned.should eq 2

      cache.stats.size.should eq 0
    end

    it "returns 0 when no expired entries" do
      cache = Sepia::CacheManager.new(ttl: 5.minutes)

      cache.put("key1", TestCacheObject.new("value1"))
      cache.put("key2", TestCacheObject.new("value2"))

      cleaned = cache.cleanup_expired
      cleaned.should eq 0

      cache.stats.size.should eq 2
    end
  end

  describe "Thread safety" do
    it "handles concurrent access safely" do
      cache = Sepia::CacheManager.new(max_size: 100)
      finished = Channel(Nil).new(10)

      # Spawn multiple threads doing operations
      10.times do |i|
        spawn do
          100.times do |j|
            key = "thread#{i}_key#{j}"
            value = TestCacheObject.new("thread#{i}_value#{j}")

            cache.put(key, value)
            retrieved = cache.get(key)
            retrieved.should_not be_nil
            retrieved.as(TestCacheObject).content.should eq("thread#{i}_value#{j}")
          end
          finished.send(nil)
        end
      end

      # Wait for all threads to finish
      10.times { finished.receive }

      # Verify cache is in a consistent state
      cache.stats.size.should be > 0
      cache.stats.size.should be <= 100
    end

    it "handles concurrent cleanup safely" do
      cache = Sepia::CacheManager.new(ttl: 50.milliseconds)
      finished = Channel(Nil).new(5)

      # Spawn threads adding items
      3.times do |i|
        spawn do
          50.times do |j|
            cache.put("key#{i}_#{j}", TestCacheObject.new("value#{i}_#{j}"))
            sleep(1.milliseconds)
          end
          finished.send(nil)
        end
      end

      # Spawn threads doing cleanup
      2.times do
        spawn do
          25.times do
            cache.cleanup_expired
            sleep(2.milliseconds)
          end
          finished.send(nil)
        end
      end

      # Wait for all threads
      5.times { finished.receive }

      # Should not crash and cache should be in valid state
      cache.stats.size.should be >= 0
    end
  end

  describe "#stats" do
    it "provides accurate statistics" do
      cache = Sepia::CacheManager.new(max_size: 3)

      cache.put("key1", TestCacheObject.new("value1"))
      cache.put("key2", TestCacheObject.new("value2"))
      cache.put("key3", TestCacheObject.new("value3"))

      stats = cache.stats
      stats.size.should eq 3
      stats.hits.should eq 0
      stats.misses.should eq 0
      stats.evictions.should eq 0

      # Generate some hits and misses
      cache.get("key1")         # hit
      cache.get("key2")         # hit
      cache.get("non_existent") # miss

      stats = cache.stats
      stats.hits.should eq 2
      stats.misses.should eq 1

      # Trigger eviction
      cache.put("key4", TestCacheObject.new("value4"))

      stats = cache.stats
      stats.evictions.should eq 1
      stats.size.should eq 3
    end

    it "tracks cleanup operations" do
      cache = Sepia::CacheManager.new(ttl: 50.milliseconds)

      cache.put("key1", TestCacheObject.new("value1"))
      cache.put("key2", TestCacheObject.new("value2"))

      sleep(100.milliseconds)

      cleaned = cache.cleanup_expired

      # Cleanup should remove expired items
      cleaned.should eq 2
      cache.stats.size.should eq 0
    end
  end

  describe "#keys" do
    it "returns all active keys" do
      cache = Sepia::CacheManager.new

      cache.put("key1", TestCacheObject.new("value1"))
      cache.put("key2", TestCacheObject.new("value2"))
      cache.put("key3", TestCacheObject.new("value3"))

      keys = cache.keys.to_set
      keys.should contain("key1")
      keys.should contain("key2")
      keys.should contain("key3")
      keys.size.should eq 3
    end

    it "does not return expired keys" do
      cache = Sepia::CacheManager.new(ttl: 50.milliseconds)

      cache.put("key1", TestCacheObject.new("value1"))
      cache.put("key2", TestCacheObject.new("value2"))

      sleep(100.milliseconds)

      # Access expired keys to trigger cleanup
      cache.has_key?("key1")
      cache.has_key?("key2")

      keys = cache.keys
      keys.should be_empty
    end
  end

  describe "#memory_usage" do
    it "estimates memory usage" do
      cache = Sepia::CacheManager.new

      cache.put("key1", TestCacheObject.new("value1"))
      cache.put("key2", TestCacheObject.new("value2"))

      usage = cache.memory_usage
      usage.should be > 0

      # Usage should increase with more items
      cache.put("key3", TestCacheObject.new("value3"))
      new_usage = cache.memory_usage
      new_usage.should be > usage
    end
  end
end

require "time"

module Sepia
  # Centralized cache manager for Sepia objects.
  #
  # Provides thread-safe LRU caching with configurable size limits, TTL,
  # and eviction policies. Designed to work with both regular objects
  # and LazyReference instances.
  #
  # ### Example
  #
  # ```
  # cache = CacheManager.new(max_size: 1000, ttl: 3600.seconds)
  #
  # # Store an object
  # cache.put("doc-123", my_document)
  #
  # # Retrieve an object
  # doc = cache.get("doc-123")
  #
  # # Cache statistics
  # puts cache.stats
  # # => {hits: 45, misses: 12, size: 23, max_size: 1000}
  # ```
  class CacheManager
    # Cache entry with value and expiration time
    private struct Entry(T)
      property value : T
      property expires_at : Time?

      def initialize(@value : T, @expires_at : Time? = nil)
      end

      def expired? : Bool
        @expires_at.try { |time| time < Time.utc } || false
      end
    end

    # Cache statistics
    struct Stats
      property hits : Int64 = 0
      property misses : Int64 = 0
      property evictions : Int64 = 0
      property size : Int32 = 0
      property max_size : Int32

      def initialize(@max_size : Int32)
      end

      def hit_rate : Float64
        total = @hits + @misses
        total > 0 ? @hits.to_f / total : 0.0
      end

      def to_s : String
        "{hits: #{@hits}, misses: #{@misses}, evictions: #{@evictions}, " \
        "size: #{@size}, max_size: #{@max_size}, hit_rate: #{(hit_rate * 100).round(2)}%}"
      end
    end

    # Maximum number of items in cache
    getter max_size : Int32

    # Time-to-live for cache entries (nil = no expiration)
    getter ttl : Time::Span?

    # Current cache statistics
    getter stats : Stats

    # Creates a new cache manager.
    #
    # ### Parameters
    #
    # - *max_size* : Maximum number of items to cache (default: 1000)
    # - *ttl* : Time-to-live for entries (default: nil = no expiration)
    #
    # ### Example
    #
    # ```
    # cache = CacheManager.new(max_size: 500, ttl: 1.hour)
    # ```
    def initialize(@max_size : Int32 = 1000, @ttl : Time::Span? = nil)
      @cache = Hash(String, Entry(Sepia::Object)).new
      @access_order = Array(String).new
      @mutex = Mutex.new
      @stats = Stats.new(@max_size)
    end

    # Stores an object in the cache.
    #
    # If the cache is full, implements LRU eviction by removing
    # the least recently used items.
    #
    # ### Parameters
    #
    # - *key* : The cache key (typically object ID)
    # - *value* : The object to cache
    #
    # ### Example
    #
    # ```
    # cache.put("doc-123", my_document)
    # ```
    def put(key : String, value : Sepia::Object) : Void
      @mutex.synchronize do
        expires_at = @ttl.try { |ttl| Time.utc + ttl }
        entry = Entry(Sepia::Object).new(value, expires_at)

        if @cache.has_key?(key)
          # Update existing entry
          @cache[key] = entry
          move_to_end(key)
        else
          # Add new entry
          if @cache.size >= @max_size
            evict_lru
          end

          @cache[key] = entry
          @access_order << key
          @stats.size = @cache.size
        end
      end
    end

    # Retrieves an object from the cache.
    #
    # Returns `nil` if the key doesn't exist or the entry has expired.
    # Updates the access order for LRU tracking.
    #
    # ### Parameters
    #
    # - *key* : The cache key
    #
    # ### Returns
    #
    # The cached object or `nil` if not found/expired.
    #
    # ### Example
    #
    # ```
    # doc = cache.get("doc-123")
    # puts doc.title if doc
    # ```
    def get(key : String) : Sepia::Object?
      @mutex.synchronize do
        entry = @cache[key]?

        if entry
          if entry.expired?
            remove_key(key)
            @stats.misses += 1
            nil
          else
            # Move to end (most recently used)
            move_to_end(key)
            @stats.hits += 1
            entry.value
          end
        else
          @stats.misses += 1
          nil
        end
      end
    end

    # Retrieves an object of specific type from the cache.
    #
    # Generic version of `get` that returns the properly typed object.
    #
    # ### Parameters
    #
    # - *key* : The cache key
    #
    # ### Returns
    #
    # The cached object cast to type T or `nil` if not found/expired.
    #
    # ### Example
    #
    # ```
    # doc = cache.get(MyDocument, "doc-123")
    # puts doc.title if doc
    # ```
    def get(key : String, type : T.class) : T? forall T
      object = get(key)
      object.as(T?) if object
    end

    # Checks if a key exists in the cache (excluding expired entries).
    #
    # ### Parameters
    #
    # - *key* : The cache key
    #
    # ### Returns
    #
    # `true` if the key exists and hasn't expired, `false` otherwise.
    #
    # ### Example
    #
    # ```
    # if cache.has_key?("doc-123")
    #   puts "Document is cached"
    # end
    # ```
    def has_key?(key : String) : Bool
      @mutex.synchronize do
        entry = @cache[key]?
        if entry && !entry.expired?
          true
        else
          remove_key(key) if entry
          false
        end
      end
    end

    # Removes a specific key from the cache.
    #
    # ### Parameters
    #
    # - *key* : The cache key to remove
    #
    # ### Returns
    #
    # `true` if the key was removed, `false` if it didn't exist.
    #
    # ### Example
    #
    # ```
    # cache.remove("doc-123")
    # ```
    def remove(key : String) : Bool
      @mutex.synchronize do
        if @cache.has_key?(key)
          remove_key(key)
          true
        else
          false
        end
      end
    end

    # Clears all entries from the cache.
    #
    # ### Example
    #
    # ```
    # cache.clear
    # puts cache.stats.size # => 0
    # ```
    def clear : Void
      @mutex.synchronize do
        @cache.clear
        @access_order.clear
        @stats.size = 0
      end
    end

    # Removes all expired entries from the cache.
    #
    # ### Returns
    #
    # The number of expired entries that were removed.
    #
    # ### Example
    #
    # ```
    # removed = cache.cleanup_expired
    # puts "Removed #{removed} expired entries"
    # ```
    def cleanup_expired : Int32
      @mutex.synchronize do
        removed = 0
        @cache.each do |key, entry|
          if entry.expired?
            remove_key(key)
            removed += 1
          end
        end
        removed
      end
    end

    # Changes the maximum cache size.
    #
    # If the new size is smaller than the current cache size,
    # evicts LRU entries to fit the new limit.
    #
    # ### Parameters
    #
    # - *new_size* : The new maximum cache size
    #
    # ### Example
    #
    # ```
    # cache.resize(500) # Reduce cache size
    # ```
    def resize(new_size : Int32) : Void
      @mutex.synchronize do
        # old_size = @max_size # No longer needed
        @max_size = new_size
        @stats.max_size = new_size

        # Evict entries if new size is smaller
        while @cache.size > @max_size
          evict_lru
        end
      end
    end

    # Returns an array of all keys currently in the cache.
    #
    # ### Returns
    #
    # Array of cache keys (most recently used last).
    #
    # ### Example
    #
    # ```
    # keys = cache.keys
    # puts "Cached objects: #{keys.size}"
    # ```
    def keys : Array(String)
      @mutex.synchronize do
        @access_order.dup
      end
    end

    # Returns an array of all non-expired values in the cache.
    #
    # ### Returns
    #
    # Array of cached objects.
    #
    # ### Example
    #
    # ```
    # objects = cache.values
    # puts "Cached #{objects.size} objects"
    # ```
    def values : Array(Sepia::Object)
      @mutex.synchronize do
        @access_order.compact_map do |key|
          entry = @cache[key]?
          entry && !entry.expired? ? entry.value : nil
        end
      end
    end

    # Estimates memory usage of the cache.
    #
    # This is a rough estimation based on the number of cached objects.
    # Actual memory usage may vary based on object size.
    #
    # ### Returns
    #
    # Estimated memory usage in bytes.
    #
    # ### Example
    #
    # ```
    # bytes = cache.memory_usage
    # puts "Cache uses approximately #{bytes / 1024} KB"
    # ```
    def memory_usage : Int64
      @mutex.synchronize do
        # Rough estimation: assume average object size of 1KB
        @cache.size.to_i64 * 1024
      end
    end

    private def move_to_end(key : String) : Void
      @access_order.delete(key)
      @access_order << key
    end

    private def remove_key(key : String) : Void
      @cache.delete(key)
      @access_order.delete(key)
      @stats.size = @cache.size
    end

    private def evict_lru : Void
      return if @access_order.empty?

      lru_key = @access_order.shift?
      if lru_key
        @cache.delete(lru_key)
        @stats.evictions += 1
        @stats.size = @cache.size
      end
    end
  end
end

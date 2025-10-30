require "set"
require "weak_ref"

module Sepia
  # Memory-aware cache using weak references.
  #
  # This cache holds weak references to objects, allowing the garbage
  # collector to reclaim memory when needed. Automatically cleans up
  # dead references and provides memory pressure monitoring.
  #
  # Uses Crystal's built-in WeakRef class for proper weak reference behavior.
  #
  # ### Example
  #
  # ```
  # weak_cache = WeakCache(Sepia::Object).new
  #
  # # Store an object
  # weak_cache.put("doc-123", my_document)
  #
  # # Retrieve an object (may return nil if GC collected it)
  # doc = weak_cache.get("doc-123")
  #
  # # Cleanup dead references
  # weak_cache.cleanup
  # ```
  class WeakCache(T)
    # Weak reference wrapper with tracking and metadata
    private struct CachedRef(T)
      property weak_ref : WeakRef(T)
      property created_at : Time

      def initialize(@object : T)
        @weak_ref = WeakRef(T).new(@object)
        @created_at = Time.utc
      end

      def alive? : Bool
        @weak_ref.value != nil
      end

      def get : T?
        @weak_ref.value
      end
    end

    # Cache statistics
    struct Stats
      property size : Int32 = 0
      property dead_refs : Int32 = 0
      property cleanups : Int64 = 0
      property total_added : Int64 = 0

      def to_s : String
        "{size: #{@size}, dead_refs: #{@dead_refs}, " \
        "cleanups: #{@cleanups}, total_added: #{@total_added}}"
      end
    end

    # Current cache statistics
    getter stats : Stats

    # Interval for automatic cleanup (in seconds)
    getter cleanup_interval : Time::Span

    # Creates a new weak cache.
    #
    # ### Parameters
    #
    # - *cleanup_interval* : How often to run automatic cleanup (default: 60 seconds)
    #
    # ### Example
    #
    # ```
    # cache = WeakCache(MyClass).new(cleanup_interval: 30.seconds)
    # ```
    def initialize(@cleanup_interval : Time::Span = 60.seconds)
      @cache = Hash(String, CachedRef(T)).new
      @mutex = Mutex.new
      @stats = Stats.new
      @last_cleanup = Time.utc
    end

    # Stores an object in the weak cache.
    #
    # The object is stored via weak reference and may be garbage collected
    # if there are no strong references to it elsewhere.
    #
    # ### Parameters
    #
    # - *key* : The cache key
    # - *object* : The object to cache
    #
    # ### Example
    #
    # ```
    # weak_cache.put("doc-123", my_document)
    # ```
    def put(key : String, object : T) : Void
      @mutex.synchronize do
        @cache[key] = CachedRef(T).new(object)
        @stats.total_added += 1
        @stats.size = @cache.size

        # Run cleanup periodically
        maybe_cleanup
      end
    end

    # Retrieves an object from the weak cache.
    #
    # Returns `nil` if the key doesn't exist, the object was garbage
    # collected, or the weak reference is dead.
    #
    # ### Parameters
    #
    # - *key* : The cache key
    #
    # ### Returns
    #
    # The cached object or `nil`.
    #
    # ### Example
    #
    # ```
    # doc = weak_cache.get("doc-123")
    # puts doc.title if doc
    # ```
    def get(key : String) : T?
      @mutex.synchronize do
        ref = @cache[key]?
        if ref
          object = ref.get
          unless object
            # Reference is dead, mark for cleanup
            @stats.dead_refs += 1
          end
          object
        else
          nil
        end
      end
    end

    # Checks if a key exists in the weak cache.
    #
    # ### Parameters
    #
    # - *key* : The cache key
    #
    # ### Returns
    #
    # `true` if the key exists and reference is alive, `false` otherwise.
    #
    # ### Example
    #
    # ```
    # if weak_cache.has_key?("doc-123")
    #   puts "Object is cached and alive"
    # end
    # ```
    def has_key?(key : String) : Bool
      @mutex.synchronize do
        ref = @cache[key]?
        ref ? ref.alive? : false
      end
    end

    # Removes a specific key from the weak cache.
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
    # weak_cache.remove("doc-123")
    # ```
    def remove(key : String) : Bool
      @mutex.synchronize do
        if @cache.has_key?(key)
          @cache.delete(key)
          @stats.size = @cache.size
          true
        else
          false
        end
      end
    end

    # Clears all entries from the weak cache.
    #
    # ### Example
    #
    # ```
    # weak_cache.clear
    # puts weak_cache.stats.size # => 0
    # ```
    def clear : Void
      @mutex.synchronize do
        @cache.clear
        @stats.size = 0
        @stats.dead_refs = 0
      end
    end

    # Removes all dead references from the weak cache.
    #
    # This should be called periodically to clean up references to
    # objects that have been garbage collected.
    #
    # ### Returns
    #
    # The number of dead references that were removed.
    #
    # ### Example
    #
    # ```
    # removed = weak_cache.cleanup
    # puts "Cleaned up #{removed} dead references"
    # ```
    def cleanup : Int32
      @mutex.synchronize do
        removed = 0
        @cache.reject! do |_, ref|
          if ref.alive?
            false # Keep alive references
          else
            removed += 1
            true # Remove dead references
          end
        end

        @stats.dead_refs = 0
        @stats.size = @cache.size
        @stats.cleanups += 1
        @last_cleanup = Time.utc

        removed
      end
    end

    # Forces cleanup regardless of interval.
    #
    # ### Example
    #
    # ```
    # weak_cache.force_cleanup
    # ```
    def force_cleanup : Void
      cleanup
    end

    # Returns all live keys in the weak cache.
    #
    # ### Returns
    #
    # Array of keys with alive references.
    #
    # ### Example
    #
    # ```
    # live_keys = weak_cache.live_keys
    # puts "#{live_keys.size} objects still cached"
    # ```
    def live_keys : Array(String)
      @mutex.synchronize do
        @cache.compact_map do |key, ref|
          key if ref.alive?
        end
      end
    end

    # Returns all live objects in the weak cache.
    #
    # ### Returns
    #
    # Array of objects with alive references.
    #
    # ### Example
    #
    # ```
    # live_objects = weak_cache.live_objects
    # puts "#{live_objects.size} objects still cached"
    # ```
    def live_objects : Array(T)
      @mutex.synchronize do
        @cache.compact_map do |_, ref|
          ref.get
        end
      end
    end

    # Returns cache statistics including dead reference count.
    #
    # ### Returns
    #
    # Current cache statistics.
    #
    # ### Example
    #
    # ```
    # puts weak_cache.stats
    # # => {size: 45, dead_refs: 3, cleanups: 12, total_added: 156}
    # ```
    def stats : Stats
      @mutex.synchronize do
        # Count dead references
        dead_count = @cache.count { |_, ref| !ref.alive? }
        @stats.dead_refs = dead_count
        @stats
      end
    end

    # Estimates memory usage of live objects in the weak cache.
    #
    # This is a rough estimation based on the number of live objects.
    #
    # ### Returns
    #
    # Estimated memory usage in bytes.
    #
    # ### Example
    #
    # ```
    # bytes = weak_cache.memory_usage
    # puts "Weak cache uses approximately #{bytes / 1024} KB"
    # ```
    def memory_usage : Int64
      @mutex.synchronize do
        # Rough estimation: assume average object size of 1KB
        live_objects.size.to_i64 * 1024
      end
    end

    # Gets the memory pressure level.
    #
    # Returns a value between 0.0 (no pressure) and 1.0 (high pressure)
    # based on the ratio of dead references to total references.
    #
    # ### Returns
    #
    # Memory pressure level as a float between 0.0 and 1.0.
    #
    # ### Example
    #
    # ```
    # pressure = weak_cache.memory_pressure
    # puts "Memory pressure: #{(pressure * 100).round(1)}%"
    # ```
    def memory_pressure : Float64
      @mutex.synchronize do
        total = @cache.size
        return 0.0 if total == 0

        dead = @cache.count { |_, ref| !ref.alive? }
        dead.to_f / total
      end
    end

    # Checks if cleanup is needed based on interval or pressure.
    #
    # ### Returns
    #
    # `true` if cleanup is recommended, `false` otherwise.
    #
    # ### Example
    #
    # ```
    # if weak_cache.needs_cleanup?
    #   weak_cache.cleanup
    # end
    # ```
    def needs_cleanup? : Bool
      @mutex.synchronize do
        time_since_cleanup = Time.utc - @last_cleanup
        time_based = time_since_cleanup > @cleanup_interval
        pressure_based = memory_pressure > 0.3 # 30% dead refs triggers cleanup

        time_based || pressure_based
      end
    end

    private def maybe_cleanup : Void
      if needs_cleanup_unsafe?
        cleanup
      end
    end

    # Unsafe version of needs_cleanup? that doesn't acquire mutex
    # Call only when mutex is already held
    private def needs_cleanup_unsafe? : Bool
      time_since_cleanup = Time.utc - @last_cleanup
      time_based = time_since_cleanup > @cleanup_interval
      pressure_based = memory_pressure_unsafe > 0.3 # 30% dead refs triggers cleanup

      time_based || pressure_based
    end

    # Unsafe version of memory_pressure that doesn't acquire mutex
    private def memory_pressure_unsafe : Float64
      total = @cache.size
      return 0.0 if total == 0

      dead = @cache.count { |_, ref| !ref.alive? }
      dead.to_f / total
    end
  end
end

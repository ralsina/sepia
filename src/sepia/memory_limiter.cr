require "file_utils"

module Sepia
  # Memory pressure detection and management system.
  #
  # Monitors system memory usage and provides signals for when
  # caches should be purged or memory-saving measures should be taken.
  # Works across different platforms (Linux, macOS, Windows).
  #
  # ### Example
  #
  # ```
  # limiter = MemoryLimiter.new(
  #   warning_threshold: "70%",
  #   critical_threshold: "85%",
  #   check_interval: 30.seconds
  # )
  #
  # limiter.on_warning { puts "Memory usage is high" }
  # limiter.on_critical { cache.clear }
  #
  # limiter.start_monitoring
  # ```
  class MemoryLimiter
    # Memory statistics snapshot
    struct MemoryStats
      property total_bytes : UInt64
      property used_bytes : UInt64
      property available_bytes : UInt64
      property usage_percent : Float64
      property timestamp : Time

      def initialize(@total_bytes, @used_bytes, @available_bytes, @usage_percent, @timestamp = Time.utc)
      end

      def to_s : String
        "{total: #{format_bytes(@total_bytes)}, used: #{format_bytes(@used_bytes)}, " \
        "available: #{format_bytes(@available_bytes)}, usage: #{@usage_percent.round(1)}%}"
      end

      private def format_bytes(bytes : UInt64) : String
        units = ["B", "KB", "MB", "GB", "TB"]
        size = bytes.to_f
        unit_index = 0

        while size >= 1024 && unit_index < units.size - 1
          size /= 1024
          unit_index += 1
        end

        "#{size.round(2)} #{units[unit_index]}"
      end
    end

    # Memory pressure levels
    enum PressureLevel
      Normal    # < warning_threshold
      Warning   # >= warning_threshold && < critical_threshold
      Critical  # >= critical_threshold
      Emergency # >= critical_threshold + 10%
    end

    # Memory usage thresholds
    getter warning_threshold : Float64
    getter critical_threshold : Float64
    getter emergency_threshold : Float64

    # Monitoring interval
    getter check_interval : Time::Span

    # Current memory statistics
    getter current_stats : MemoryStats

    # Event callbacks
    property on_warning : Proc(Nil)?
    property on_critical : Proc(Nil)?
    property on_emergency : Proc(Nil)?
    property on_normal : Proc(Nil)?

    # Monitoring state
    getter monitoring : Bool

    # Creates a new memory limiter.
    #
    # ### Parameters
    #
    # - *warning_threshold* : Memory usage percentage for warning (default: 0.7 = 70%)
    # - *critical_threshold* : Memory usage percentage for critical (default: 0.85 = 85%)
    # - *emergency_threshold* : Memory usage percentage for emergency (default: 0.95 = 95%)
    # - *check_interval* : How often to check memory usage (default: 30 seconds)
    #
    # ### Example
    #
    # ```
    # limiter = MemoryLimiter.new(
    #   warning_threshold: 0.75,
    #   critical_threshold: 0.90,
    #   check_interval: 60.seconds
    # )
    # ```
    def initialize(
      @warning_threshold : Float64 = 0.7,
      @critical_threshold : Float64 = 0.85,
      @emergency_threshold : Float64 = 0.95,
      @check_interval : Time::Span = 30.seconds,
    )
      @current_stats = MemoryStats.new(0_u64, 0_u64, 0_u64, 0.0)
      @current_pressure = PressureLevel::Normal
      @monitoring = false
      @monitor_thread = nil.as(Fiber?)
      @mutex = Mutex.new
    end

    # Starts monitoring memory usage in the background.
    #
    # Creates a fiber that periodically checks memory usage and
    # triggers callbacks based on threshold levels.
    #
    # ### Example
    #
    # ```
    # limiter.start_monitoring
    # ```
    def start_monitoring : Void
      @mutex.synchronize do
        return if @monitoring

        @monitoring = true
        @monitor_thread = spawn do
          while @monitoring
            check_memory
            sleep(@check_interval)
          end
        end
      end
    end

    # Stops monitoring memory usage.
    #
    # ### Example
    #
    # ```
    # limiter.stop_monitoring
    # ```
    def stop_monitoring : Void
      @mutex.synchronize do
        @monitoring = false
        @monitor_thread = nil
      end
    end

    # Forces an immediate memory check.
    #
    # Updates current statistics and triggers appropriate callbacks.
    #
    # ### Returns
    #
    # Current memory pressure level.
    #
    # ### Example
    #
    # ```
    # pressure = limiter.check_now
    # puts "Current pressure: #{pressure}"
    # ```
    def check_now : PressureLevel
      check_memory
      @current_pressure
    end

    # Gets the current memory pressure level.
    #
    # ### Returns
    #
    # Current pressure level without forcing a new check.
    #
    # ### Example
    #
    # ```
    # pressure = limiter.current_pressure
    # case pressure
    # when .warning?
    #   puts "Memory usage is high"
    # when .critical?
    #   puts "Memory usage is critical"
    # end
    # ```
    def current_pressure : PressureLevel
      @mutex.synchronize { @current_pressure }
    end

    # Checks if memory pressure is at warning level or higher.
    #
    # ### Returns
    #
    # `true` if usage >= warning_threshold, `false` otherwise.
    #
    # ### Example
    #
    # ```
    # if limiter.warning?
    #   cache.cleanup
    # end
    # ```
    def warning? : Bool
      @current_pressure.warning? || @current_pressure.critical? || @current_pressure.emergency?
    end

    # Checks if memory pressure is at critical level or higher.
    #
    # ### Returns
    #
    # `true` if usage >= critical_threshold, `false` otherwise.
    #
    # ### Example
    #
    # ```
    # if limiter.critical?
    #   cache.clear
    #   GC.collect
    # end
    # ```
    def critical? : Bool
      @current_pressure.critical? || @current_pressure.emergency?
    end

    # Checks if memory pressure is at emergency level.
    #
    # ### Returns
    #
    # `true` if usage >= emergency_threshold, `false` otherwise.
    #
    # ### Example
    #
    # ```
    # if limiter.emergency?
    #   raise "Out of memory!"
    # end
    # ```
    def emergency? : Bool
      @current_pressure.emergency?
    end

    # Gets a human-readable description of current memory state.
    #
    # ### Returns
    #
    # Description string.
    #
    # ### Example
    #
    # ```
    # puts limiter.status_description
    # # => "Memory usage: 2.3 GB of 8.0 GB (28.8%) - Normal"
    # ```
    def status_description : String
      @mutex.synchronize do
        "#{@current_stats.to_s} - #{@current_pressure}"
      end
    end

    # Suggests cache size based on current memory pressure.
    #
    # ### Parameters
    #
    # - *max_size* : Maximum desired cache size
    #
    # ### Returns
    #
    # Recommended cache size based on memory pressure.
    #
    # ### Example
    #
    # ```
    # recommended = limiter.suggest_cache_size(1000)
    # cache.resize(recommended)
    # ```
    def suggest_cache_size(max_size : Int32) : Int32
      case @current_pressure
      when .normal?
        max_size
      when .warning?
        (max_size * 0.7).to_i32
      when .critical?
        (max_size * 0.4).to_i32
      when .emergency?
        (max_size * 0.1).to_i32
      else
        max_size
      end
    end

    private def check_memory : Void
      @mutex.synchronize do
        stats = get_memory_stats
        @current_stats = stats

        old_pressure = @current_pressure
        @current_pressure = calculate_pressure(stats.usage_percent)

        # Trigger callbacks based on pressure changes
        trigger_callbacks(old_pressure, @current_pressure)
      end
    rescue ex
      # Log error but don't crash monitoring
      STDERR.puts "MemoryLimiter: Error checking memory: #{ex.message}"
    end

    private def calculate_pressure(usage_percent : Float64) : PressureLevel
      case usage_percent
      when .<(warning_threshold)
        PressureLevel::Normal
      when .<(critical_threshold)
        PressureLevel::Warning
      when .<(emergency_threshold)
        PressureLevel::Critical
      else
        PressureLevel::Emergency
      end
    end

    private def trigger_callbacks(old_pressure : PressureLevel, new_pressure : PressureLevel) : Void
      # Only trigger when pressure level changes
      return if old_pressure == new_pressure

      case new_pressure
      when .normal?
        @on_normal.try &.call
      when .warning?
        @on_warning.try &.call
      when .critical?
        @on_critical.try &.call
      when .emergency?
        @on_emergency.try &.call
      end
    end

    private def get_memory_stats : MemoryStats
      {% if flag?(:linux) %}
        get_linux_memory_stats
      {% elsif flag?(:darwin) %}
        get_macos_memory_stats
      {% else %}
        # Fallback for other platforms
        get_generic_memory_stats
      {% end %}
    end

    {% if flag?(:linux) %}
      private def get_linux_memory_stats : MemoryStats
        begin
          content = File.read("/proc/meminfo")
          total_kb = 0_u64
          available_kb = 0_u64

          content.each_line do |line|
            case line
            when /^MemTotal:\s+(\d+)\s+kB/
              total_kb = $1.to_u64
            when /^MemAvailable:\s+(\d+)\s+kB/
              available_kb = $1.to_u64
            end
          end

          used_kb = total_kb - available_kb
          total_bytes = total_kb * 1024
          used_bytes = used_kb * 1024
          available_bytes = available_kb * 1024
          usage_percent = total_bytes > 0 ? (used_bytes.to_f / total_bytes * 100) : 0.0

          MemoryStats.new(total_bytes, used_bytes, available_bytes, usage_percent)
        rescue
          get_generic_memory_stats
        end
      end
    {% end %}

    {% if flag?(:darwin) %}
      private def get_macos_memory_stats : MemoryStats
        begin
          # Use vm_stat command on macOS
          result = Process.run("vm_stat", shell: true)
          if result.success?
            page_size = 4096_u64
            free_pages = 0_u64
            active_pages = 0_u64
            inactive_pages = 0_u64
            wired_pages = 0_u64

            result.output.each_line do |line|
              case line
              when /^Pages free:\s+(\d+)/
                free_pages = $1.to_u64
              when /^Pages active:\s+(\d+)/
                active_pages = $1.to_u64
              when /^Pages inactive:\s+(\d+)/
                inactive_pages = $1.to_u64
              when /^Pages wired down:\s+(\d+)/
                wired_pages = $1.to_u64
              end
            end

            used_pages = active_pages + inactive_pages + wired_pages
            total_pages = used_pages + free_pages

            total_bytes = total_pages * page_size
            used_bytes = used_pages * page_size
            available_bytes = free_pages * page_size
            usage_percent = total_bytes > 0 ? (used_bytes.to_f / total_bytes * 100) : 0.0

            MemoryStats.new(total_bytes, used_bytes, available_bytes, usage_percent)
          else
            get_generic_memory_stats
          end
        rescue
          get_generic_memory_stats
        end
      end
    {% end %}

    private def get_generic_memory_stats : MemoryStats
      # Very basic fallback - this is a rough estimation
      # In a real implementation, you might want to use system-specific APIs
      # or Crystal's GC stats as a proxy

      # For now, return conservative estimates
      total_bytes = 8_u64 * 1024 * 1024 * 1024 # Assume 8GB total
      used_bytes = 2_u64 * 1024 * 1024 * 1024  # Assume 2GB used
      available_bytes = total_bytes - used_bytes
      usage_percent = (used_bytes.to_f / total_bytes * 100)

      MemoryStats.new(total_bytes, used_bytes, available_bytes, usage_percent)
    end
  end
end

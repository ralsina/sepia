# Event Logging in Sepia

Sepia provides a comprehensive event logging system that tracks object lifecycle events and user activities. This is particularly useful for collaborative applications, audit trails, and activity feeds.

## Table of Contents

- [Overview](#overview)
- [Key Concepts](#key-concepts)
- [Enabling Event Logging](#enabling-event-logging)
- [Automatic Event Logging](#automatic-event-logging)
- [Activity Logging](#activity-logging)
- [Querying Events](#querying-events)
- [Event Structure](#event-structure)
- [On-Disk Format](#on-disk-format)
- [Generation Tracking](#generation-tracking)
- [Storage API](#storage-api)
- [Object API](#object-api)
- [Use Cases](#use-cases)
- [Best Practices](#best-practices)
- [Advanced Topics](#advanced-topics)

## Overview

Sepia's event logging system captures all important actions on objects:

- **Lifecycle Events**: Created, Updated, Deleted operations
- **Activity Events**: User-defined activities that aren't object persistence
- **Metadata Support**: Rich JSON-serializable context for events
- **Generation Tracking**: Links events to object versions for optimistic concurrency
- **Per-Object Storage**: Events stored alongside object data for easy access

## Key Concepts

### Event Types

- **Created**: Object was created for the first time
- **Updated**: Object was modified and saved
- **Deleted**: Object was removed from storage
- **Activity**: User-defined action (e.g., moved_lane, highlighted, shared)

### Metadata

All events support arbitrary JSON-serializable metadata:

```crystal
# Simple metadata
{"user" => "alice", "reason" => "initial_creation"}

# Complex metadata
{
  "user" => "alice",
  "timestamp" => Time.utc,
  "changes" => ["title", "content"],
  "collaboration" => {
    "session_id" => "abc123",
    "duration" => 1800,
    "participants" => ["alice", "bob"]
  }
}
```

### Generation Tracking

Events are linked to object generation numbers:
- Generation 0: Activity events (don't change object state)
- Generation N+1: Save operations that create new versions
- Current generation: Delete operations

## Enabling Event Logging

Event logging is disabled by default. Enable it per class:

```crystal
class Document < Sepia::Object
  include Sepia::Serializable
  sepia_log_events true  # Enable logging for this class

  property content : String

  def initialize(@content = "")
  end

  def to_sepia : String
    @content
  end

  def self.from_sepia(json : String) : self
    new(json)
  end
end

class Project < Sepia::Object
  include Sepia::Container
  sepia_log_events true  # Enable logging for containers too

  property name : String
  property boards : Array(Board)

  def initialize(@name = "")
    @boards = [] of Board
  end
end
```

### Configuration Options

```crystal
# Enable logging
sepia_log_events true

# Disable logging
sepia_log_events false

# Alternative syntax
sepia_log_events_enabled
sepia_log_events_disabled
```

## Automatic Event Logging

When event logging is enabled, Sepia automatically logs lifecycle events:

### Using Storage API

```crystal
# Create and save (logs Created event)
doc = Document.new("Hello World")
doc.sepia_id = "my-doc"
Sepia::Storage.save(doc, metadata: {"user" => "alice", "reason" => "initial_creation"})

# Update and save (logs Updated event)
doc.content = "Updated content"
Sepia::Storage.save(doc, metadata: {"user" => "bob", "reason" => "content_edit"})

# Delete (logs Deleted event)
Sepia::Storage.delete(doc, metadata: {"user" => "admin", "reason" => "cleanup"})
```

### Using Object API

```crystal
# Create and save
doc = Document.new("Hello World")
doc.sepia_id = "my-doc"
doc.save(metadata: {"user" => "alice"})  # Smart save (auto-detects new vs existing)

# Update with forced generation
doc.content = "Updated content"
doc.save(force_new_generation: true, metadata: {"user" => "bob"})

# Or use the legacy method
new_doc = doc.save_with_generation(metadata: {"user" => "charlie"})
```

## Activity Logging

Log user activities that aren't related to object persistence:

### Basic Activity Logging

```crystal
# Log activities on any object
doc.log_activity("highlighted", {"color" => "yellow", "user" => "alice"})
doc.log_activity("shared", {"platform" => "slack", "user" => "bob"})

# Log activities on containers too
project.log_activity("lane_created", {"lane_name" => "Review", "user" => "charlie"})
project.log_activity("color_changed")  # Simple version without metadata
```

### Rich Activity Examples

```crystal
# Complex activity with structured metadata
note.log_activity("moved", {
  "from_lane" => "In Progress",
  "to_lane" => "Done",
  "user" => "alice",
  "timestamp" => Time.utc,
  "drag_duration" => 2.5,
  "collaborators" => ["bob", "charlie"]
})

# Activity with arrays and objects
board.log_activity("restructured", {
  "action" => "lane_reorder",
  "user" => "alice",
  "changes" => [
    {"lane" => "Todo", "old_index" => 0, "new_index" => 1},
    {"lane" => "Done", "old_index" => 2, "new_index" => 0}
  ],
  "affected_items" => 5
})
```

## Querying Events

Access the event history for any object:

### Basic Querying

```crystal
# Get all events for an object
events = Sepia::Storage.object_events(Document, "my-doc")

# Events are ordered by timestamp (newest first)
events.each do |event|
  puts "#{event.timestamp}: #{event.event_type}"
  puts "  Generation: #{event.generation}"
  puts "  Metadata: #{event.metadata}"
end
```

### Filtering Events

```crystal
# Filter by event type
created_events = events.select(&.event_type.created?)
updated_events = events.select(&.event_type.updated?)
activity_events = events.select(&.event_type.activity?)
deleted_events = events.select(&.event_type.deleted?)

# Filter by generation
gen2_events = events.select(&.generation.==(2))

# Filter by metadata
user_events = events.select { |e| e.metadata["user"]? == "alice" }
```

### Advanced Queries

```crystal
# Get activities by specific user
alice_activities = events.select do |event|
  event.event_type.activity? &&
  event.metadata["user"]? == "alice"
end

# Get recent save operations
recent_saves = events.select do |event|
  event.event_type.created? || event.event_type.updated?
end.first(5)

# Get activities in time range
today_events = events.select do |event|
  event.timestamp > Time.utc.at_beginning_of_day
end
```

## Event Structure

Each event contains rich information:

```crystal
event = Sepia::LogEvent.new(
  event_type: Sepia::LogEventType::Updated,
  generation: 2,
  metadata: {"user" => "alice", "reason" => "edit"}
)

event.timestamp    # => Time when the event occurred
event.event_type   # => Created, Updated, Deleted, or Activity
event.generation   # => Object generation number (0 for activities)
event.metadata     # => JSON::Any with custom context
```

### Accessing Metadata

```crystal
# Simple metadata access
user = event.metadata["user"].as_s
reason = event.metadata["reason"].as_s

# Complex metadata access
changes = event.metadata["changes"].as_a
collaborators = event.metadata["collaborators"].as_a.map(&.as_s)

# Safe access
user = event.metadata["user"]?.try(&.as_s)
count = event.metadata["count"]?.try(&.as_i)
```

## On-Disk Format

Events are stored in JSON Lines format in `.events/` directories:

### Directory Structure

```
./_data
├── Document
│   └── doc-123
│       └── .events
│           └── doc-123.jsonl    # One JSON event per line
└── Project
    └── proj-456
        └── .events
            └── proj-456.jsonl
```

### Event File Format

Each line is a JSON object:

```json
{"ts":"2025-01-15T10:30:45Z","type":"created","gen":1,"meta":{"user":"alice","reason":"initial_creation"}}
{"ts":"2025-01-15T10:31:20Z","type":"activity","gen":1,"meta":{"action":"highlighted","color":"yellow","user":"bob"}}
{"ts":"2025-01-15T10:32:10Z","type":"updated","gen":2,"meta":{"user":"charlie","reason":"content_edit"}}
{"ts":"2025-01-15T10:33:00Z","type":"deleted","gen":2,"meta":{"user":"admin","reason":"cleanup"}}
```

### Field Descriptions

- **ts**: Timestamp in RFC3339 format
- **type**: Event type (created, updated, deleted, activity)
- **gen**: Generation number (0 for activities, N+1 for saves, current for deletes)
- **meta**: JSON metadata object (preserves original data types)

## Generation Tracking

Events are properly linked to object generation numbers:

### Generation Logic

```crystal
# Object at generation 0 (new)
doc.save()                    # Creates generation 1, logs Created(gen=1)

# Object at generation 1 (existing)
doc.save()                    # Creates generation 2, logs Updated(gen=2)
doc.log_activity("highlighted")  # Logs Activity(gen=1) - uses current generation
doc.save(force_new_generation: true)  # Creates generation 3, logs Updated(gen=3)

# Delete always uses current generation
doc.delete()                  # Logs Deleted(gen=3)
```

### Timeline Example

```
gen=1 (Created)    ← Initial save
gen=1 (Activity)   ← Activity on generation 1
gen=2 (Updated)    ← Save creates generation 2
gen=2 (Activity)   ← Activity on generation 2
gen=2 (Deleted)    ← Delete uses current generation
```

## Storage API

### Basic Operations

```crystal
# Save with smart detection
Sepia::Storage.save(object, metadata: {"user" => "alice"})

# Save with forced new generation
Sepia::Storage.save(object, force_new_generation: true, metadata: {"user" => "bob"})

# Save to custom location
Sepia::Storage.save(object, path: "/custom/path", metadata: {"user" => "charlie"})

# Delete with metadata
Sepia::Storage.delete(object, metadata: {"user" => "admin", "reason" => "cleanup"})
```

### Advanced Options

```crystal
# Disable caching
Sepia::Storage.save(object, cache: false, metadata: {"user" => "alice"})

# Custom path with metadata
Sepia::Storage.save(object,
  path: "/archive/documents",
  cache: false,
  metadata: {"user" => "archiver", "auto_archived" => true}
)

# Force new generation with complex metadata
Sepia::Storage.save(object,
  force_new_generation: true,
  metadata: {
    "user" => "alice",
    "batch_id" => "batch_123",
    "changes" => {
      "fields_modified" => ["title", "content"],
      "word_count_change" => 150
    }
  }
)
```

## Object API

### Simple Operations

```crystal
# Smart save (auto-detects new vs existing)
doc.save()

# Save with metadata
doc.save(metadata: {"user" => "alice"})

# Force new generation
doc.save(force_new_generation: true)

# Force new generation with metadata
doc.save(force_new_generation: true, metadata: {"user" => "bob"})
```

### Activity Logging

```crystal
# Simple activity
doc.log_activity("highlighted")

# Activity with metadata
doc.log_activity("shared", {"platform" => "slack", "user" => "charlie"})

# Complex activity with rich metadata
doc.log_activity("collaborative_edit", {
  "session_duration" => 1800,
  "participants" => ["alice", "bob", "charlie"],
  "changes_made" => 15,
  "conflicts_resolved" => 2
})
```

### Method Chaining

```crystal
# All save methods return self for chaining
doc.save(metadata: {"user" => "alice"})
  .log_activity("processed", {"processor" => "auto-summarizer"})
  .save(force_new_generation: true, metadata: {"user" => "system"})
```

## Use Cases

### Activity Feeds

```crystal
# Get recent activity for display
recent_activities = board_events
  .select(&.event_type.activity?)
  .first(10)
  .map do |event|
    {
      "action" => event.metadata["action"],
      "user" => event.metadata["user"],
      "timestamp" => event.timestamp,
      "details" => event.metadata
    }
  end
```

### Audit Trails

```crystal
# Complete change history for compliance
audit_trail = Sepia::Storage.object_events(Document, doc_id)
  .map do |event|
    {
      "timestamp" => event.timestamp,
      "action" => event.event_type.to_s,
      "user" => event.metadata["user"]?,
      "reason" => event.metadata["reason"]?,
      "generation" => event.generation
    }
  end
```

### User Analytics

```crystal
# User activity patterns
user_activities = all_events
  .select { |e| e.metadata["user"]? == "alice" }
  .group_by(&.timestamp.date)
  .transform_values(&.size)

puts "Alice's activity by day:"
user_activities.each do |date, count|
  puts "#{date}: #{count} actions"
end
```

### Debugging

```crystal
# Understand object lifecycle
puts "Document lifecycle:"
Sepia::Storage.object_events(Document, doc_id).each do |event|
  case event.event_type
  when .created?
    puts "  Created at #{event.timestamp} by #{event.metadata["user"]}"
  when .updated?
    puts "  Updated to gen#{event.generation} at #{event.timestamp} by #{event.metadata["user"]}"
  when .activity?
    puts "  Activity: #{event.metadata["action"]} at #{event.timestamp}"
  when .deleted?
    puts "  Deleted at #{event.timestamp} by #{event.metadata["user"]}"
  end
end
```

## Best Practices

### 1. Enable Logging Judiciously

```crystal
# ✅ DO: Enable for important user-facing objects
class Document < Sepia::Object
  include Sepia::Serializable
  sepia_log_events true  # Users care about document history
end

# ❌ DON'T: Enable for everything
class CacheEntry < Sepia::Object
  include Sepia::Serializable
  sepia_log_events false  # Internal objects don't need logging
end
```

### 2. Use Structured Metadata

```crystal
# ✅ GOOD: Structured, queryable metadata
doc.log_activity("approved", {
  "approver" => "alice",
  "approval_level" => "manager",
  "criteria_met" => ["content_review", "fact_check"],
  "next_review" => 7.days.from_now
})

# ❌ AVOID: Unstructured strings
doc.log_activity("approved", "alice approved it as manager, content and facts checked, review in a week")
```

### 3. Choose Meaningful Actions

```crystal
# ✅ GOOD: Specific, actionable events
note.log_activity("moved_to_lane", {"lane" => "Done"})
note.log_activity("assigned", {"assignee" => "bob"})
note.log_activity("priority_changed", {"old" => "high", "new" => "urgent"})

# ❌ AVOID: Generic or unclear events
note.log_activity("action", {"what" => "something happened"})
```

### 4. Include Context

```crystal
# ✅ GOOD: Rich context for understanding
note.log_activity("edited", {
  "user" => "alice",
  "editor" => "web",
  "session_duration" => 120,
  "chars_added" => 150,
  "chars_removed" => 25,
  "auto_save" => false
})

# ❌ AVOID: Minimal context
note.log_activity("edited", {"user" => "alice"})
```

### 5. Use Generation Tracking

```crystal
# ✅ DO: Use generation-aware operations when versioning matters
version = document.save_with_generation(metadata: {"user" => "alice"})
conflict_resolution = handle_conflicts_if_needed(version)

# ✅ DO: Use smart save for simple updates
document.save(metadata: {"user" => "bob"})
```

## Advanced Topics

### Custom Event Types

While Sepia provides built-in event types, you can extend the system:

```crystal
# Add custom action metadata for specialized workflows
case study.log_activity("phase_change", {
  "action" => "phase_change",
  "from_phase" => "recruitment",
  "to_phase" => "interview",
  "protocol" => "clinical_trial_v2"
})
```

### Event Filtering

```crystal
# Create specialized queries
module EventQueries
  def self.user_activity(user_id : String, object_class : Class, limit = 50)
    Sepia::Storage.object_events(object_class, "*")
      .select { |e| e.metadata["user"]?.try(&.to_s) == user_id }
      .first(limit)
  end

  def self.recent_activities(hours = 24)
    cutoff = Time.utc - hours.hours
    # Implementation would need to scan multiple object files
    # Consider maintaining a global activity index for performance
  end
end
```

### Performance Considerations

- **Event Storage**: Events are stored as JSON Lines for efficient append-only operations
- **Query Performance**: Reading events requires file I/O, consider caching frequent queries
- **Storage Size**: Events are stored alongside objects, monitor disk usage for high-frequency logging
- **Indexing**: For large-scale applications, consider maintaining separate indexes for common queries

### Migration and Compatibility

Event storage format may change between Sepia versions. When upgrading:

1. **Backup existing event data**
2. **Test with sample data**
3. **Run migration tools if provided**
4. **Verify event integrity**

Current event format is stable but consider future enhancements:
- Event compression for large metadata
- Global activity indexes
- Event retention policies
- Cross-object event relationships

---

## API Reference

### Core Classes

- **`Sepia::LogEvent`**: Individual event record
- **`Sepia::LogEventType`**: Event type enum (Created, Updated, Deleted, Activity)
- **`Sepia::EventLogger`**: Event storage and retrieval engine

### Key Methods

#### Storage API
```crystal
Sepia::Storage.save(object, metadata?, cache?, path?, force_new_generation?)
Sepia::Storage.delete(object, metadata?, cache?)
Sepia::Storage.object_events(class, id) -> Array(LogEvent)
```

#### Object API
```crystal
object.save(metadata?)
object.save(*, force_new_generation : Bool, metadata?)
object.save_with_generation(metadata?)
object.log_activity(action, metadata?)
```

#### Event Access
```crystal
event.timestamp      # Time
event.event_type     # LogEventType
event.generation     # Int32
event.metadata       # JSON::Any
```

For more detailed API documentation, see the [Crystal API docs](https://crystaldoc.info/github/ralsina/sepia/).
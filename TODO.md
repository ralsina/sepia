# TODO List

## Testing
- Add tests for garbage collection with generation-enabled objects
  - Test GC removes all generations when object is orphaned
  - Test GC leaves some generations when object is still referenced
  - Test event logging persists after GC deletes generation files
  - Test generation tracking consistency before/after GC

## Documentation
- Add examples of generation tracking with GC
- Document event logging behavior with deleted objects

## Future Features
- Consider log retention policies for deleted objects
- Performance optimizations if needed (file pooling, buffering)

## User Experience
- Fix generation loading UX to return nil for non-existent generations
  - Current: `Document.load("doc-123.3")` returns current content when generation 3 doesn't exist
  - Desired: Should return nil with clear behavior for non-existent generations
  - Update both Storage and Serializable load methods to handle this case

## Architecture
- Research spinning off cache implementation
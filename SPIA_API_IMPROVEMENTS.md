# Sepia API Improvement Proposals

## Current Issues

1. **`latest()` throws `Enumerable::EmptyError`** when no generations exist
2. **`Storage.load()` throws exception** when object doesn't exist
3. **No graceful fallback** from latest→any generation
4. **No safe methods** following Crystal conventions (using `?` suffix)

## Proposed API Improvements

### 1. Add Safe Query Methods with `?` Suffix (Crystal Convention)

```crystal
# Current (throws exceptions):
obj = Sepia::Storage.load(MyClass, id)
generations = MyClass.latest(id)

# Proposed (returns Option/nil):
obj = Sepia::Storage.load?(MyClass, id)  # Returns MyClass?
generations = MyClass.latest?(id)         # Returns Array(MyClass)?
```

### 2. Separate Loading Strategies

```crystal
# For always getting latest generation:
obj = MyClass.latest?(id)          # nil if no generations

# For getting any generation:
obj = MyClass.load_any?(id)        # nil if no generations

# For getting specific generation:
obj = MyClass.load_generation(id, gen)  # nil if generation doesn't exist
```

### 3. Better Generation Management

```crystal
# Current issues:
MyClass.latest(id)           # Throws if empty
MyClass.versions(id)        # Returns all, but no safe version

# Proposed improvements:
MyClass.latest?(id)          # Returns MyClass?
MyClass.latest!(id)         # Throws (current behavior)
MyClass.versions?(id)       # Returns Array(MyClass)?
MyClass.count_generations(id)  # Returns Int32 (no exceptions)
MyClass.has_generations?(id) # Returns Bool
```

### 4. Chainable Safe Operations

```crystal
# Current verbose:
begin
  obj = MyClass.latest?(id)
rescue Enumerable::EmptyError
  obj = MyClass.load_any?(id)
end

# Proposed cleaner:
obj = MyClass.latest?(id) || MyClass.load_any?(id)
```

## Key API Improvements

1. **Consistent `?` Suffix**: All safe methods return optionals
2. **Preserve Current Behavior**: Keep throwing methods with `!` suffix for when you *do* want exceptions
3. **Better Generation API**: More granular control over version/generation access
4. **Performance**: Avoid exception overhead when objects don't exist

## Most Valuable Changes

1. **`latest?()` method** - This is the main culprit in our issues
2. **`load?()` method** - Safer loading that doesn't require try/catch
3. **Better generation introspection** - Check existence/count without loading

## Benefits

- **Cleaner Code**: No more try/catch blocks for expected "not found" cases
- **Performance**: Avoid exception overhead for common cases
- **Developer Experience**: Follows Crystal conventions consistently
- **Backward Compatibility**: Existing code continues to work with `!` methods
- **Predictable Behavior**: Methods with `?` are safe, methods without are explicit

## Migration Strategy

1. **Add Safe Methods**: Introduce `?` variants alongside existing methods
2. **Documentation**: Encourage use of safe methods in documentation
3. **Gradual Migration**: Applications can migrate at their own pace
4. **Deprecation**: Eventually deicate unsafe methods (long-term)
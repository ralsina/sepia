# Sepia

⚠️ **Warning: Unstable API and Storage Format**
Sepia is currently in active development and does not have a stable API or storage format. **The API is subject to change without notice**, and **breaking changes may occur in any release**. Additionally, the on-disk storage format is not stable - you will need to migrate your data stores when upgrading between versions. Use at your own risk in production.

Sepia is a file-system-based serialization library for Crystal that provides two main modules:

- **`Sepia::Serializable`**: Objects serialize to single files
- **`Sepia::Container`**: Objects serialize as directories containing nested objects

## Installation

Add to your `shard.yml`:

```yaml
dependencies:
  sepia:
    github: ralsina/sepia
```

## Documentation

📖 **Full Documentation**: [https://ralsina.github.io/sepia](https://ralsina.github.io/sepia)

The documentation site includes:
- Getting started guide
- API reference
- Examples and tutorials
- Advanced features (backup, file watching, event logging)

## Development

Run tests with `crystal spec`.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a Pull Request
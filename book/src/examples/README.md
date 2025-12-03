# Examples

This section provides real-world examples of how to use Sepia in different types of applications. Each example demonstrates specific patterns and best practices for working with Sepia's serialization and storage features.

## Available Examples

- **[Document Management](document-management.md)** - Building a document management system with file storage and metadata
- **[Configuration Management](configuration-management.md)** - Managing application configuration with versioning and rollback
- **[Collaborative Applications](collaborative-apps.md)** - Building multi-user applications with event logging and conflict resolution

## Key Concepts Demonstrated

### Object Design Patterns

- **Serializable vs Container** - When to use each module
- **Object Relationships** - Modeling one-to-many, many-to-many relationships
- **Inheritance Hierarchies** - Working with polymorphic object graphs

### Storage and Persistence

- **Configuration** - Setting up different storage backends
- **Performance** - Efficient object loading and caching strategies
- **Backup and Migration** - Data portability and disaster recovery

### Advanced Features

- **File Watching** - Reacting to external changes in real-time
- **Event Logging** - Building audit trails and activity feeds
- **Generation Tracking** - Optimistic concurrency control for collaborative apps

## Running the Examples

Each example is a complete, runnable Crystal application. To run an example:

```bash
# Clone the repository
git clone https://github.com/ralsina/sepia.git
cd sepia

# Install dependencies
shards install

# Run an individual example
crystal run examples/document_management.cr
```

## Best Practices

These examples demonstrate several best practices for working with Sepia:

1. **Always define meaningful `sepia_id` values** - Use business-relevant identifiers
2. **Implement proper error handling** - Handle storage failures gracefully
3. **Use generation tracking for collaborative apps** - Prevent data loss from concurrent edits
4. **Set up file watching for multi-process scenarios** - Stay synchronized with external changes
5. **Create regular backups** - Use the backup system for data protection
6. **Structure objects logically** - Keep related data together in containers
7. **Use appropriate storage backends** - FileStorage for persistence, InMemoryStorage for testing

## Adapting Examples

These examples are designed to be starting points. You can adapt them by:

- **Changing storage backends** - Switch between FileStorage and InMemoryStorage
- **Adding custom fields** - Extend the example objects with your own properties
- **Implementing different interfaces** - Add REST APIs, web UIs, or CLIs
- **Integrating with other libraries** - Combine with web frameworks, databases, or message queues

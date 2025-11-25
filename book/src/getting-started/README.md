# Getting Started

Welcome to Sepia! This guide will help you get up and running with Sepia's file-system-based object persistence.

## What You'll Learn

In this section, you'll learn:

- How to install Sepia in your Crystal project
- Basic concepts and terminology
- How to create your first persistent objects
- How to organize your data structures

## Prerequisites

Before you begin, make sure you have:

- Crystal 1.16.3 or higher installed
- Basic understanding of Crystal classes and modules
- A code editor or IDE

## Core Concepts

Sepia provides two main modules for object persistence:

### Serializable Objects
Objects that serialize to a single file on disk. Perfect for simple data structures like documents, configurations, or settings.

### Container Objects
Objects that serialize as directories containing other objects. Great for complex data structures with relationships like project hierarchies, user profiles, or configuration systems.

### Storage Backends
Sepia supports multiple storage backends:
- **Filesystem** (default): Stores objects in local directories
- **Memory**: Keeps objects in RAM (useful for testing)

### Generation Tracking
Sepia tracks object versions to prevent conflicts when multiple processes modify the same data.

## Next Steps

1. [Installation](installation.md) - Add Sepia to your project
2. [Quick Start](quick-start.md) - Create your first persistent objects
3. [Core Concepts](core-concepts.md) - Understand the fundamentals

Let's start with [Installation](installation.md).
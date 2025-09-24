module Sepia
  # Abstract base class for storage backends.
  # All storage implementations must inherit from this class.
  abstract class StorageBackend
    # Save a Serializable object
    abstract def save(object : Serializable, path : String? = nil)

    # Save a Container object
    abstract def save(object : Container, path : String? = nil)

    # Load an object by class and ID
    abstract def load(object_class : Class, id : String, path : String? = nil) : Object

    # Delete an object
    abstract def delete(object : Serializable | Container)

    # List all object IDs of a given class
    abstract def list_all(object_class : Class) : Array(String)

    # Check if an object exists
    abstract def exists?(object_class : Class, id : String) : Bool

    # Count objects of a given class
    abstract def count(object_class : Class) : Int32

    # Clear all data (useful for testing)
    abstract def clear

    # Export all data as a hash structure
    abstract def export_data : Hash(String, Array(Hash(String, String)))

    # Import data from a hash structure
    abstract def import_data(data : Hash(String, Array(Hash(String, String))))
  end
end

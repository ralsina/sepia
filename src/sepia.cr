require "./sepia/*"

# Sepia is a simple, file-system-based serialization library for Crystal.
# It provides two main modules: `Sepia::Serializable` and `Sepia::Container`.
#
# Disk Storage Strategy:
#
# **1. Individual Objects:**
#
# - `Sepia::Serializable` objects: Stored as individual files in a directory
#   named after their class, using their `sepia_id` as the filename.
#
#   Example:
#
# ```crystal
# class MySerializable
#   include Sepia::Serializable
#   property value : String
#
#   def initialize(@value); end
#
#   def to_sepia
#     @value
#   end
#
#   def self.from_sepia(s)
#     new(s)
#   end
# end
#
# my_obj = MySerializable.new("hello")
# my_obj.sepia_id = "my_obj_id"
# my_obj.save
# ```
# 
#
#   On-disk representation:
#
# ```text
# _data/
#   └── MySerializable/
#       └── my_obj_id
# ```
#
# - `Sepia::Container` objects: Stored as directories, also named after their
#   class and using their `sepia_id` as the directory name.
#
#   Example:
#
# ```crystal
#   class MyContainer
#     include Sepia::Container
#   end
#
#   my_container = MyContainer.new
#   my_container.sepia_id = "my_container_id"
#   my_container.save
# ```
#
#   On-disk representation:
#
# ```text
#   _data/
#   └── MyContainer/
#       └── my_container_id/
# ```
#
# **2. Nested Objects within Containers:**
# - Nested `Serializable` objects: Stored as symlinks to their canonical
#   `Serializable` file.
#
#   Example:
#
# ```crystal
#   class MyContainer
#     include Sepia::Container
#     property nested_serializable : MySerializable
#
#     def initialize(@nested_serializable); end
#   end
#
#   my_serializable = MySerializable.new("nested")
#   my_serializable.sepia_id = "nested_serializable_id"
#   my_container = MyContainer.new(my_serializable)
#   my_container.sepia_id = "container_with_serializable"
#   my_container.save
# ```
#
#   On-disk representation:
#
# ```text
#   _data/
#   ├── MyContainer/
#   │   └── container_with_serializable/
#   │       └── nested_serializable -> ../../MySerializable/nested_serializable_id
#   └── MySerializable/
#       └── nested_serializable_id
# ```
#
# - Nested `Container` objects: Stored as subdirectories, mirroring the
#   object hierarchy on disk.
#
#   Example:
#
# ```crystal
#   class MyOuterContainer
#     include Sepia::Container
#     property inner_container : MyContainer
#
#     def initialize(@inner_container); end
#   end
#
#   class MyInnerContainer
#     include Sepia::Container
#   end
#
#   inner = MyInnerContainer.new
#   inner.sepia_id = "inner_container_id"
#   outer = MyOuterContainer.new(inner)
#   outer.sepia_id = "outer_container_id"
#   outer.save
# ```
#
#   On-disk representation:
#
# ```text
#   _data/
#   └── MyOuterContainer/
#       └── outer_container_id/
#           └── inner_container/
# ```
#
# **3. Collections within Containers:**
# - **Arrays/Sets of `Serializable` objects:** Stored in a subdirectory
#   named after the collection's instance variable. Each serializable object
#   is symlinked into that directory using its index as the filename.
#
#   #   Example:
#
# ```crystal
#   class MyContainerWithArray
#     include Sepia::Container
#     property serializables : Array(MySerializable)
#
#     def initialize(@serializables = [] of MySerializable); end
#   end
#
#   s1 = MySerializable.new("one"); s1.sepia_id = "s1_id"
#   s2 = MySerializable.new("two"); s2.sepia_id = "s2_id"
#   container = MyContainerWithArray.new([s1, s2])
#   container.sepia_id = "array_of_serializables"
#   container.save
# ```
#
#   On-disk representation:
#
# ```text
#   _data/
#   ├── MyContainerWithArray/
#   │   └── array_of_serializables/
#   │       └── serializables/
#   │           ├── 0 -> ../../../../MySerializable/s1_id
#   │           └── 1 -> ../../../../MySerializable/s2_id
#   └── MySerializable/
#       ├── s1_id
#       └── s2_id
# ```
#
# - **Arrays/Sets of `Container` objects:** Stored in a subdirectory
#   named after the collection's instance variable. Each container object
#   is stored as a subdirectory within that directory, using its index as
#   the directory name.
#
#   Example:
# ```crystal
# class MyContainerWithArrayOfContainers
#   include Sepia::Container
#  property containers : Array(MyContainer)
# 
#   def initialize(@containers = [] of MyContainer); end
# end
# 
# c1 = MyContainer.new; c1.sepia_id = "c1_id"
# c2 = MyContainer.new; c2.sepia_id = "c2_id"
# container = MyContainerWithArrayOfContainers.new([c1, c2])
# container.sepia_id = "array_of_containers"
# container.save
# ```
#
#   On-disk representation:
#
# ```text
# _data/
#   ├── MyContainerWithArrayOfContainers/
#   │   └── array_of_containers/
#   │       └── containers/
#   │           ├── 0/
#   │           └── 1/
#   └── MyContainer/
#       ├── c1_id/
#       └── c2_id/
# ```
#
# - **Hashes (String keys) of `Serializable` values:** Stored in a subdirectory
#   named after the hash's instance variable. Each serializable object
#   is symlinked into that directory using its key as the filename.
#
#   Example:
# 
#   ```crystal
#   class MyContainerWithHash
#     include Sepia::Container
#     property serializables_hash : Hash(String, MySerializable)
# 
#     def initialize(@serializables_hash = {} of String => MySerializable); end
#   end
# 
#   s1 = MySerializable.new("alpha"); s1.sepia_id = "alpha_id"
#   s2 = MySerializable.new("beta"); s2.sepia_id = "beta_id"
#   container = MyContainerWithHash.new({"a" => s1, "b" => s2})
#   container.sepia_id = "hash_of_serializables"
#   container.save
#   ```
# 
#   On-disk representation:
# 
# ```text
# _data/
# ├── MyContainerWithHash/
# │   └── hash_of_serializables/
# │       └── serializables_hash/
# │           ├── a -> ../../../../MySerializable/alpha_id
# │           └── b -> ../../../../MySerializable/beta_id
# └── MySerializable/
#     ├── alpha_id
#     └── beta_id
# ```
#
# - **Hashes (String keys) of `Container` values:** Stored in a subdirectory
#   named after the hash's instance variable. Each container object
#   is stored as a subdirectory within that directory, using its key as
#   the directory name.
#
#   Example:
# 
# ```crystal
# class MyContainerWithHashOfContainers
#   include Sepia::Container
#   property containers_hash : Hash(String, MyContainer)
# 
#   def initialize(@containers_hash = {} of String => MyContainer); end
# end
# 
# c1 = MyContainer.new; c1.sepia_id = "hash_c1_id"
# c2 = MyContainer.new; c2.sepia_id = "hash_c2_id"
# container = MyContainerWithHashOfContainers.new({"x" => c1, "y" => c2})
# container.sepia_id = "hash_of_containers"
# container.save
# ```
# 
# On-disk representation:
# 
# ```text
# _data/
# ├── MyContainerWithHashOfContainers/
# │   └── hash_of_containers/
# │       └── containers_hash/
# │           ├── x/
# │           └── y/
# └── MyContainer/
#     ├── hash_c1_id/
#     └── hash_c2_id/
# ```
module Sepia
  VERSION = "0.1.0"
end

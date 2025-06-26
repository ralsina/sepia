# sepia

A simple serialization library for Crystal, with an interface inspired by `JSON::Serializable`.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     sepia:
       github: your-github-user/sepia
   ```

2. Run `shards install`

## Usage

```crystal
require "sepia"

class User
  include Sepia::Serializable

  property name : String
  property age : Int32

  # Fields can be renamed for serialization
  @[Sepia::Field(key: "user_email")]
  property email : String

  # Fields can be ignored
  @[Sepia::Field(ignore: true)]
  property internal_id : String = "some-internal-value"

  def initialize(@name, @age, @email)
  end
end

user = User.new("Alice", 30, "alice@example.com")

# Serialize to a string
sepia_string = user.to_sepia
puts sepia_string
# Output (order may vary):
# name=Alice
# age=30
# user_email=alice@example.com

# Deserialize from a string
new_user = User.from_sepia(sepia_string)
puts new_user.name        # => Alice
puts new_user.age         # => 30
puts new_user.email       # => alice@example.com
puts new_user.internal_id # => "some-internal-value" (default value is kept)
```

TODO: Write usage instructions here

## Development

TODO: Write development instructions here

## Contributing

1. Fork it (<https://github.com/your-github-user/sepia/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Roberto Alsina](https://github.com/your-github-user) - creator and maintainer

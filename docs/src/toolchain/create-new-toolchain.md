To create a toolchain with a custom provider and a rule that consumes it, you need to define three components:
A custom provider: A struct-like object that carries information from a toolchain rule to a consuming rule.
A toolchain rule: This rule uses is_toolchain_rule = True and returns an instance of your custom provider.
A consuming rule: A standard build rule that requests your toolchain and uses the information from the provider to define build actions.

# Define the provider and toolchain rule
Create a new file greeting.bzl to define both the provider and the toolchain rule. 

```starlark
"A toolchain for generating greetings."

# --- The Provider ---
# This defines the data structure that the toolchain will return.
GreetingToolchainInfo = provider(fields = ["greeting_prefix"])

# --- The Toolchain Rule ---
def _greeting_toolchain_impl(ctx):
    """The implementation for the greeting toolchain rule."""
    # This example simply hardcodes the prefix. In a real toolchain,
    # it might load this from a configuration file or a binary.
    return [GreetingToolchainInfo(greeting_prefix = "Hello")]

greeting_toolchain = rule(
    impl = _greeting_toolchain_impl,
    attrs = {},
    is_toolchain_rule = True,
)
```

# Define the consuming rule
Add the consuming rule to the same greeting.bzl file. This rule takes a name and uses the toolchain to produce a text file. 

```starlark
# --- The Consuming Rule ---
def _greet_impl(ctx):
    """The implementation for the greet rule."""
    toolchain = ctx.toolchains["//:greeting_toolchain_type"]
    greeting_prefix = toolchain.greeting_prefix
    output = ctx.attrs.name + ".txt"

    # Define the build action using the prefix from the toolchain
    ctx.actions.write(
        output = output,
        content = "%s, %s!" % (greeting_prefix, ctx.attrs.name),
    )

    return [DefaultInfo(default_outputs = [output])]

greet = rule(
    impl = _greet_impl,
    attrs = {
        "name": attrs.string(),
        # Define a toolchain dependency. The type is a label defined
        # elsewhere (like in the prelude), which will be mapped to
        # our custom toolchain target via a `.buckconfig` entry.
        "toolchain": attrs.toolchain_dep(default_only = True),
    },
)
```

# Set up the project configuration
```ini
[platform.toolchains]
# Maps the generic toolchain type requested by the `greet` rule
# to our concrete toolchain target.
//:greeting_toolchain_type = //toolchains:greeting_toolchain
```

```starlark
# Load the rules from our custom .bzl file.
load("//:greeting.bzl", "greeting_toolchain")

# Define our toolchain. This creates the concrete target that the
# consuming rule and .buckconfig entry will reference.
greeting_toolchain(
    name = "greeting_toolchain",
)
```

# Create a target and build
```starlark
# Load our consuming rule.
load("//:greeting.bzl", "greet")

# Define a target that uses the greet rule.
greet(
    name = "alice",
)
```

To build and view the output, run the following command from the project root:
```sh
buck2 build :alice --show-output
```

The result will be a buck-out path to a file named alice.txt containing the text "Hello, alice!". The greet rule implicitly resolved and used the greeting_toolchain to get the "Hello" prefix.




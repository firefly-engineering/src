# Configuration Reference

## Module Options

### firefly.toolchains.registry

**Type**: `path`
**Default**: Built-in default registry

Path to toolchain registry file. Can be:
- Default (omit to use built-in registry)
- Custom path: `./my-registry.nix`
- Extended: `lib.recursiveUpdate defaultRegistry ./additions.nix`

**Example**:
```nix
firefly.toolchains.registry = ./my-custom-registry.nix;
```

### firefly.toolchains.declarationFile

**Type**: `path`
**Default**: `./toolchain.toml`

Path to toolchain declaration file.

**Example**:
```nix
firefly.toolchains.declarationFile = ./config/toolchains.toml;
```

### firefly.toolchains.buck2.enable

**Type**: `bool`
**Default**: `true`

Enable Buck2 config generation.

**Example**:
```nix
firefly.toolchains.buck2.enable = false;  # Disable if not using Buck2
```

### firefly.toolchains.buck2.autoGenerate

**Type**: `bool`
**Default**: `true`

Automatically generate Buck2 configs on shell entry.

**Example**:
```nix
firefly.toolchains.buck2.autoGenerate = false;  # Manual generation only
```

### firefly.toolchains.shell.showVersions

**Type**: `bool`
**Default**: `true`

Show toolchain versions on shell entry.

**Example**:
```nix
firefly.toolchains.shell.showVersions = false;  # Quiet mode
```

## toolchain.toml Schema

```toml
[<toolchain-name>]
version = "<version-string>"

# Example:
[go]
version = "1.21.5"

[rust]
version = "1.75.0"

[python]
version = "3.12"
```

Version strings must match entries in the registry.

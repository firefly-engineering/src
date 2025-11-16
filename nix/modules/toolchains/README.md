# Toolchains Module

This module provides a registry-based toolchain resolution system that ensures synchronization between development shells and Buck2 builds.

## Overview

The toolchains module:
- Reads toolchain declarations from `toolchain.toml`
- Resolves versions through a configurable registry
- Provides comprehensive error handling with helpful messages
- Ensures both shell and Buck2 use identical toolchain binaries

## Usage

### 1. Import the Module

In your `flake.nix`:

```nix
{
  inputs.firefly-toolchains.url = "github:firefly-engineering/src";

  outputs = { self, firefly-toolchains, ... }: {
    # Import the module
    imports = [ firefly-toolchains.flakeModules.toolchains ];

    # Configure it
    firefly.toolchains = {
      declarationFile = ./toolchain.toml;  # Default
      registry = firefly-toolchains.modules.toolchains.registry-default;  # Or custom
    };
  };
}
```

### 2. Create toolchain.toml

Create a `toolchain.toml` file in your repository root:

```toml
[go]
version = "1.22.1"

[nodejs]
version = "20"

[python]
version = "3.12"
```

### 3. Use Synchronized Toolchains

```bash
# Development shell has declared toolchains
nix develop
go version  # go version go1.22.1 linux/amd64

# Buck2 uses the same toolchains
buck2 build //...  # Uses same go 1.22.1 binary
```

## Configuration Options

### `firefly.toolchains.declarationFile`

- **Type**: path
- **Default**: `./toolchain.toml`
- **Description**: Path to the toolchain declaration file

### `firefly.toolchains.registry`

- **Type**: path
- **Default**: `./registry-default.nix`
- **Description**: Path to the toolchain registry file

The registry maps version strings to Nix derivations:

```nix
{ pkgs }: {
  go = {
    "1.22.1" = pkgs.go_1_22;
  };
  nodejs = {
    "20" = pkgs.nodejs_20;
  };
}
```

### `firefly.toolchains.buck2.enable`

- **Type**: boolean
- **Default**: `true`
- **Description**: Enable Buck2 toolchain config generation

### `firefly.toolchains.buck2.outputPath`

- **Type**: path
- **Default**: `./toolchains`
- **Description**: Where to generate Buck2 toolchain files

## Error Handling

The module provides comprehensive error handling for common scenarios:

### Missing toolchain.toml

If the declaration file doesn't exist, you'll get:

```
Toolchain declaration file not found: /path/to/toolchain.toml

To fix this, create a toolchain.toml file:

  cat > toolchain.toml <<EOF
  [go]
  version = "1.21.5"
  EOF

Or specify a different path:

  firefly.toolchains.declarationFile = ./path/to/toolchain.toml;

See: docs/src/user-guide/getting-started.md
```

### Unknown Toolchain Version

If you request a version not in the registry:

```
Unknown version '999.999.999' for toolchain 'go'

Available versions for 'go':
  1.21.5
  1.22.0
  1.22.1

Fix this by:
- Using an available version in toolchain.toml
- Adding '999.999.999' to your registry:

    go."999.999.999" = pkgs.your-package;

See: docs/src/user-guide/custom-registry.md
```

### Malformed TOML

If the TOML file has syntax errors:

```
Failed to parse TOML file: /path/to/toolchain.toml

The file contains syntax errors. Common issues:
- Missing quotes around strings
- Unclosed brackets
- Invalid section headers

Example of valid syntax:

  [go]
  version = "1.21.5"

  [rust]
  version = "1.75.0"

TOML specification: https://toml.io/
```

### Unknown Toolchain

If you reference a toolchain not in the registry:

```
Unknown toolchain 'nonexistent' in /path/to/toolchain.toml

Available toolchains in registry:
  go
  nodejs
  python
  rust

Either:
- Fix the toolchain name in toolchain.toml
- Add 'nonexistent' to your custom registry
```

### Missing Version Field

If a toolchain section lacks a version:

```
Invalid configuration for toolchain 'go' in /path/to/toolchain.toml

Toolchain 'go' is missing required 'version' field

Example of correct format:

  [go]
  version = "1.0.0"
```

### Missing Registry File

If a custom registry path is invalid:

```
Registry file not found: /path/to/registry.nix

To fix this:
- Check the path is correct
- Use default registry: remove firefly.toolchains.registry option
- Create registry file at /path/to/registry.nix

See: docs/src/user-guide/custom-registry.md
```

### Invalid Registry Format

If the registry has an incorrect structure:

```
Invalid registry format: expected attribute set, got string

Registry must be an attribute set like:

  { pkgs }: {
    go = {
      "1.21.5" = pkgs.go_1_21;
    };
  }
```

### Derivation Build Failures

If a derivation exists but can't be evaluated:

```
Failed to resolve toolchain 'go' version '1.21.5'

The derivation exists in the registry but cannot be built.
This may indicate:
- Incompatible system architecture
- Missing dependencies
- Broken package in nixpkgs

Try:
- Using a different version
- Updating nixpkgs
- Checking nixpkgs issues: https://github.com/NixOS/nixpkgs/issues
```

### Helpful Hints

The module detects common mistakes and provides hints:

```
💡 Hint: 'go' version '1.21' not found, but these similar versions exist:
  1.21.5
```

## Custom Registries

You can create a custom registry to:
- Add versions not in the default registry
- Apply custom patches
- Build toolchains from source
- Support internal/proprietary toolchains

Example custom registry:

```nix
# my-registry.nix
{ pkgs }:

{
  go = {
    "1.22.1" = pkgs.go_1_22.overrideAttrs (old: {
      patches = old.patches ++ [
        ./patches/custom-go-patch.patch
      ];
    });
  };

  rust = {
    "1.75.0" = pkgs.rustc.override {
      llvmPackages = pkgs.llvmPackages_17;
    };
  };

  # Add custom internal toolchain
  internal-tool = {
    "2.0" = pkgs.callPackage ./internal-tool.nix { };
  };
}
```

Then use it:

```nix
firefly.toolchains.registry = ./my-registry.nix;
```

## Extending the Default Registry

You can extend the default registry instead of replacing it:

```nix
{ pkgs, lib, firefly-toolchains }:

let
  defaultRegistry = import "${firefly-toolchains}/nix/modules/toolchains/registry-default.nix" { inherit pkgs; };

  myAdditions = {
    go."1.23.0" = pkgs.go_1_23;  # Add new version
    custom-tool = {
      "1.0" = pkgs.callPackage ./custom.nix { };
    };
  };
in
lib.recursiveUpdate defaultRegistry myAdditions
```

## Architecture

The module works in three stages:

1. **Declaration**: Read `toolchain.toml` to understand what versions are needed
2. **Resolution**: Look up each version in the registry to get Nix derivations
3. **Generation**: Use resolved derivations for both shell and Buck2 configs

This ensures both environments use **exactly the same binaries** from the Nix store.

## Future Features

- Shell environment generation (Phase 0.4)
- Buck2 config generation (Phase 0.5)
- Toolchain composition (Phase 4)
- Multi-backend support (mise, Docker) (Phase 4)
- Registry extension utilities (Phase 8)

## Related Documentation

- [Design Document](../../../docs/src/design/toolchain-synchronization.md)
- [Architecture Overview](../../../docs/src/architecture.md)
- [Task Roadmap](../../../TASKS.md)

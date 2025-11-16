# Getting Started with Toolchain Synchronization

## What is this?

This module synchronizes toolchains between your Nix development shell and Buck2 builds, ensuring that native tooling (`go build`, `cargo check`, IDE) and Buck2 use the **exact same toolchain binaries**.

## Quick Start

### 1. Add to your flake inputs

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    firefly-toolchains.url = "github:firefly-engineering/src";
  };

  outputs = { self, nixpkgs, firefly-toolchains }: {
    # We'll add the module next
  };
}
```

### 2. Import the module

```nix
{
  outputs = { self, nixpkgs, firefly-toolchains }: {
    devShells.x86_64-linux.default =
      let
        pkgs = import nixpkgs { system = "x86_64-linux"; };
      in
      pkgs.mkShell {
        # Import module here
        imports = [ firefly-toolchains.flakeModules.toolchains ];
      };
  };
}
```

### 3. Create toolchain.toml

```toml
# toolchain.toml
[go]
version = "1.21.5"

[rust]
version = "1.75.0"
```

### 4. Enter shell

```bash
nix develop

# You should see:
# 🔧 Toolchain Synchronization Active
#   Go:     go1.21.5
#   Rust:   1.75.0
```

### 5. Verify synchronization

```bash
# Check shell
which go
# /nix/store/...-go-1.21.5/bin/go

# Check Buck2
buck2 audit config go_bin
# /nix/store/...-go-1.21.5/bin/go

# They should be identical! ✅
```

## Next Steps

- [Configuration Guide](./configuration.md) - Customize module behavior
- [Custom Registry](./custom-registry.md) - Add your own toolchain versions
- [Troubleshooting](./troubleshooting.md) - Common issues and solutions

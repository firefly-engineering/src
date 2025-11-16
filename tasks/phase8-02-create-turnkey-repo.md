# Phase 8.2: Create Turnkey Repository (Core Mechanism)

## Overview

Create the `firefly-engineering/turnkey` repository containing the core toolchain synchronization mechanism. This is the "engine" that resolves toolchains and generates configurations.

## Context

Turnkey is the **mechanism** (not the data). It provides:
- Registry resolution logic
- Shell environment generation
- Buck2 config generation
- Validation tools
- But NO specific toolchain versions

Users can use turnkey with:
- Default `toolchain-registry` (most users)
- Custom registry (enterprises)
- Extended registry (add versions)

## Prerequisites

- Phase 8.1: Preparation complete
- Clear understanding of repository boundaries
- Registry interface defined
- Breaking changes identified

## Success Criteria

- [ ] `firefly-engineering/turnkey` repository created
- [ ] Module code moved and working independently
- [ ] Flake structure correct
- [ ] Registry interface well-documented
- [ ] Examples provided (with custom registries)
- [ ] README comprehensive
- [ ] CI/CD configured
- [ ] Tests passing
- [ ] Documentation site set up

## Implementation Guidance

### 1. Create Repository Structure

```bash
# Create new repository
mkdir -p turnkey
cd turnkey
git init

# Create structure
mkdir -p {modules,lib,examples,docs,tests}

# Structure:
# turnkey/
# ├── flake.nix              # Main flake
# ├── flake.lock
# ├── README.md
# ├── LICENSE (MIT or Apache 2.0)
# ├── modules/
# │   └── default.nix        # Main module
# ├── lib/
# │   ├── registry.nix       # Registry helpers
# │   ├── resolution.nix     # Resolution logic
# │   ├── generators.nix     # Config generators
# │   └── validation.nix     # Validation tools
# ├── examples/
# │   ├── minimal/
# │   ├── custom-registry/
# │   └── multi-language/
# ├── docs/
# │   └── src/
# │       ├── getting-started.md
# │       ├── api-reference.md
# │       └── custom-registry.md
# └── tests/
#     └── integration/
```

### 2. Create Main Flake

`flake.nix`:

```nix
{
  description = "Turnkey - Toolchain synchronization for Nix + Buck2";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      # Main module export
      flakeModules.default = import ./modules/default.nix;

      # Compatibility
      nixosModules.default = self.flakeModules.default;

      # Library functions
      lib = import ./lib { inherit nixpkgs; };

      # Example configurations
      examples = {
        minimal = import ./examples/minimal;
        customRegistry = import ./examples/custom-registry;
      };

      # Development shells
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.nixfmt
              pkgs.mdbook
            ];
          };
        }
      );

      # Tests
      checks = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          integration = import ./tests/integration { inherit pkgs self; };
        }
      );
    };
}
```

### 3. Move Module Code

`modules/default.nix`:

```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.turnkey.toolchains;

  # Import library functions
  registryLib = import ../lib/registry.nix { inherit lib; };
  resolution = import ../lib/resolution.nix { inherit lib pkgs; };
  generators = import ../lib/generators.nix { inherit lib pkgs; };
  validation = import ../lib/validation.nix { inherit lib pkgs; };

  # Resolve toolchains
  resolved = resolution.resolveToolchains {
    registry = cfg.registry;
    declarations = cfg.declarationFile;
  };
in
{
  options.turnkey.toolchains = {
    registry = lib.mkOption {
      type = lib.types.anything;  # Function: { pkgs }: attrset
      description = ''
        Toolchain registry function.

        Must be a function that takes { pkgs } and returns an attribute set:

          { pkgs }: {
            <toolchain-name> = {
              "<version-string>" = <derivation>;
            };
          }

        Example:
          { pkgs }: {
            go = {
              "1.21.5" = pkgs.go_1_21;
            };
          }

        See: https://turnkey.dev/docs/registry-interface
      '';
    };

    declarationFile = lib.mkOption {
      type = lib.types.path;
      default = ./toolchain.toml;
      description = "Path to toolchain.toml declaration file";
    };

    buck2 = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Buck2 config generation";
      };

      autoGenerate = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Automatically generate configs on shell entry";
      };
    };

    shell = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Add toolchains to development shell";
      };

      showVersions = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Print toolchain versions on shell entry";
      };
    };

    # Internal option
    resolved = lib.mkOption {
      type = lib.types.attrs;
      internal = true;
      readOnly = true;
      default = resolved;
    };
  };

  config = lib.mkMerge [
    # Shell generation
    (lib.mkIf (cfg.shell.enable && resolved != {}) {
      devShells.default = generators.generateShell {
        inherit resolved;
        showVersions = cfg.shell.showVersions;
      };
    })

    # Buck2 generation
    (lib.mkIf (cfg.buck2.enable && resolved != {}) {
      # Generate Buck2 configs via shell hook
    })
  ];
}
```

### 4. Create Comprehensive README

`README.md`:

```markdown
# Turnkey

> Turnkey toolchain synchronization for Nix + Buck2

Turnkey ensures your development shell and Buck2 builds use **identical toolchain binaries**, eliminating the "works on my machine" problem.

## Quick Start

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    turnkey.url = "github:firefly-engineering/turnkey";
    toolchain-registry.url = "github:firefly-engineering/toolchain-registry";
  };

  outputs = { nixpkgs, turnkey, toolchain-registry, ... }: {
    devShells.x86_64-linux.default =
      (nixpkgs.legacyPackages.x86_64-linux.mkShell {
        imports = [ turnkey.flakeModules.default ];

        turnkey.toolchains.registry = toolchain-registry.registry;
      });
  };
}
```

```toml
# toolchain.toml
[go]
version = "1.21.5"
```

```bash
$ nix develop
🔧 Toolchain Synchronization Active
  Go: go1.21.5

$ which go
/nix/store/abc.../go-1.21.5/bin/go

$ buck2 audit config go.go_bin
/nix/store/abc.../go-1.21.5/bin/go  # ✅ Same path!
```

## Features

- ✅ **Synchronized toolchains**: Shell and Buck2 use identical binaries
- ✅ **Automatic cache invalidation**: Nix paths change = Buck2 cache invalidates
- ✅ **Custom registries**: Use your own toolchain versions
- ✅ **Multi-language**: Go, Rust, Python, C/C++, and more
- ✅ **Security patches**: Apply patches transparently
- ✅ **Zero network**: All toolchains from Nix (offline builds)

## Documentation

- [Getting Started](https://turnkey.dev/docs/getting-started)
- [API Reference](https://turnkey.dev/docs/api-reference)
- [Custom Registry Guide](https://turnkey.dev/docs/custom-registry)
- [Examples](./examples/)

## How It Works

```
toolchain.toml      Registry            Nix Store
──────────────      ────────            ─────────
[go]                go."1.21.5" =       /nix/store/abc-go
version="1.21.5" →  pkgs.go_1_21   →    ↓
                                        Shell & Buck2
                                        (same binary)
```

## Why Turnkey?

**Without Turnkey:**
- Shell: Uses system Go (1.20)
- Buck2: Downloads Go (1.21)
- Result: `go build` works, `buck2 build` fails ❌

**With Turnkey:**
- Shell: Uses Nix Go (1.21)
- Buck2: Uses same Nix Go (1.21)
- Result: Both work identically ✅

## Registry

Turnkey is **mechanism-only**. You need a **registry** (data) to provide toolchain versions.

**Options:**
1. **Default registry**: https://github.com/firefly-engineering/toolchain-registry
2. **Custom registry**: Define your own
3. **Extended registry**: Add to default

See: [Custom Registry Guide](./docs/src/custom-registry.md)

## Examples

- [Minimal](./examples/minimal/) - Simplest setup
- [Custom Registry](./examples/custom-registry/) - Your own versions
- [Multi-Language](./examples/multi-language/) - Go + Rust + Python

## Contributing

Contributions welcome! See [CONTRIBUTING.md](./CONTRIBUTING.md)

## License

Apache 2.0 OR MIT (your choice)

## Links

- **Website**: https://turnkey.dev
- **Docs**: https://turnkey.dev/docs
- **Registry**: https://github.com/firefly-engineering/toolchain-registry
- **Issues**: https://github.com/firefly-engineering/turnkey/issues
```

### 5. Create Examples

**Minimal example** (`examples/minimal/flake.nix`):

```nix
{
  description = "Minimal turnkey example";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    turnkey.url = "github:firefly-engineering/turnkey";
  };

  outputs = { nixpkgs, turnkey, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Custom minimal registry
      customRegistry = { pkgs }: {
        go = {
          "1.21" = pkgs.go_1_21;
        };
      };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        imports = [ turnkey.flakeModules.default ];

        turnkey.toolchains.registry = customRegistry;
      };
    };
}
```

### 6. Documentation Site

Set up mdBook:

```bash
cd docs
mdbook init

# Structure:
# docs/
# ├── book.toml
# └── src/
#     ├── SUMMARY.md
#     ├── introduction.md
#     ├── getting-started.md
#     ├── api-reference.md
#     └── custom-registry.md
```

### 7. CI/CD Configuration

`.github/workflows/ci.yml`:

```yaml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v24
      - name: Run tests
        run: nix flake check
      - name: Build examples
        run: |
          nix build .#examples.minimal
          nix build .#examples.customRegistry

  docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build docs
        run: |
          cd docs
          mdbook build
      - name: Deploy docs
        if: github.ref == 'refs/heads/main'
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./docs/book
```

### 8. Tests

Create integration test (`tests/integration/default.nix`):

```nix
{ pkgs, self }:

pkgs.runCommand "integration-test" {
  buildInputs = [ pkgs.nix pkgs.bash ];
} ''
  # Test that module can be imported
  # Test that resolution works
  # Test that validation works

  touch $out
''
```

## Implementation Steps

1. Create GitHub repository
2. Set up directory structure
3. Create main flake.nix
4. Move module code from main repo
5. Move library code (resolution, generators, etc.)
6. Create comprehensive README
7. Create examples
8. Set up documentation site (mdbook)
9. Configure CI/CD
10. Create tests
11. License files (Apache 2.0 / MIT dual)
12. Initial commit and push

## Testing

```bash
# Test locally before publishing
cd turnkey/

# Check flake structure
nix flake show

# Run tests
nix flake check

# Build examples
nix build .#examples.minimal

# Test integration
nix develop .#examples.minimal --command bash -c "
  echo 'Testing minimal example...'
  which go
"

# Build documentation
cd docs && mdbook build
```

## Related Documentation

- Tasks: `TASKS.md` (Phase 8.2)
- Phase 8.1: Preparation

## Next Steps

After completing this task:
- Phase 8.3: Create toolchain-registry repository (`phase8-03-create-registry-repo.md`)
- Test both repos together
- Phase 8.4: Migrate this repository to use extracted repos

## Notes

- **Focus on mechanism**: No toolchain versions in this repo
- **Clean examples**: Examples should be minimal and educational
- **Documentation**: Comprehensive docs critical for adoption
- **CI/CD**: Ensure quality with automated testing
- **Versioning**: Use semantic versioning from v1.0.0
- **License**: Permissive license for wide adoption
- **Community**: Design for community contribution
- **Stability**: Registry interface should be stable (SemVer)

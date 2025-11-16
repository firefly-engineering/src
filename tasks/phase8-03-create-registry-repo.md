# Phase 8.3: Create Toolchain Registry Repository (Version Catalog)

## Overview

Create the `firefly-engineering/toolchain-registry` repository containing curated toolchain versions. This is the "data" that users combine with turnkey's "mechanism".

## Context

The toolchain registry provides:
- Curated toolchain versions for all major languages
- Security patches and bug fixes
- Metadata and documentation
- Community-maintained version catalog

It's separate from turnkey so:
- ✅ Registry updates don't require turnkey updates
- ✅ Organizations can use turnkey with their own registries
- ✅ Community can contribute new versions easily
- ✅ Mechanism and data evolve independently

## Prerequisites

- Phase 8.1: Preparation complete
- Phase 8.2: Turnkey repository created
- Understanding of nixpkgs package structure
- Knowledge of toolchain versions to include

## Success Criteria

- [ ] `firefly-engineering/toolchain-registry` repository created
- [ ] Registry includes Go, Rust, Python, C/C++ versions
- [ ] Registry structure is clean and extensible
- [ ] Patches directory organized by language
- [ ] README lists all available versions
- [ ] Contribution guide exists
- [ ] CI tests all registry entries
- [ ] Versioning and changelog established
- [ ] Works with turnkey

## Implementation Guidance

### 1. Create Repository Structure

```bash
# Create new repository
mkdir -p toolchain-registry
cd toolchain-registry
git init

# Create structure:
# toolchain-registry/
# ├── flake.nix
# ├── flake.lock
# ├── README.md
# ├── LICENSE (MIT or Apache 2.0)
# ├── CHANGELOG.md
# ├── CONTRIBUTING.md
# ├── registry.nix           # Main export
# ├── go/
# │   ├── versions.nix       # Go versions
# │   ├── patches/
# │   │   └── cve-fix.patch
# │   └── README.md
# ├── rust/
# │   ├── versions.nix
# │   ├── patches/
# │   └── README.md
# ├── python/
# │   ├── versions.nix
# │   ├── patches/
# │   └── README.md
# ├── cxx/
# │   ├── versions.nix
# │   └── README.md
# └── tests/
#     └── verify-entries.nix
```

### 2. Create Main Flake

`flake.nix`:

```nix
{
  description = "Community toolchain registry for Turnkey";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    in
    {
      # Main registry export
      registry = import ./registry.nix;

      # Per-language registries (for advanced users)
      registries = {
        go = import ./go/versions.nix;
        rust = import ./rust/versions.nix;
        python = import ./python/versions.nix;
        cxx = import ./cxx/versions.nix;
      };

      # Helper functions
      lib = {
        # Extend registry with custom entries
        extendRegistry = baseRegistry: customEntries: { pkgs }:
          let
            base = baseRegistry { inherit pkgs; };
            custom = customEntries { inherit pkgs; };
          in
          nixpkgs.lib.recursiveUpdate base custom;

        # Merge multiple registries
        mergeRegistries = registries: { pkgs }:
          nixpkgs.lib.foldl'
            (acc: reg: nixpkgs.lib.recursiveUpdate acc (reg { inherit pkgs; }))
            {}
            registries;
      };

      # Tests
      checks = nixpkgs.lib.genAttrs systems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # Test that all registry entries are valid
          verifyEntries = import ./tests/verify-entries.nix { inherit pkgs self; };
        }
      );
    };
}
```

### 3. Create Main Registry

`registry.nix`:

```nix
{ pkgs }:

let
  # Import language-specific versions
  goVersions = import ./go/versions.nix { inherit pkgs; };
  rustVersions = import ./rust/versions.nix { inherit pkgs; };
  pythonVersions = import ./python/versions.nix { inherit pkgs; };
  cxxVersions = import ./cxx/versions.nix { inherit pkgs; };
in
{
  # Combine all language registries
  go = goVersions;
  rust = rustVersions;
  python = pythonVersions;
  clang = cxxVersions.clang;
  gcc = cxxVersions.gcc;
}
```

### 4. Language-Specific Registries

**Go** (`go/versions.nix`):

```nix
{ pkgs }:

let
  # Helper to apply patches
  applyPatches = drv: patches:
    if patches == [] then drv
    else drv.overrideAttrs (old: {
      patches = (old.patches or []) ++ patches;
    });
in
{
  # Go 1.21.x
  "1.21" = pkgs.go_1_21;  # Latest 1.21.x
  "1.21.0" = pkgs.go_1_21;
  "1.21.5" = pkgs.go_1_21;
  "1.21.6" = pkgs.go_1_21;

  # Go 1.22.x
  "1.22" = pkgs.go_1_22;
  "1.22.0" = pkgs.go_1_22;
  "1.22.1" = pkgs.go_1_22;

  # Go 1.23.x
  "1.23" = pkgs.go_1_23;
  "1.23.0" = pkgs.go_1_23;

  # Patched versions (if needed)
  # "1.21.5-cve-fix" = applyPatches pkgs.go_1_21 [
  #   ./patches/cve-2024-xxxx.patch
  # ];

  # Convenience aliases
  "stable" = pkgs.go;  # Latest stable from nixpkgs
  "latest" = pkgs.go;
}
```

**Rust** (`rust/versions.nix`):

```nix
{ pkgs }:

{
  # Rust stable versions
  "1.75" = pkgs.rust-bin.stable."1.75.0".default or pkgs.rustc;
  "1.75.0" = pkgs.rust-bin.stable."1.75.0".default or pkgs.rustc;

  "1.76" = pkgs.rust-bin.stable."1.76.0".default or pkgs.rustc;
  "1.76.0" = pkgs.rust-bin.stable."1.76.0".default or pkgs.rustc;

  "1.77" = pkgs.rust-bin.stable."1.77.0".default or pkgs.rustc;
  "1.77.0" = pkgs.rust-bin.stable."1.77.0".default or pkgs.rustc;

  # Aliases
  "stable" = pkgs.rustc;
  "latest" = pkgs.rustc;

  # Nightly (use with caution)
  # "nightly" = pkgs.rust-bin.nightly.latest.default;
}
```

**Python** (`python/versions.nix`):

```nix
{ pkgs }:

{
  # Python 3.11
  "3.11" = pkgs.python311;
  "3.11.0" = pkgs.python311;

  # Python 3.12
  "3.12" = pkgs.python312;
  "3.12.0" = pkgs.python312;

  # Python 3.13
  "3.13" = pkgs.python313;
  "3.13.0" = pkgs.python313;

  # Aliases
  "3" = pkgs.python3;
  "latest" = pkgs.python3;
}
```

**C/C++** (`cxx/versions.nix`):

```nix
{ pkgs }:

{
  clang = {
    "16" = pkgs.clang_16;
    "17" = pkgs.clang_17;
    "18" = pkgs.clang_18;
    "latest" = pkgs.clang;
  };

  gcc = {
    "12" = pkgs.gcc12;
    "13" = pkgs.gcc13;
    "14" = pkgs.gcc14;
    "latest" = pkgs.gcc;
  };
}
```

### 5. Comprehensive README

`README.md`:

```markdown
# Toolchain Registry

> Community-maintained toolchain versions for [Turnkey](https://github.com/firefly-engineering/turnkey)

This registry provides curated versions of popular toolchains (Go, Rust, Python, C/C++) for use with Turnkey's toolchain synchronization system.

## Available Toolchains

### Go

| Version | nixpkgs Package | Notes |
|---------|-----------------|-------|
| 1.21, 1.21.x | `pkgs.go_1_21` | LTS |
| 1.22, 1.22.x | `pkgs.go_1_22` | Stable |
| 1.23, 1.23.x | `pkgs.go_1_23` | Latest |
| stable, latest | `pkgs.go` | Latest stable |

[Full Go versions](./go/README.md)

### Rust

| Version | Source | Notes |
|---------|--------|-------|
| 1.75.x | nixpkgs | Stable |
| 1.76.x | nixpkgs | Stable |
| 1.77.x | nixpkgs | Latest |
| stable | nixpkgs | Latest stable |

[Full Rust versions](./rust/README.md)

### Python

| Version | nixpkgs Package |
|---------|-----------------|
| 3.11 | `pkgs.python311` |
| 3.12 | `pkgs.python312` |
| 3.13 | `pkgs.python313` |

[Full Python versions](./python/README.md)

### C/C++

**Clang**: 16, 17, 18, latest
**GCC**: 12, 13, 14, latest

[Full C/C++ versions](./cxx/README.md)

## Usage

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

[rust]
version = "1.76"
```

## Extending the Registry

Add your own versions:

```nix
{
  turnkey.toolchains.registry = toolchain-registry.lib.extendRegistry
    toolchain-registry.registry
    ({ pkgs }: {
      go."1.24.0" = pkgs.go_1_24;  # Add new version
      nodejs."20" = pkgs.nodejs_20;  # Add new toolchain
    });
}
```

## Contributing

We welcome contributions! See [CONTRIBUTING.md](./CONTRIBUTING.md)

### Adding a Version

1. Update `<language>/versions.nix`
2. Test: `nix flake check`
3. Update README
4. Submit PR

### Reporting Issues

- Version not working: [Open issue](https://github.com/firefly-engineering/toolchain-registry/issues)
- Version missing: [Request version](https://github.com/firefly-engineering/toolchain-registry/issues/new?template=version-request.md)

## Versioning

This registry uses **date-based versioning**: `YYYY.MM.PATCH`

- **YYYY.MM**: Release month
- **PATCH**: Bug fixes within month

Adding versions: Minor update (no breaking change)
Removing versions: Major update (breaking change)

## Changelog

See [CHANGELOG.md](./CHANGELOG.md)

## License

Apache 2.0 OR MIT (your choice)
```

### 6. Contribution Guide

`CONTRIBUTING.md`:

```markdown
# Contributing to Toolchain Registry

Thanks for contributing! This registry is community-maintained.

## Adding a New Version

### 1. Find the nixpkgs package

```bash
nix search nixpkgs go
# Find: pkgs.go_1_24
```

### 2. Add to language file

Edit `go/versions.nix`:

```nix
{
  "1.24" = pkgs.go_1_24;
  "1.24.0" = pkgs.go_1_24;
}
```

### 3. Test

```bash
nix flake check  # Verify all entries
nix build .#checks.x86_64-linux.verifyEntries
```

### 4. Update README

Add to version table in main README.md

### 5. Submit PR

- Clear title: "Add Go 1.24"
- Description: Why adding this version

## Adding a Patch

### 1. Create patch file

Place in `<language>/patches/`

### 2. Apply in versions.nix

```nix
"1.21.5-cve-fix" = applyPatches pkgs.go_1_21 [
  ./patches/cve-2024-xxxx.patch
];
```

### 3. Document

Create `patches/README.md` entry explaining the patch

## Style Guide

- **Version keys**: Use semantic versions ("1.21.5", not "go1.21.5")
- **Aliases**: Provide "stable", "latest" where appropriate
- **Comments**: Explain non-obvious choices
- **Testing**: All changes must pass `nix flake check`

## Release Process

Maintainers follow this process:

1. Merge PRs
2. Update CHANGELOG.md
3. Tag release: `git tag YYYY.MM.PATCH`
4. Push: `git push --tags`
5. GitHub Release with notes
```

### 7. Tests

`tests/verify-entries.nix`:

```nix
{ pkgs, self }:

let
  registry = self.registry { inherit pkgs; };

  # Test that all entries can be evaluated
  testToolchain = name: versions:
    pkgs.lib.mapAttrsToList (version: deriv:
      # Try to access outPath to verify derivation is valid
      pkgs.runCommand "test-${name}-${version}" {} ''
        echo "Testing ${name} ${version}"
        echo "Path: ${deriv}"
        touch $out
      ''
    ) versions;

  allTests = pkgs.lib.flatten (
    pkgs.lib.mapAttrsToList testToolchain registry
  );

in
pkgs.symlinkJoin {
  name = "registry-verification";
  paths = allTests;
}
```

### 8. CI/CD

`.github/workflows/ci.yml`:

```yaml
name: CI

on: [push, pull_request]

jobs:
  verify:
    strategy:
      matrix:
        system: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.system }}

    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v24

      - name: Verify all registry entries
        run: nix flake check -L

      - name: Test with Turnkey
        run: |
          # Create test project using this registry
          nix flake init -t github:firefly-engineering/turnkey#minimal
          # Modify to use this registry
          # Test build
```

## Implementation Steps

1. Create GitHub repository
2. Set up directory structure
3. Create main flake and registry
4. Add Go versions
5. Add Rust versions
6. Add Python versions
7. Add C/C++ versions
8. Create comprehensive README with version tables
9. Create contribution guide
10. Set up tests
11. Configure CI/CD
12. Initial commit and push

## Testing

```bash
# Test registry exports correctly
cd toolchain-registry/
nix flake show

# Test all entries
nix flake check

# Test with Turnkey
# (Create test project that uses this registry)

# Verify versions listed in README match actual
nix eval .#registry --apply 'r: builtins.attrNames (r { }).go'
```

## Related Documentation

- Tasks: `TASKS.md` (Phase 8.3)
- Phase 8.2: Turnkey repository

## Next Steps

After completing this task:
- Test turnkey + registry integration
- Phase 8.4: Migrate this repository (`phase8-04-migrate-this-repo.md`)

## Notes

- **Community focus**: Design for community contribution
- **Documentation**: List all versions clearly
- **Testing**: Ensure all entries valid
- **Versioning**: Clear versioning policy
- **Maintenance**: Plan for ongoing updates
- **Deprecation**: Document when old versions removed
- **Security**: Track CVEs, add patches quickly
- **Quality**: Test that all entries actually work

# Phase 0.6: Write User Documentation

## Overview

Create comprehensive documentation for downstream repositories that want to use the toolchain synchronization module. This documentation should enable users to get started quickly and configure the module for their needs.

## Context

At this point (after Phases 0.1-0.5), the module is functionally complete:
- ✅ Module structure and API defined
- ✅ Default registry created
- ✅ Resolution logic implemented
- ✅ Shell generation working
- ✅ Buck2 config generation working

Now we need documentation so others can **use** it. This documentation will be refined in Phase 1.4 and will eventually move to the `turnkey` repository in Phase 8.

## Prerequisites

- Phase 0.1-0.5: Module implementation complete
- Working example in this repository (dog-fooding)
- Understanding of target user persona (developers setting up new repos)

## Success Criteria

- [ ] "Getting Started" guide exists and is clear
- [ ] Configuration reference documents all module options
- [ ] Custom registry guide with examples
- [ ] Troubleshooting guide for common issues
- [ ] Documentation tested with fresh user
- [ ] Examples work out-of-the-box

## Implementation Guidance

### 1. Create Documentation Structure

```
docs/src/user-guide/
├── getting-started.md      # Quick start for new users
├── configuration.md        # Module options reference
├── custom-registry.md      # How to create/extend registries
├── troubleshooting.md      # Common problems and solutions
└── examples/
    ├── minimal.md          # Simplest possible setup
    ├── multi-language.md   # Using multiple toolchains
    └── custom-registry.md  # Custom registry example
```

### 2. Getting Started Guide

Create `docs/src/user-guide/getting-started.md`:

```markdown
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
```

### 3. Configuration Reference

Create `docs/src/user-guide/configuration.md`:

```markdown
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
```

### 4. Custom Registry Guide

Create `docs/src/user-guide/custom-registry.md`:

```markdown
# Custom Toolchain Registry

## Registry Structure

A registry maps version strings to Nix derivations:

```nix
{ pkgs }:
{
  <toolchain-name> = {
    "<version-string>" = <nix-derivation>;
  };
}
```

## Creating a Custom Registry

### Option 1: From Scratch

```nix
# my-registry.nix
{ pkgs }:
{
  go = {
    "1.21.5" = pkgs.go_1_21;
    "1.24.0" = pkgs.go_1_24;  # Custom version
  };

  rust = {
    "custom" = pkgs.rust.override {
      # Custom Rust with specific configuration
    };
  };
}
```

Use it:
```nix
firefly.toolchains.registry = ./my-registry.nix;
```

### Option 2: Extend Default Registry

```nix
# additions.nix
{ pkgs, defaultRegistry }:

lib.recursiveUpdate defaultRegistry {
  go."1.24.0" = pkgs.go_1_24;  # Add new version

  myCustomTool."1.0.0" = pkgs.myTool;  # Add new toolchain
}
```

## Adding Patches

```nix
{ pkgs }:
{
  go = {
    "1.21.5-patched" = pkgs.go_1_21.overrideAttrs (old: {
      patches = (old.patches or []) ++ [
        ./patches/go-security-fix.patch
      ];
    });
  };
}
```

Use in `toolchain.toml`:
```toml
[go]
version = "1.21.5-patched"
```
```

### 5. Troubleshooting Guide

Create `docs/src/user-guide/troubleshooting.md`:

```markdown
# Troubleshooting

## Path Mismatch: Shell vs Buck2

**Symptom**: `which go` and `buck2 audit config go_bin` return different paths.

**Cause**: Buck2 configs not regenerated after toolchain change.

**Solution**:
```bash
# Regenerate Buck2 configs
generate-buck2-configs

# Or exit and re-enter shell
exit
nix develop
```

## Unknown Version Error

**Symptom**: `Unknown version '1.99.99' for toolchain 'go'`

**Cause**: Version not in registry.

**Solution**:
- Check available versions: error message lists them
- Use available version in `toolchain.toml`
- Or add custom version to registry

## toolchain.toml Not Found

**Symptom**: `Toolchain declaration file not found`

**Cause**: Missing `toolchain.toml` file.

**Solution**:
```bash
# Create toolchain.toml
cat > toolchain.toml <<EOF
[go]
version = "1.21.5"
EOF
```

## Builds Work in Shell But Fail in Buck2

**Symptom**: `go build` succeeds, `buck2 build` fails with toolchain error.

**Solution**:
1. Verify synchronization: `verify-toolchains`
2. Regenerate Buck2 configs: `generate-buck2-configs`
3. Check `.buckconfig` includes `.buckconfig.toolchains`

## Slow Shell Entry

**Symptom**: `nix develop` takes a long time.

**Cause**: Nix is building toolchains from source.

**Solution**:
- Use binary cache if available
- Check that nixpkgs version has prebuilt binaries
- Consider using `nix-direnv` for faster activation
```

### 6. Example: Minimal Setup

Create `docs/src/user-guide/examples/minimal.md`:

```markdown
# Example: Minimal Setup

Simplest possible configuration with just Go.

## flake.nix

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    firefly-toolchains.url = "github:firefly-engineering/src";
  };

  outputs = { self, nixpkgs, firefly-toolchains }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        imports = [ firefly-toolchains.flakeModules.toolchains ];
      };
    };
}
```

## toolchain.toml

```toml
[go]
version = "1.21.5"
```

## Test

```bash
nix develop
go version  # go version go1.21.5 linux/amd64
```
```

## Implementation Steps

1. Create `docs/src/user-guide/` directory
2. Write "Getting Started" guide
3. Write configuration reference
4. Write custom registry guide
5. Write troubleshooting guide
6. Create example files
7. Test all examples work
8. Get feedback from fresh user

## Testing

- [ ] Have someone unfamiliar with the system follow "Getting Started"
- [ ] Verify all code examples are correct
- [ ] Test that examples work when copy-pasted
- [ ] Check that troubleshooting covers common errors
- [ ] Ensure documentation is findable (good navigation)

## Related Documentation

- Design: `docs/src/design/toolchain-synchronization.md`
- Architecture: `docs/src/architecture.md`
- Tasks: `TASKS.md` (Phase 0.4)

## Next Steps

After completing this task:
- Phase 0.5: Self-hosting test (dog-fooding)
- Phase 1: Refinement and testing
- Phase 1.4: Polish documentation based on feedback

## Notes

- **User perspective**: Write from the user's point of view, not implementer's
- **Examples first**: Show working examples before explaining theory
- **Progressive disclosure**: Start simple, add complexity gradually
- **Copy-pasteable**: All code should work when copied directly
- **Screenshots**: Consider adding terminal screenshots for visual learners
- **Updates**: Documentation will evolve based on user feedback
- **Future**: This documentation will move to `turnkey` repository in Phase 8

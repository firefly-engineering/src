# Phase 1.4: Polish Documentation Based on Testing

## Overview

Refine and polish documentation based on learnings from downstream testing (Phase 1.3) and error handling implementation (Phase 1.1). Ensure documentation is complete, accurate, and helpful for real users.

## Context

After implementing the module and testing it from a user's perspective, we now know:
- What users actually need to know
- What confuses people
- What documentation is missing
- What examples are most helpful

This phase focuses on making the documentation **production-ready** for real users (and eventually for the community in Phase 8).

## Prerequisites

- Phase 0.6: Initial user documentation written
- Phase 1.1: Error handling implemented
- Phase 1.2: Validation tools created
- Phase 1.3: Downstream testing complete
- Feedback from fresh users testing the system

## Success Criteria

- [ ] All documentation examples work when copy-pasted
- [ ] Getting started guide takes <15 minutes to complete
- [ ] Every error message has corresponding troubleshooting entry
- [ ] API reference is complete and accurate
- [ ] Documentation has clear navigation
- [ ] Examples cover common use cases
- [ ] Screenshots/diagrams added where helpful
- [ ] Fresh user can succeed without asking questions

## Implementation Guidance

### 1. Update Getting Started Guide

Based on testing feedback:

```markdown
# Getting Started

## Prerequisites

Before you begin, ensure you have:
- Nix with flakes enabled (see [Nix installation](./nix-setup.md))
- Buck2 installed (can be installed via Nix)
- Basic understanding of Nix flakes (see [Nix flakes primer](./nix-flakes-primer.md))

## Quick Start (5 minutes)

### Step 1: Add to your flake.nix

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    firefly-toolchains.url = "github:firefly-engineering/src";
  };

  outputs = { self, nixpkgs, firefly-toolchains }:
    let
      system = "x86_64-linux";  # Change to your system: x86_64-linux, aarch64-linux, x86_64-darwin, aarch64-darwin
      pkgs = import nixpkgs { inherit system; };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        imports = [ firefly-toolchains.flakeModules.toolchains ];

        # Additional packages for your project
        packages = [ pkgs.buck2 ];
      };
    };
}
```

### Step 2: Create toolchain.toml

```bash
cat > toolchain.toml <<EOF
[go]
version = "1.21.5"
EOF
```

### Step 3: Set up Buck2

Create `.buckconfig`:

```bash
cat > .buckconfig <<EOF
[buildfile]
name = BUCK

<file:.buckconfig.toolchains>
EOF
```

### Step 4: Enter shell

```bash
nix develop

# You should see:
# 🔧 Toolchain Synchronization Active
#   Go:     go1.21.5
#
# ℹ️  Buck2 configs synchronized to same toolchains
```

### Step 5: Verify it works

```bash
# Check shell has Go
which go
# /nix/store/.../go-1.21.5/bin/go

# Check Buck2 has same Go
buck2 audit config go.go_bin
# /nix/store/.../go-1.21.5/bin/go

# Verify they match
verify-toolchains
# ✅ All toolchains synchronized!
```

## What just happened?

1. Your flake imports the toolchain synchronization module
2. The module reads `toolchain.toml` to see what versions you want
3. It resolves those versions to specific Nix packages
4. It adds those packages to your dev shell
5. It generates Buck2 configs pointing to the same packages
6. Both environments use **identical binaries**

## Next Steps

- [Add more toolchains](./multiple-toolchains.md)
- [Customize the registry](./custom-registry.md)
- [Build a project](./first-build.md)
```

### 2. Add "Common Pitfalls" Section

```markdown
# Common Pitfalls

## Forgetting to include .buckconfig.toolchains

**Symptom**: Buck2 doesn't find toolchains

**Fix**: Ensure `.buckconfig` includes the generated file:

```ini
<file:.buckconfig.toolchains>
```

## Not regenerating after toolchain change

**Symptom**: Shell and Buck2 have different versions

**Fix**: Exit and re-enter shell, or run:

```bash
generate-buck2-configs
```

## Gitignoring toolchain.toml

**Symptom**: Team members have different toolchains

**Fix**: toolchain.toml should be **committed** to git. Only gitignore generated files:

```gitignore
# DO commit
# toolchain.toml

# DON'T commit (generated)
.buckconfig.toolchains
toolchains/BUCK
toolchains/*.bzl
```
```

### 3. Create "How It Works" Deep Dive

```markdown
# How It Works: Under the Hood

## The Synchronization Problem

Traditional setups have two separate toolchain configurations:

```
Shell Environment          Buck2 Environment
─────────────────          ─────────────────
$PATH finds system go      Buck2 downloads go
/usr/bin/go                 ~/.cache/buck2/go
version: 1.20 ❌           version: 1.21 ❌

RESULT: Builds work in Buck2 but fail with `go build`
```

## Our Solution: Single Source of Truth

```
        toolchain.toml
              │
              │ Declares: "go = 1.21.5"
              │
              ├──→ Nix Registry
              │    Resolves: "1.21.5" → /nix/store/abc-go-1.21.5
              │
      ┌───────┴────────┐
      │                │
      ▼                ▼
  Dev Shell       Buck2 Config
  ─────────       ────────────
  packages = [    [go]
    /nix/store/   go_bin = /nix/store/
    abc-go-1.21.5 abc-go-1.21.5/bin/go
  ]

  ✅ Same binary path = Guaranteed synchronization
```

## Why Nix Store Paths Matter

Nix store paths are **content-addressed**:

```
/nix/store/abc123-go-1.21.5
           ^^^^^^
           Hash of all inputs (source, patches, build flags)
```

If **anything** changes:
- Different version → Different hash → Different path
- Applied patch → Different hash → Different path
- Build flag → Different hash → Different path

When path changes:
- Shell automatically uses new path (it's in packages)
- Buck2 config regenerates with new path
- Buck2 cache invalidates (different path = different cache key)

**Result**: No manual cache invalidation needed!

## The Registry

The registry maps user-friendly versions to Nix derivations:

```nix
{
  go = {
    "1.21.5" = pkgs.go_1_21;  # From nixpkgs
    "1.22.0" = pkgs.go_1_22;
  };
}
```

This separation allows:
- **Users** declare what they want: "1.21.5"
- **Registry** decides how to provide it: nixpkgs, custom build, with patches, etc.
- **Different orgs** can have different registries
```

### 4. Add Troubleshooting for All Error Messages

Map every error from Phase 1.1 to troubleshooting entry:

```markdown
# Troubleshooting Guide

## Error: "Toolchain declaration file not found"

**Full error**:
```
Toolchain declaration file not found: ./toolchain.toml

To fix this, create a toolchain.toml file:
  ...
```

**Cause**: No `toolchain.toml` in repository root

**Solution**: Create the file as shown in error message, or configure a different path:

```nix
firefly.toolchains.declarationFile = ./config/my-toolchains.toml;
```

---

## Error: "Unknown version 'X' for toolchain 'Y'"

**Full error**:
```
Unknown version '1.99' for toolchain 'go'

Available versions for 'go':
  1.21
  1.21.5
  1.22
  1.22.0
```

**Cause**: Requested version not in registry

**Solution**: Either:
1. Use an available version from the list
2. Add the version to a custom registry (see [Custom Registry Guide](./custom-registry.md))

---

[Continue for all errors from Phase 1.1...]
```

### 5. Add API Reference

Complete reference for all options:

```markdown
# API Reference

## Module Options

### `firefly.toolchains.registry`

- **Type**: `path`
- **Default**: Module's built-in default registry
- **Example**: `./my-registry.nix`

Description of what this option does...

### `firefly.toolchains.declarationFile`

[Full documentation for each option...]

## toolchain.toml Schema

### `[<toolchain-name>]`

Valid toolchain names depend on registry. Default registry provides:
- `go` - Go programming language
- `rust` - Rust toolchain
- `python` - Python interpreter
- `clang` - Clang/LLVM C/C++ compiler
- `gcc` - GCC C/C++ compiler

### `version = "<string>"`

Version string to use. Must match an entry in the registry.

Examples:
```toml
[go]
version = "1.21.5"  # Specific version

[go]
version = "1.21"  # Latest 1.21.x (if registry provides alias)

[rust]
version = "stable"  # Special version (if registry provides)
```
```

### 6. Add Examples Repository

Create `docs/src/user-guide/examples/` with complete working examples:

```markdown
# Examples

## Minimal Go Project

See: `examples/minimal-go/`

Complete working example:
- [flake.nix](../../examples/minimal-go/flake.nix)
- [toolchain.toml](../../examples/minimal-go/toolchain.toml)
- [Source code](../../examples/minimal-go/hello/)

## Multi-Language Project

See: `examples/multi-language/`

Demonstrates Go + Rust + Python in one project.

## Custom Registry with Patches

See: `examples/custom-registry/`

Shows how to create custom registry with security patches.

[... more examples ...]
```

### 7. Add Visual Diagrams

Create or source diagrams:

```markdown
# Architecture Diagrams

## Synchronization Flow

[Include mermaid diagram or image showing flow from toolchain.toml to shell and Buck2]

## Cache Invalidation

[Diagram showing how Nix store path change triggers Buck2 cache invalidation]
```

## Implementation Steps

1. Review all documentation with fresh eyes
2. Test every example by copy-pasting
3. Update getting started based on testing feedback
4. Add "Common Pitfalls" section
5. Create "How It Works" deep dive
6. Complete API reference
7. Map all errors to troubleshooting entries
8. Create working examples directory
9. Add diagrams/visuals
10. Get fresh user to review
11. Iterate based on feedback

## Testing

Documentation testing checklist:

```bash
# Test 1: Can fresh user complete getting started in <15 minutes?
# Recruit someone unfamiliar with the system
# Time them following the guide
# Note where they get stuck

# Test 2: Do all code examples work?
# Copy-paste each example
# Verify it works without modification

# Test 3: Can user find answer to common questions?
# Ask user to solve common problems using only docs
# If they can't find answer quickly, improve navigation/content

# Test 4: Is API reference accurate?
# Compare every option in reference to actual implementation
# Verify defaults are correct
# Check examples work
```

## Related Documentation

- All documentation in `docs/src/user-guide/`
- Design: `docs/src/design/toolchain-synchronization.md`
- Tasks: `TASKS.md` (Phase 1.4)

## Next Steps

After completing this task:
- Phase 2: Buck2 caching validation
- Phase 6: CI/CD integration documentation
- Phase 8: Prepare documentation for extraction

## Notes

- **User testing is critical**: No amount of internal review beats real users
- **Examples over explanation**: Show working code first, explain second
- **Progressive disclosure**: Don't overwhelm with all details upfront
- **Accurate**: Wrong documentation is worse than no documentation
- **Maintainable**: Keep docs close to code, update together
- **Searchable**: Use good headings and keywords
- **Screenshots**: Consider terminal screenshots for key steps
- **Videos**: Consider short screencast for getting started
- **Community**: This documentation will serve community users in Phase 8

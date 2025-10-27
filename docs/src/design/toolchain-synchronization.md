# Toolchain Synchronization Architecture

## Overview

The Firefly Engineering monorepo uses two distinct toolchain execution contexts:

1. **Native tooling**: Direct invocation of language tools (e.g., `go build`, `cargo build`)
2. **Buck2 builds**: Hermetic builds using Buck2's execution environment

The fundamental challenge is ensuring these two contexts use **exactly the same toolchain versions and binaries**, not just similar ones. This document describes the architecture that achieves guaranteed synchronization through a single source of truth with backend-agnostic configuration.

## Problem Statement

### The Two Toolchain Challenge

In a typical monorepo setup, developers need:

- **Native development experience**: Running `go test`, `cargo check`, using IDE language servers
- **Hermetic CI/CD builds**: Reproducible builds via Buck2 with explicit dependencies

Traditional approaches create drift:

```
❌ Traditional Approach (Drift-Prone)
Developer's machine: go 1.21.5 (via homebrew)
      ↓
CI environment: go 1.21.3 (via docker image)
      ↓
Buck2 toolchain: go 1.21.4 (vendored in prelude)
      ↓
Result: "Works on my machine" problems
```

### Requirements for Success

1. **Guaranteed Synchronization**: Shell and Buck2 must use identical binaries
2. **Single Source of Truth**: One place to declare toolchain versions
3. **Backend Flexibility**: Support different provisioning systems (Nix, mise, etc.)
4. **Incremental Sophistication**: Start simple, grow with organizational needs
5. **Turnkey Experience**: Should work immediately after clone + setup

## Solution Architecture

### Distribution Model

This solution is packaged as a **reusable Nix flake module** that other repositories can import. This enables:

- **Turnkey adoption**: Downstream repos just add flake input + create toolchain.toml
- **Centralized maintenance**: Registry updates benefit all users
- **Customization**: Repos can override default registry or extend it
- **Zero vendor lock-in**: Solution is portable across repositories

**Evolution Path**:

1. **Initial Development** (this repository): Prototype and validate the solution with real use cases
2. **Extraction** (future): Split into TWO standalone repositories for independent versioning and broader adoption:
   - **`turnkey`**: Core synchronization mechanism (generic, no versions)
   - **`toolchain-registry`**: Curated toolchain version catalog (data)
3. **Reference Implementation**: This repository becomes a downstream consumer, demonstrating best practices

This allows rapid iteration while maintaining clean separation between mechanism and data long-term.

**Example Downstream Usage** (after extraction):
```nix
# flake.nix in downstream repo
{
  inputs = {
    turnkey.url = "github:firefly-engineering/turnkey";
    toolchain-registry.url = "github:firefly-engineering/toolchain-registry";
  };

  outputs = { self, turnkey, toolchain-registry, ... }: {
    devShells.default = turnkey.lib.mkShell {
      # Use community-maintained registry
      registry = toolchain-registry.registry;

      # Or use your own registry
      # registry = ./my-custom-registry.nix;

      # Or extend the community registry
      # registry = turnkey.lib.extendRegistry
      #   toolchain-registry.registry
      #   ./my-additions.nix;
    };
  };
}
```

Then create `toolchain.toml`:
```toml
[go]
version = "1.21.5"
```

And profit - both shell and Buck2 use synchronized toolchains!

**Why Two Repositories?**
- **Mechanism vs. Data**: Core logic separate from version catalog
- **Independent Versioning**: Registry updates (new Go version) don't require module changes
- **Flexibility**: Use `turnkey` with any registry (corporate, community, custom)
- **Community Contributions**: Easy to contribute new versions to registry without understanding mechanism

### High-Level Design

```
┌─────────────────────────────────────────────────────────────┐
│              toolchain.toml (Declaration)                   │
│                                                             │
│  [go]                                                       │
│  version = "1.21.5"                                         │
│                                                             │
│  [rust]                                                     │
│  version = "1.75.0"                                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ (lookup)
┌─────────────────────────────────────────────────────────────┐
│              Toolchain Registry (Backend)                   │
│                                                             │
│  nix/toolchains/registry.nix                                │
│                                                             │
│  go = {                                                     │
│    "1.21.5" = { pkg = pkgs.go_1_21; patches = [...]; };    │
│    "1.22.0" = { pkg = pkgs.go_1_22; patches = [...]; };    │
│  };                                                         │
│                                                             │
│  rust = {                                                   │
│    "1.75.0" = { pkg = pkgs.rust-bin...; };                 │
│    "1.76.0" = { pkg = pkgs.rust-bin...; };                 │
│  };                                                         │
│                                                             │
│  → Resolves version strings to concrete derivations         │
└─────────────────────────────────────────────────────────────┘
                              │
                ┌─────────────┴─────────────┐
                ▼                           ▼
┌──────────────────────────┐  ┌──────────────────────────┐
│   Shell Environment      │  │  Buck2 Toolchain Config  │
│                          │  │                          │
│  Nix derivation          │  │  Generated BUCK files    │
│  (devenv.sh)             │  │  - toolchains/BUCK       │
│                          │  │  - Custom prelude        │
│  Provides:               │  │                          │
│  - go binary             │  │  References:             │
│  - cargo binary          │  │  - Same Nix derivations  │
│  - IDE tools             │  │  - Same binaries         │
└──────────────────────────┘  └──────────────────────────┘
         │                              │
         │                              │
         └──────────────┬───────────────┘
                        ▼
                ✅ Same binaries
                ✅ Same versions
                ✅ Same behavior

Source of Truth = toolchain.toml + registry.nix
```

### Key Architectural Principles

#### 1. Layered Configuration with Registry Resolution

The source of truth is composed of **two complementary components**:

**Component 1: Toolchain Declaration** (`toolchain.toml`)
- Declares what versions the project needs
- Convenient shortcut for version selection
- Easy to edit for version changes (even per-branch)

```toml
[toolchain]
schema_version = "1.0"

[go]
version = "1.21.5"

[rust]
version = "1.75.0"
```

**Component 2: Toolchain Registry** (`nix/toolchains/registry.nix`)
- Resolution mechanism: version string → concrete derivation
- Contains all available versions
- Backend-specific implementation details (packages, patches, build options)

```nix
# nix/toolchains/registry.nix
{ pkgs }:

{
  go = {
    # Multiple versions available in registry
    "1.21.5" = {
      package = pkgs.go_1_21;
      patches = [ ./patches/go-security-1.21.patch ];
    };
    "1.22.0" = {
      package = pkgs.go_1_22;
      patches = [ ./patches/go-security-1.22.patch ];
    };
  };

  rust = {
    "1.75.0" = {
      package = pkgs.rust-bin.stable."1.75.0".default;
      components = [ "rustfmt" "clippy" ];
    };
    "1.76.0" = {
      package = pkgs.rust-bin.stable."1.76.0".default;
      components = [ "rustfmt" "clippy" ];
    };
  };
}
```

**Resolution Process**:
```
toolchain.toml declares: go.version = "1.21.5"
         ↓
Registry lookup: registry.go."1.21.5"
         ↓
Returns: { package = pkgs.go_1_21; patches = [...]; }
         ↓
Used by shell and Buck2 generators
```

This design allows:
- ✅ **Easy version switching**: Edit one line in toolchain.toml
- ✅ **Branch-specific versions**: Different branches can use different versions
- ✅ **Centralized patches**: Patches managed in registry, applied automatically
- ✅ **Version catalog**: Registry shows all available versions at a glance

#### 2. Backend Abstraction

The architecture supports multiple provisioning backends:

```
toolchain.toml
    │
    ├─→ Nix Backend      → Shell + Buck2 (via Nix derivations)
    ├─→ Mise Backend     → Shell + Buck2 (via mise installation)
    └─→ Docker Backend   → Container + Buck2 (via docker image)
```

This allows organizations to:
- Start with simple Nix setup
- Migrate to mise for faster iteration
- Support hybrid environments (some devs on Docker, others on Nix)

#### 3. Guaranteed Binary Synchronization

Both shell and Buck2 reference **the exact same Nix derivations** resolved from the registry:

```nix
# nix/generators/resolve.nix
{ registry, toolchainDeclaration }:

let
  # Resolve go 1.21.5 from registry
  goToolchain = registry.go.${toolchainDeclaration.go.version};

  # Resolve rust 1.75.0 from registry
  rustToolchain = registry.rust.${toolchainDeclaration.rust.version};
in
{
  # For shell environment
  shellPackages = [
    goToolchain.package
    rustToolchain.package
  ];

  # For Buck2 toolchain generation
  buck2Toolchains = {
    go = {
      goRoot = "${goToolchain.package}";
      goBin = "${goToolchain.package}/bin/go";
    };
    rust = {
      rustc = "${rustToolchain.package}/bin/rustc";
      cargo = "${rustToolchain.package}/bin/cargo";
    };
  };
}
```

Buck2 toolchain definitions are generated from the same resolved derivations:

```python
# Generated: toolchains/go/BUCK
system_go_toolchain(
    name = "go",
    go_root = "/nix/store/...-go-1.21.5",  # Same as shell
    go_bin = "/nix/store/...-go-1.21.5/bin/go",
    visibility = ["PUBLIC"],
)
```

The key is that **resolution happens once**, and the result is used for both outputs.

## Buck2 Caching and Toolchain Compatibility

### The Caching Challenge

Buck2's performance depends heavily on caching build artifacts both locally and remotely. For caching to work correctly, Buck2 must be able to:

1. **Identify toolchain changes**: Detect when a toolchain has changed and invalidate affected cache entries
2. **Generate stable cache keys**: Produce reproducible hashes for identical toolchain configurations
3. **Avoid false cache hits**: Ensure that different toolchains (even similar versions) produce different cache keys
4. **Support remote caching**: Enable sharing of cached artifacts across developers and CI

### Buck2's Toolchain Hashing Mechanism

Buck2 calculates cache keys based on:

1. **Toolchain rule implementation**: The Starlark code defining the toolchain
2. **Toolchain attributes**: All parameters passed to the toolchain (binary paths, version strings, etc.)
3. **Transitive inputs**: Any files or configurations that affect the toolchain's behavior

When Buck2 evaluates a toolchain, it creates a hash that includes all of these elements. This hash becomes part of the cache key for any action using that toolchain.

### Why Nix Store Paths Are Ideal

Nix store paths are **content-addressed**, meaning the path itself encodes a hash of:
- The package source
- Build instructions
- All dependencies
- Any patches applied
- Build-time configuration

Example Nix store path:
```
/nix/store/abc123...-go-1.21.5
              ↑
         Content hash - changes when ANY input changes
```

This property makes Nix paths perfect for Buck2 caching because:

1. **Automatic invalidation**: When you update the registry (e.g., add a patch), the Nix derivation changes, producing a new store path
2. **Stable hashing**: Identical configurations always produce the same store path
3. **Explicit versioning**: The path itself is the version identifier
4. **Fine-grained changes**: Even minor changes (like adding a patch) change the hash

### Integration Strategy

#### 1. Toolchain Attributes Must Include Full Paths

Buck2 toolchain definitions must reference complete Nix store paths, not just version strings:

```python
# ✅ CORRECT - Full Nix store path
system_go_toolchain(
    name = "go",
    go_root = "/nix/store/abc123...-go-1.21.5",  # Full content-addressed path
    go_bin = "/nix/store/abc123...-go-1.21.5/bin/go",
    visibility = ["PUBLIC"],
)

# ❌ WRONG - Version string only
system_go_toolchain(
    name = "go",
    version = "1.21.5",  # Buck2 can't detect when patches change
    go_bin = "go",       # Too ambiguous
    visibility = ["PUBLIC"],
)
```

**Why this works**: Buck2 includes the `go_root` and `go_bin` attributes in its toolchain hash. When the Nix store path changes (due to patches, version updates, etc.), Buck2 sees a different toolchain and invalidates affected cache entries.

#### 2. Generated Toolchain Fingerprints

To make cache invalidation explicit, we can generate a toolchain fingerprint that Buck2 can check:

```python
# Generated: toolchains/go/BUCK
system_go_toolchain(
    name = "go",
    go_root = "/nix/store/abc123...-go-1.21.5",
    go_bin = "/nix/store/abc123...-go-1.21.5/bin/go",
    # Explicit fingerprint derived from Nix derivation hash
    fingerprint = "abc123...",  # First 8 chars of Nix store hash
    visibility = ["PUBLIC"],
)
```

#### 3. Registry Version Tracking

The registry can track metadata for cache diagnostics:

```nix
# nix/toolchains/registry.nix
{
  go = {
    "1.21.5" = {
      package = pkgs.go_1_21;
      patches = [ ./patches/CVE-2024-XXXX.patch ];

      # Metadata for humans (not used by Buck2, but helpful for debugging)
      metadata = {
        registry_version = "2024-01-15";  # When this config was updated
        patch_count = 1;
        description = "Go 1.21.5 with CVE patch";
      };
    };
  };
}
```

### Caching Scenarios

#### Scenario 1: Developer Upgrades Toolchain Version

```bash
# Edit toolchain.toml
[go]
version = "1.21.5" → "1.22.0"

# Regenerate Buck2 config
nix develop
buck2 build //...

# What happens:
# 1. Registry resolves 1.22.0 → new Nix store path
# 2. Generated BUCK file has new go_root path
# 3. Buck2 sees different toolchain attributes
# 4. Cache misses for all targets using Go toolchain
# 5. Rebuild with new toolchain, create new cache entries
```

#### Scenario 2: Security Patch Applied to Existing Version

```nix
# Update registry.nix
go."1.21.5" = {
  package = pkgs.go_1_21;
  patches = [ ./patches/CVE-2024-XXXX.patch ];  # ← New patch
};

# Nix rebuilds derivation with patch
# → New store path: /nix/store/xyz789...-go-1.21.5

# Buck2 regenerates toolchain with new path
# → Different toolchain hash
# → Cache invalidation
# → Rebuild with patched toolchain
```

#### Scenario 3: Remote Caching Across Team

```bash
# Developer A builds with Go 1.21.5
buck2 build //app:server
# → Uploads artifacts to remote cache with toolchain hash abc123...

# Developer B uses same Go 1.21.5 (same Nix store path)
buck2 build //app:server
# → Requests artifacts with toolchain hash abc123...
# → Cache hit! Downloads pre-built artifacts
# → No rebuild needed

# Developer C uses Go 1.22.0 (different Nix store path)
buck2 build //app:server
# → Requests artifacts with toolchain hash xyz789...
# → Cache miss (different toolchain)
# → Rebuilds from scratch
```

### Remote Caching Configuration

#### Buck2 Remote Execution (RE) Setup

```ini
# .buckconfig
[cache]
  mode = readwrite
  remote_cache = true
  remote_cache_url = https://cache.example.com

[build]
  # Include toolchain paths in cache key calculation
  execution_platforms = root//platforms:default
```

#### Ensuring Reproducibility for Remote Caching

For remote caching to work reliably across machines:

1. **All developers must use Nix**: Ensures identical toolchain binaries
2. **Flake lock must be committed**: Pins Nix dependencies to specific versions
3. **Toolchain paths in Buck2 config**: Generated paths must be consistent

```bash
# Verify cache key consistency
# Machine A
buck2 audit config go_bin
# /nix/store/abc123...-go-1.21.5/bin/go

# Machine B (with same flake.lock)
buck2 audit config go_bin
# /nix/store/abc123...-go-1.21.5/bin/go  ✅ Same path!

# → Cache entries are shared
```

### Validation and Debugging

#### Check Toolchain Fingerprints

```bash
# Show Buck2's toolchain hash
buck2 audit config //toolchains:go

# Show Nix derivation hash
nix-store --query --hash $(which go)

# Verify they're in sync
```

#### Diagnose Cache Misses

```bash
# Enable verbose caching logs
buck2 build //app:server -v 5

# Look for toolchain-related cache misses
# Example output:
# Cache miss: toolchain hash changed
#   Previous: abc123...
#   Current:  xyz789...
#   Reason:   go_root path changed
```

#### Test Cache Sharing

```bash
# Clean local cache
buck2 clean

# Build with remote cache
buck2 build //... --remote-cache

# Check cache hit rate
buck2 summary
# Expected: High hit rate if team uses same toolchain versions
```

### Best Practices

1. **Commit flake.lock**: Ensures all team members get identical Nix derivations
2. **Regenerate Buck2 configs in CI**: Verify generated configs match expectations
3. **Monitor cache hit rates**: Low rates may indicate toolchain version drift
4. **Document registry changes**: Help team understand when cache invalidation is expected
5. **Use branches for toolchain experiments**: Avoid disrupting main branch cache

### Implementation Checklist

Phase 1: Basic Caching Support
- [ ] Generated Buck2 configs include full Nix store paths
- [ ] Local caching works with Nix toolchains
- [ ] Toolchain changes trigger cache invalidation

Phase 2: Remote Caching
- [ ] Remote cache server configured
- [ ] Cache keys are reproducible across machines
- [ ] Team members can share cached artifacts

Phase 3: Advanced Features
- [ ] Toolchain fingerprinting for easier debugging
- [ ] Cache hit rate monitoring
- [ ] Automated cache warming for common toolchain versions

### Success Metrics

1. **Cache hit rate > 80%** for incremental builds on main branch
2. **Zero false cache hits** (different toolchains never share cache entries)
3. **Reproducible builds** across all team members using same flake.lock
4. **Fast CI builds** through remote cache sharing

## Implementation Phases

### Phase 1: Core Infrastructure

**Goal**: Establish the foundational configuration and generation pipeline with registry-based resolution.

**Deliverables**:
1. `toolchain.toml` schema definition
2. `nix/toolchains/registry.nix` - Toolchain registry with initial versions
3. Nix-based resolver: `toolchain.toml` + `registry.nix` → resolved derivations
4. Shell environment generation (devenv.sh integration)
5. Basic Buck2 toolchain file generation

**Example Registry**:
```nix
# nix/toolchains/registry.nix
{ pkgs }:
{
  go = {
    "1.21.5" = { package = pkgs.go_1_21; };
    "1.22.0" = { package = pkgs.go_1_22; };
  };
  rust = {
    "1.75.0" = { package = pkgs.rust-bin.stable."1.75.0".default; };
  };
}
```

**Example Output**:

```bash
# Developer workflow
nix develop              # Shell has go 1.21.5 (resolved from registry)
go version               # go version go1.21.5 linux/amd64

buck2 run //example:app  # Uses same go 1.21.5 binary (same resolution)
```

**Validation**:
```bash
# Verify synchronization
which go                           # /nix/store/...-go-1.21.5/bin/go
buck2 audit config go_bin          # /nix/store/...-go-1.21.5/bin/go
# ✅ Same path = guaranteed synchronization
```

### Phase 2: Prelude Customization

**Goal**: Fork and customize Buck2 prelude for toolchain integration.

**Deliverables**:
1. Forked prelude with embedded toolchains removed
2. Custom toolchain registration macros
3. Generated prelude configuration pointing to Nix toolchains

**File Structure**:
```
prelude/               # Forked from buck2-prelude
├── rust/
│   └── rust.bzl      # Modified to use system toolchain
├── go/
│   └── go.bzl        # Modified to use system toolchain
└── toolchains/
    └── register.bzl  # Auto-generated toolchain registration
```

### Phase 3: External Cell for Utilities

**Goal**: Create Nix-managed external cell with codegen tools.

**Deliverables**:
1. External cell with Buck2 file generators
2. Gazelle-like tool for dependency graph management
3. Reindeer-like tool for Rust dependency translation
4. Integration with `nix develop` for automatic availability

**Structure**:
```
# External cell managed by Nix
nix/cells/tooling/
├── BUCK                  # Cell root
├── gazelle/
│   ├── BUCK
│   └── main.go           # Buck2 file generator
├── reindeer/
│   ├── BUCK
│   └── main.rs           # Cargo → Buck2 translator
└── buck2-gen/
    ├── BUCK
    └── generator.py      # Generic Buck2 file generator
```

**Usage**:
```bash
# In shell (provided by Nix)
buck2-gazelle --update   # Regenerate BUCK files
reindeer regenerate      # Update Rust dependencies
```

### Phase 4: Incremental Sophistication

**Goal**: Support advanced use cases as organizations grow through enhanced backend registries.

**Capabilities**:
1. Custom toolchain patches (in backend registry)
2. Build-from-source options (in backend registry)
3. Multiple backend support (Nix + mise)
4. Toolchain composition (in backend registry)

**Important**: All advanced features are implemented in the **backend registry**, not in `toolchain.toml`. The declaration stays simple and backend-agnostic.

**Simple Declaration** (unchanged):
```toml
[toolchain]
schema_version = "1.0"

[go]
version = "1.21.5"

[rust]
version = "1.75.0"
```

**Advanced Backend Registry** (Nix example):
```nix
# nix/toolchains/registry.nix
{ pkgs }:
{
  go = {
    "1.21.5" = {
      # Custom patches applied transparently
      package = pkgs.go_1_21.overrideAttrs (old: {
        patches = old.patches ++ [
          ./patches/go-security.patch
          ./patches/go-perf.patch
        ];
      });
    };
  };

  rust = {
    "1.75.0" = {
      # Build from source with custom features
      package = pkgs.rust.override {
        fromSource = true;
        llvmPackages = pkgs.llvmPackages_17;
      };
    };
  };
}
```

**Why This Separation Matters**:
- A repository uses **one backend at a time** (Nix OR mise, not both simultaneously)
- Backend-specific details (patches, build recipes) must live in the backend layer
- Different backends have different mechanisms (Nix uses `overrideAttrs`, mise uses plugins, etc.)
- Keeping `toolchain.toml` simple ensures it remains backend-agnostic

**Alternative Backend Example** (hypothetical mise):
```toml
# mise/toolchains/registry.toml
[go."1.21.5"]
source = "golang-org"
patches = ["./patches/go-security.patch"]

[rust."1.75.0"]
source = "rust-lang/rust"
build_from_source = true
features = ["llvm-17"]
```

Different backends, same simple declaration in `toolchain.toml`.

## Technical Architecture

### File Organization

```
src/
├── toolchain.toml              # High-level toolchain declaration
├── nix/
│   ├── toolchains/
│   │   └── registry.nix        # Toolchain registry (version → derivation)
│   ├── generators/
│   │   ├── resolve.nix         # Resolution layer (toml + registry → derivations)
│   │   ├── shell.nix           # Shell environment generator
│   │   ├── buck2.nix           # Buck2 toolchain generator
│   │   └── prelude.nix         # Prelude customization generator
│   └── cells/
│       └── tooling/            # External cell for utilities
├── toolchains/
│   ├── BUCK                    # Generated Buck2 toolchains
│   ├── go/
│   │   ├── BUCK                # Generated
│   │   └── toolchain.bzl       # Generated
│   └── rust/
│       ├── BUCK                # Generated
│       └── toolchain.bzl       # Generated
├── prelude/                    # Forked Buck2 prelude
│   ├── rust/
│   ├── go/
│   └── toolchains/
│       └── register.bzl        # Auto-generated
└── .buckconfig
```

### Generation Pipeline

```
┌─────────────────┐     ┌─────────────────────────┐
│ toolchain.toml  │     │ nix/toolchains/         │
│                 │     │ registry.nix            │
│ [go]            │     │                         │
│ version="1.21.5"│     │ go."1.21.5" = {...}     │
└────────┬────────┘     └───────────┬─────────────┘
         │                          │
         └──────────┬───────────────┘
                    ▼
         ┌─────────────────────┐
         │ Resolution Layer    │
         │ (nix/generators/    │
         │  resolve.nix)       │
         │                     │
         │ Looks up version    │
         │ in registry         │
         │ → Returns derivation│
         └──────────┬──────────┘
                    │
         ┌──────────┴───────────┐
         ▼                      ▼
┌─────────────────┐    ┌─────────────────┐
│ Shell Generator │    │ Buck2 Generator │
│ (shell.nix)     │    │ (buck2.nix)     │
└────────┬────────┘    └────────┬────────┘
         │                      │
         ▼                      ▼
┌─────────────────┐    ┌─────────────────┐
│ devShell        │    │ toolchains/BUCK │
│ (Nix output)    │    │ prelude/        │
│                 │    │                 │
│ /nix/store/...  │    │ /nix/store/...  │
│    └─ Same path ─────────────┘         │
└─────────────────┘    └─────────────────┘
```

**Key Point**: Resolution happens **once** at the top of the pipeline. Both generators receive the same resolved derivations, guaranteeing synchronization.

### Synchronization Mechanism

The key to synchronization is using **Nix store paths** as the common reference, with resolution happening once via the registry:

```nix
# nix/generators/buck2.nix
{ resolvedToolchains }:
# resolvedToolchains comes from resolve.nix which looked up versions in registry

let
  # Extract Nix store paths from resolved derivations
  goPath = "${resolvedToolchains.go.package}";
  rustPath = "${resolvedToolchains.rust.package}";
in
pkgs.writeText "toolchains-BUCK" ''
  # Generated by nix/generators/buck2.nix
  # DO NOT EDIT MANUALLY
  # Resolved from toolchain.toml via registry.nix

  system_go_toolchain(
      name = "go",
      go_root = "${goPath}",
      go_bin = "${goPath}/bin/go",
      visibility = ["PUBLIC"],
  )

  system_rust_toolchain(
      name = "rust",
      rustc = "${rustPath}/bin/rustc",
      cargo = "${rustPath}/bin/cargo",
      visibility = ["PUBLIC"],
  )
''
```

**Example Resolution Flow**:
```nix
# nix/generators/resolve.nix
{ pkgs, lib }:

let
  # Load registry
  registry = import ../toolchains/registry.nix { inherit pkgs; };

  # Parse toolchain.toml
  declaration = lib.importTOML ../../toolchain.toml;

  # Resolve each toolchain
  resolvedGo = registry.go.${declaration.go.version};
  resolvedRust = registry.rust.${declaration.rust.version};
in
{
  go = resolvedGo;      # { package = <derivation>; patches = [...]; }
  rust = resolvedRust;  # { package = <derivation>; components = [...]; }
}
```

This resolved data structure is then passed to **both** shell and Buck2 generators, ensuring they reference identical derivations.

## Benefits

### For Developers

1. **Guaranteed Consistency**: Shell and Buck2 always use identical toolchains
2. **Fast Incremental Builds**: Buck2 caching works correctly with automatic cache invalidation
3. **Fast Onboarding**: Single `nix develop` sets up everything correctly
4. **Familiar Workflow**: Native tools (`go build`, `cargo test`) work as expected
5. **IDE Integration**: Language servers work with correct toolchain versions

### For Organizations

1. **Reproducible Builds**: Exact same toolchains in dev, CI, and production
2. **High-Performance CI**: Remote caching works reliably across team and CI with content-addressed toolchains
3. **Easy Version Management**: Switch toolchain versions by editing one line in toolchain.toml
4. **Branch-Specific Versions**: Different branches can use different toolchain versions seamlessly
5. **Security Patching**: Apply patches centrally in registry without waiting for upstream
6. **Automatic Cache Invalidation**: Nix content-addressing ensures correct cache behavior without manual intervention
7. **Compliance**: Complete audit trail of toolchain versions and modifications in registry
8. **Incremental Adoption**: Start simple, add sophistication as needed

**Example Use Case**: Security team discovers vulnerability in Go 1.21.5
```nix
# Update registry.nix to apply patch
go."1.21.5" = {
  package = pkgs.go_1_21;
  patches = [ ./patches/CVE-2024-XXXX.patch ];  # ← Add patch
};
# All projects using 1.21.5 automatically get patched version on next nix develop
```

### For the Ecosystem

1. **Backend Flexibility**: Not locked into Nix (can swap to mise, Docker, etc.)
2. **Standard Compliance**: Projects remain compatible with language ecosystems
3. **Extractability**: Components can be extracted and used outside the monorepo
4. **Open Source Friendly**: Architecture is portable and documentable

## Migration Path

### Current State → Target State

**Current**:
- Nix provides tools in shell
- Buck2 configured with "system toolchains"
- Implicit synchronization (works but not guaranteed)

**Phase 1 (Explicit Synchronization)**:
- Add `toolchain.toml` with current versions
- Generate Buck2 toolchain files from Nix
- Verify shell and Buck2 use same binaries

**Phase 2 (Enhanced Capabilities)**:
- Fork and customize prelude
- Add external cell for utilities
- Support advanced configuration options

**Phase 3 (Production Ready)**:
- Multi-backend support
- Comprehensive testing
- Documentation and examples

## Future Directions

### Backend Plugins

Support pluggable backends via a common interface:

```nix
# nix/backends/interface.nix
{
  # Every backend must implement
  parseToolchainConfig = config: { ... };
  generateShellEnv = toolchains: { ... };
  generateBuck2Config = toolchains: { ... };
}

# nix/backends/nix.nix - Nix backend
# nix/backends/mise.nix - Mise backend
# nix/backends/docker.nix - Docker backend
```

### Toolchain Composition

Allow combining toolchains from multiple sources (implemented in backend registry):

**Simple Declaration** (unchanged):
```toml
[go]
version = "1.21.5"
```

**Registry Implementation** (Nix example):
```nix
# nix/toolchains/registry.nix
{
  go = {
    "1.21.5" = {
      package = pkgs.go_1_21;
      # Compose additional tools in the backend
      additionalTools = [
        (pkgs.gopls.overrideAttrs (old: {
          # Custom gopls build from latest source
          src = pkgs.fetchFromGitHub {
            owner = "golang";
            repo = "tools";
            rev = "latest-commit";
          };
        }))
      ];
    };
  };
}
```

### Cross-Platform Support

Support multiple platforms (handled in backend registry):

**Simple Declaration** (unchanged):
```toml
[go]
version = "1.21.5"
```

**Registry Implementation** (Nix automatically handles platforms):
```nix
# nix/toolchains/registry.nix
{
  go = {
    "1.21.5" = {
      # Nix automatically selects correct platform
      package = pkgs.go_1_21;
      # On linux-x64: downloads linux tarball
      # On darwin-arm64: downloads macOS arm64 tarball
      # Platform detection is automatic via Nix's builtins.currentSystem
    };
  };
}
```

**Note**: Cross-platform support is a backend concern. Nix handles this automatically through its platform detection. Other backends (mise, Docker) would implement platform support in their own registry format.

## Success Metrics

1. **Binary Identity**: Shell and Buck2 `go version` output must be identical
2. **Zero Configuration Drift**: No manual `.buckconfig` or shell config needed
3. **Fast Setup**: `nix develop` completes in < 60 seconds on first run
4. **High Cache Hit Rate**: > 80% cache hits for incremental builds on main branch
5. **Reliable Remote Caching**: Team members successfully share cached artifacts
6. **Zero False Cache Hits**: Different toolchains never produce incorrect cache hits
7. **Developer Satisfaction**: Developers prefer monorepo environment to standalone projects

## Related Documents

- [Architecture Overview](../architecture.md): High-level monorepo architecture
- [Supply Chain Security](../supply-chain-security.md): Security implications of toolchain management
- [External Cell Dependency Management](./ext-cell-dependency-management.md): Alternative dependency management approach
- [Go Dependency Management Roadmap](./go-dependency-management-roadmap.md): Language-specific dependency handling

## Conclusion

This architecture solves the fundamental "two toolchains" problem through a **registry-based resolution system** that guarantees synchronization. The source of truth is composed of two complementary components:

1. **toolchain.toml**: High-level declaration of what versions the project needs
2. **registry.nix**: Resolution mechanism mapping versions to concrete derivations

This separation provides:
- **Ease of use**: Change versions by editing one line in toolchain.toml
- **Centralized control**: All version implementations (patches, build options) in registry
- **Branch flexibility**: Different branches can use different versions
- **Guaranteed sync**: Resolution happens once, used for both shell and Buck2

The layered configuration approach provides flexibility for organizations at different maturity levels, while the backend abstraction ensures the solution can evolve with changing ecosystem tools (Nix → mise → Docker).

**Reusable Two-Repository Architecture**: By splitting into mechanism (`turnkey`) and data (`toolchain-registry`), organizations can:
- Import the core module into any repository with minimal configuration
- Use the community-maintained registry or bring their own
- Benefit from registry updates without touching the core mechanism
- Extend or override the default registry for organization-specific needs
- Maintain zero vendor lock-in (solution is completely portable)
- Contribute to registry without understanding mechanism internals

The key innovations are:

1. **Registry-resolved Nix derivations** as the common reference point for both shell and Buck2 toolchains, eliminating version drift
2. **Content-addressed Nix store paths** that provide automatic, cryptographically-verified cache invalidation for Buck2
3. **Single resolution step** that guarantees identical binaries across native tooling and hermetic builds

The registry acts as the single authoritative source for toolchain implementations, while Nix's content-addressing naturally solves Buck2's caching requirements without additional tooling or configuration. This creates a turnkey developer experience with industrial-strength build caching.

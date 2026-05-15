# Firefly Engineering Monorepo Architecture

```admonish info
This architecture is not fully implemented yet.
```

## Table of Contents

1. [Overview](#overview)
2. [Design Principles](#design-principles)
3. [Architecture Components](#architecture-components)
4. [Nix-Based Toolchain Management](#nix-based-toolchain-management)
5. [Buck2 Build System Integration](#buck2-build-system-integration)
6. [Third-Party Dependency Management](#third-party-dependency-management)
7. [Language-Specific Solutions](#language-specific-solutions)
8. [Transparent Native Tooling](#transparent-native-tooling)
9. [Implementation Details](#implementation-details)
10. [Benefits](#benefits)

## Overview

The Firefly Engineering monorepo employs a hybrid architecture that combines **Nix** for environment and toolchain management with **Buck2** as the primary build system. This architecture is designed to provide hermetic builds, reproducible environments, and seamless integration with native language toolchains while avoiding the typical "ecosystem contamination" problems of traditional monorepos.

### The Two Toolchain Challenge

A fundamental architectural challenge in this monorepo is managing **two distinct toolchain execution contexts**:

1. **Native tooling context**: Developers using `go build`, `cargo check`, IDE language servers, etc.
2. **Buck2 build context**: Hermetic builds with explicit dependency tracking

The key innovation of this architecture is **guaranteed synchronization**: both contexts use the exact same toolchain binaries, not just similar versions. This is achieved through a **single source of truth** configuration that generates both the development shell environment and Buck2 toolchain definitions from the same Nix derivations.

See [Toolchain Synchronization](./design/toolchain-synchronization.md) for the detailed design.

### Key Components

- **Nix + Flakes**: Provides reproducible development environments and toolchain provisioning
- **Buck2**: Fast, hermetic build system with excellent language support
- **Toolchain Synchronization**: Single source of truth (`toolchain.toml`) generates both shell and Buck2 configurations
- **System Toolchains**: Buck2 references the exact same Nix-provided binaries used in the shell
- **Transparent Dependency Management**: Third-party dependencies managed via Nix with transparent bridging to build tools

## Design Principles

### 1. Hermetic and Reproducible Builds
All builds should be completely reproducible across different environments and machines, with all dependencies explicitly declared and versioned.

### 2. Non-Contaminating Ecosystem Integration
Unlike traditional monorepos that require specialized tooling, our architecture allows standard language tools to work seamlessly both within and outside the monorepo context.

### 3. Transparent Dependency Management
Third-party dependencies are managed centrally through Nix but consumed transparently by both Buck2 and native tooling.

### 4. Minimal Vendor Lock-in
Components built in this monorepo should be easily extractable and usable as standalone projects without Buck2-specific modifications.

### 5. Developer Experience First
The architecture prioritizes developer productivity with fast builds, easy onboarding, and familiar tooling.

## Architecture Components

```
┌─────────────────────────────────────────────────────────────┐
│                     Developer Interface                     │
├─────────────────────────────────────────────────────────────┤
│  Buck2 CLI    │   Native Tools    │   IDE Integration       │
│  buck2 build  │   cargo build     │   rust-analyzer         │
│  buck2 test   │   go build        │   gopls                 │
│  buck2 run    │   python -m       │   pyright               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Build System Layer                       │
├─────────────────────────────────────────────────────────────┤
│                         Buck2                               │
│  ┌─────────────────┐ ┌─────────────────┐ ┌──────────────┐   │
│  │ System Toolchain│ │ Build Rules     │ │ Target Graph │   │
│  │ Integration     │ │ (rust_binary,   │ │ Resolution   │   │
│  │                 │ │  go_binary,     │ │              │   │
│  │                 │ │  python_binary) │ │              │   │
│  └─────────────────┘ └─────────────────┘ └──────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  Dependency Bridge Layer                    │
├─────────────────────────────────────────────────────────────┤
│   GOPROXY        │   Cargo Registry   │   Python Index      │
│   (Nix Store)    │   (Nix Store)      │   (Nix Store)       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  Toolchain & Environment                    │
├─────────────────────────────────────────────────────────────┤
│                         Nix + Flakes                        │
│  ┌─────────────────┐ ┌─────────────────┐ ┌──────────────┐   │
│  │ Dev Environment │ │ System Tools    │ │ Dependencies │   │
│  │ (devenv)        │ │ (rustc, go,     │ │ (3rd party   │   │
│  │                 │ │  python, etc.)  │ │  packages)   │   │
│  └─────────────────┘ └─────────────────┘ └──────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Nix-Based Toolchain Management

### Architecture Overview

The repository uses Nix with flakes to provide a consistent development environment across all team members and CI systems. The toolchain management follows a **layered configuration approach**:

1. **Abstract Definition**: `toolchain.toml` declares high-level toolchain requirements
2. **Backend Implementation**: Nix recipes translate abstract definitions to concrete derivations
3. **Dual Output**: Same Nix derivations power both shell environment and Buck2 toolchains

This architecture ensures that `go version` in the shell and `go version` invoked by Buck2 return identical results, because they're literally the same binary.

**Key Files:**
- `toolchain.toml`: Single source of truth for toolchain versions
- `flake.nix`: Main flake configuration
- `nix/toolchain.nix`: Backend-specific toolchain configuration
- `nix/generators/`: Code generators for shell and Buck2 configs
- `nix/shell.nix`: Development environment specification
- `nix/devenv/agents.nix`: Claude Code integration

### Toolchain Definition

**High-Level Definition** (`toolchain.toml`):
```toml
[toolchain]
schema_version = "1.0"

[go]
version = "1.21.5"

[rust]
version = "1.75.0"

[python]
version = "3.11"
```

**Backend Configuration** (`nix/toolchain.nix`):
```nix
# Backend-specific implementation details
{
  go = {
    version = "1.21.5";
    package = pkgs.go_1_21;
    sha256 = "sha256-...";
  };

  rust = {
    version = "1.75.0";
    package = pkgs.rust-bin.stable."1.75.0".default;
  };
}
```

### Environment Specification

```nix
# nix/shell.nix
{
  languages = {
    cplusplus.enable = true;
    go.enable = true;
    jsonnet.enable = true;
    nix.enable = true;
    python.enable = true;
    rust.enable = true;
    shell.enable = true;
  };

  packages = with pkgs; [
    buck2
    nix
    git
    jujutsu
  ];
}
```

This configuration ensures that all required toolchains are available in the development shell with pinned versions.

### Environment Variable Configuration

The Nix shell also sets up environment variables that configure language-specific tools to use our centralized dependency management:

```nix
# nix/shell.nix (extended configuration)
{
  enterShell = ''
    echo "🚀 Welcome to Firefly Engineering Monorepo"

    # Go configuration
    export GOPROXY="http://localhost:8080/proxy"
    export GOPATH="$BUCK_OUT/go"
    export GOCACHE="$BUCK_OUT/go/cache"

    # Rust configuration - non-intrusive registry setup
    export CARGO_HOME="$BUCK_OUT/cargo"
    export CARGO_REGISTRY_DEFAULT="firefly"
    export CARGO_REGISTRIES_FIREFLY_INDEX="file://$NIX_STORE_PATH/registry-index"
    export CARGO_NET_OFFLINE="true"

    # Python configuration
    export PIP_INDEX_URL="file://$NIX_STORE_PATH/python-index/simple"
    export PYTHONPATH="$BUCK_OUT/python/lib"
  '';
}
```

This approach ensures that:
- **No User File Modification**: Environment variables avoid touching `~/.cargo/config.toml`, `~/.gitconfig`, etc.
- **Automatic Setup**: All configuration happens transparently when entering the shell
- **Consistent Behavior**: Both Buck2 and native tools use the same dependency sources
- **Easy Cleanup**: Exit the shell and all configuration is gone

### Benefits of Nix Integration

1. **Reproducible Environments**: Every developer and CI system gets identical tool versions
2. **Dependency Isolation**: No conflicts with system-installed tools
3. **Easy Onboarding**: Single `nix develop` or `direnv allow` command sets up everything
4. **Patch Management**: Ability to patch dependencies at the Nix level without affecting consumption

## Buck2 Build System Integration

### System Toolchain Strategy

Buck2 is configured to use "system toolchains" that reference the **exact same Nix derivations** used in the development shell. This guarantees binary-level synchronization between native tooling and Buck2 builds.

**Generated Configuration:**

The Buck2 toolchain definitions are **automatically generated** from the same `toolchain.toml` and `nix/toolchain.nix` that produce the shell environment:

```python
# toolchains/BUCK (Generated - DO NOT EDIT MANUALLY)
# Generated from toolchain.toml via nix/generators/buck2.nix

system_go_toolchain(
    name = "go",
    go_root = "/nix/store/...-go-1.21.5",  # Same path as shell
    go_bin = "/nix/store/...-go-1.21.5/bin/go",
    visibility = ["PUBLIC"],
)

system_rust_toolchain(
    name = "rust",
    rustc = "/nix/store/...-rust-1.75.0/bin/rustc",
    cargo = "/nix/store/...-rust-1.75.0/bin/cargo",
    visibility = ["PUBLIC"],
)

system_python_bootstrap_toolchain(
    name = "python_bootstrap",
    visibility = ["PUBLIC"],
)

system_cxx_toolchain(
    name = "cxx",
    visibility = ["PUBLIC"],
)
```

### Generation Pipeline

```
toolchain.toml → nix/toolchain.nix → nix/generators/buck2.nix → toolchains/BUCK
                                   ↘ nix/generators/shell.nix → devShell
```

Both generators reference the same Nix derivations, ensuring:
- ✅ Identical binary paths
- ✅ Same versions
- ✅ Same patches and configurations
- ✅ Zero possibility of drift

### Buck2 Configuration

```ini
# .buckconfig
[cells]
  root = .
  toolchains = toolchains

[build]
  execution_platforms = prelude//platforms:default
```

This setup allows Buck2 to find and use the toolchains provided by Nix in the development environment. The critical difference from traditional "system toolchains" is that these paths are **generated and guaranteed** to match the shell environment, not just assumed to be compatible.

### Caching Compatibility

A crucial aspect of this architecture is its compatibility with Buck2's caching mechanism. Nix store paths are **content-addressed**, meaning the path itself changes whenever the toolchain changes (version updates, patches, configuration). This property is ideal for Buck2 caching:

- **Automatic cache invalidation**: When a toolchain changes, the Nix store path changes, and Buck2 automatically invalidates affected cache entries
- **Stable cache keys**: Identical toolchains produce identical Nix store paths, enabling reliable cache sharing
- **Remote caching**: Teams can share cached artifacts because all developers using the same `flake.lock` get identical toolchain paths

See [Toolchain Synchronization - Buck2 Caching](./design/toolchain-synchronization.md#buck2-caching-and-toolchain-compatibility) for detailed analysis.

## Third-Party Dependency Management

### Philosophy

Rather than vendoring all third-party dependencies like traditional monorepos (e.g., Google's Bazel setup), we manage dependencies at the Nix level. This approach provides:

- **Centralized Version Management**: All dependency versions declared in Nix
- **Patch Capability**: Apply patches via Nix derivations when needed
- **Transparent Consumption**: Dependencies available to both Buck2 and native tooling
- **Storage Efficiency**: Dependencies shared across projects via Nix store

### Planned Implementation Strategy

#### Current State
Dependencies are currently managed through standard language-specific mechanisms (Cargo.toml, go.mod, etc.) within individual projects.

#### Target Architecture

1. **Nix Dependency Declarations**
   ```nix
   # nix/dependencies/
   rustDependencies = {
     serde = "1.0.193";
     tokio = "1.35.0";
     # ... other crates
   };

   goDependencies = {
     "github.com/gorilla/mux" = "v1.8.1";
     "go.uber.org/zap" = "v1.26.0";
     # ... other modules
   };
   ```

2. **Bridge Layer Components**
   - **GOPROXY**: Nix-backed Go module proxy
   - **Cargo Registry**: Nix-backed crate registry mirror
   - **Python Index**: Nix-backed PyPI mirror

3. **Transparent Access**
   - Buck2 toolchains configured to use bridge components
   - Native tools (cargo, go mod, pip) transparently use same sources
   - Cache directories (GOPATH/pkg/mod, target/, etc.) managed under buck-out/

## Language-Specific Solutions

### Go Integration

**Proposed Implementation:**
```bash
# Transparent GOPROXY serving from Nix store
export GOPROXY=http://localhost:8080/proxy
export GOPATH=$BUCK_OUT/go
export GOCACHE=$BUCK_OUT/go/cache
```

**Benefits:**
- Standard `go build`, `go mod tidy` work normally
- Buck2 go_binary targets use same dependency resolution
- Module cache shared between Buck2 and native tooling

### Rust Integration

**Proposed Implementation:**
```bash
# Non-intrusive Cargo registry configuration via environment variables
export CARGO_HOME=$BUCK_OUT/cargo
export CARGO_REGISTRY_DEFAULT=firefly
export CARGO_REGISTRIES_FIREFLY_INDEX=file://$NIX_STORE_PATH/registry-index
export CARGO_NET_OFFLINE=true
```

**Benefits:**
- **Non-intrusive**: No modification of user's `~/.cargo/config.toml`
- **Transparent**: Standard `cargo build`, `cargo check` work with monorepo dependencies
- **Consistent**: Buck2 rust_binary targets use same crate resolution
- **Isolated**: Shared compilation cache via `target/` directory under `buck-out/`

### Python Integration

**Proposed Implementation:**
```bash
# Custom Python index
export PIP_INDEX_URL=file://$NIX_STORE_PATH/python-index/simple
export PYTHONPATH=$BUCK_OUT/python/lib
```

**Benefits:**
- Standard pip, poetry, uv work with centralized dependencies
- Buck2 python_binary targets use same package resolution
- Shared wheel cache and site-packages

## Transparent Native Tooling

### Design Goal

Any component built in the monorepo should be extractable as a standalone project without Buck2-specific modifications. This means:

1. **Standard Project Structure**: Each project maintains standard language conventions
2. **Native Build Compatibility**: `cargo build`, `go build`, etc. work out-of-the-box
3. **IDE Integration**: Language servers and IDEs work normally
4. **External Consumption**: Projects can be imported as standard language packages

### Implementation Strategy

#### Project Structure Example

```
experimental/
├── rs-hello-world/
│   ├── rules.star          # Buck2 build definition
│   ├── Cargo.toml          # Standard Rust manifest
│   ├── src/
│   │   └── main.rs
│   └── .cargo/config.toml  # Points to monorepo registry
└── go-hello-world/
    ├── rules.star          # Buck2 build definition
    ├── go.mod              # Standard Go module
    ├── main.go
    └── .goproxy           # Points to monorepo proxy
```

#### Export Process

When a project needs to be extracted:
1. Copy project directory
2. Update dependency configurations to point to public registries
3. Run standard tooling (`cargo publish`, `go mod tidy`)
4. Project works independently

## Architecture in Practice: mdbook Documentation

This section demonstrates the architecture principles through a concrete example: the implementation of a custom Buck2 rule for building mdbook documentation.

### The Challenge

We wanted to build this documentation using Buck2 while maintaining compatibility with standard mdbook tooling. This required:

1. **System Toolchain Integration**: Using the `mdbook` binary provided by Nix
2. **Dependency Tracking**: Ensuring Buck2 rebuilds when markdown files change
3. **Native Compatibility**: Preserving ability to use `mdbook serve` for development
4. **Hermetic Builds**: Reproducible documentation generation

### The Solution

#### Custom Buck2 Rule (`toolchains/mdbook/mdbook.bzl`)

```python
def _mdbook_impl(ctx: AnalysisContext) -> list[Provider]:
    """Implementation for mdbook rule that builds documentation."""

    # Declare the output directory for the built book
    output_dir = ctx.actions.declare_output("book", dir = True)

    # Use the package directory as the source directory
    src_dir = ctx.label.package

    # Create a script that runs mdbook and ensures output exists
    script = ctx.actions.write("mdbook_build.sh", [
        "#!/bin/bash",
        "set -euo pipefail",
        "mkdir -p $1",
        "mdbook build {} --dest-dir $1".format(src_dir),
    ])

    # Command with proper input/output tracking
    cmd = cmd_args([
        "bash",
        script,
        output_dir.as_output(),  # Buck2 tracks this output
    ], hidden = ctx.attrs.srcs if ctx.attrs.srcs else [])

    ctx.actions.run(cmd, category = "mdbook_build")

    return [
        DefaultInfo(default_output = output_dir),
        # RunInfo enables 'buck2 run //docs:docs' to start development server
        RunInfo(args = cmd_args(["mdbook", "serve", src_dir])),
    ]

mdbook = rule(
    impl = _mdbook_impl,
    attrs = {
        "srcs": attrs.list(attrs.source(), default = [],
                          doc = "Markdown and config files"),
    },
    doc = "Builds an mdbook documentation site",
)
```

#### Build Target (`docs/rules.star`)

```python
load("@toolchains//mdbook:mdbook.bzl", "mdbook")

mdbook(
    name = "docs",
    srcs = [
        "book.toml",
    ] + glob(["src/*.md"]),  # Automatic discovery of markdown files
    visibility = ["PUBLIC"],
)
```

### Architecture Principles Demonstrated

#### 1. **System Toolchain Integration**

**Challenge**: Use Nix-provided `mdbook` without vendoring binaries.

**Solution**: The rule directly calls `mdbook` from the system PATH, which is provided by the Nix shell environment. No additional toolchain configuration needed.

**Benefits**:
- ✅ Single source of truth for tool versions (Nix)
- ✅ No binary vendoring or version conflicts
- ✅ Automatic updates when Nix environment changes

#### 2. **Hermetic Dependency Tracking**

**Challenge**: Ensure Buck2 knows when to rebuild documentation.

**Solution**: Source files listed in `srcs` are passed as `hidden` dependencies to `cmd_args`, ensuring Buck2 tracks all inputs without exposing them on the command line.

**Benefits**:
- ✅ Incremental builds - only rebuild when content changes
- ✅ Parallel execution - Buck2 can build docs alongside other targets
- ✅ Caching - identical inputs produce cached results

#### 3. **Native Tooling Compatibility**

**Challenge**: Preserve developer workflow with standard tools.

**Solution**: The rule operates on standard mdbook project structure (`book.toml`, `src/` directory) and produces standard HTML output.

**Benefits**:
- ✅ `mdbook serve` works normally for development
- ✅ Generated docs compatible with any web server
- ✅ No Buck2-specific artifacts in documentation source

#### 4. **Transparent Environment Configuration**

**Challenge**: Make mdbook available without user intervention.

**Solution**: Nix shell automatically provides `mdbook` binary and all dependencies.

**Benefits**:
- ✅ Zero configuration - `nix develop` provides everything
- ✅ Consistent versions across all team members
- ✅ No global system pollution

### Usage Examples

```bash
# Build documentation (Buck2)
buck2 build //docs:docs

# Show output location
buck2 build //docs:docs --show-output

# Serve documentation (Buck2) - starts development server
buck2 run //docs:docs

# Development server (native tooling)
cd docs && mdbook serve

# One-time build (native tooling)
cd docs && mdbook build
```

### Key Insights

This implementation showcases several architectural advantages:

1. **Composability**: The same `mdbook` binary works in both Buck2 and native contexts
2. **Maintainability**: Adding new documentation files requires no `rules.star` changes (glob patterns)
3. **Reliability**: Buck2's dependency tracking ensures documentation stays in sync with changes
4. **Simplicity**: The rule implementation is straightforward and follows Buck2 conventions

The mdbook rule demonstrates how the hybrid Nix + Buck2 architecture delivers on its promise: **powerful build capabilities without ecosystem lock-in**.

## Implementation Details

### Current Implementation Status

✅ **Completed:**
- Nix development environment with devenv
- Buck2 basic configuration with system toolchains
- Multi-language support (Rust, Go, Python, C++)
- Example projects demonstrating integration
- Custom mdbook Buck2 rule with full source dependency tracking
- Automated documentation builds integrated with monorepo workflow

🚧 **In Progress:**
- Toolchain synchronization architecture design
- Additional example projects for other tools and languages

📋 **Planned (Toolchain Synchronization):**
- `toolchain.toml` schema definition and parser
- Nix generator for Buck2 toolchain files
- Shell environment generator integrated with toolchain config
- Custom Buck2 prelude fork with system toolchain integration
- External cell for build utilities (gazelle-like, reindeer-like tools)

📋 **Planned (Dependency Management):**
- Nix-based dependency management implementation
- Language-specific bridge layer components (GOPROXY, Cargo registry, PyPI mirror)
- Advanced Buck2 rule customizations
- CI/CD pipeline integration

See [Toolchain Synchronization Design Document](./design/toolchain-synchronization.md) for detailed implementation roadmap.

### File Organization

```
src/
├── toolchain.toml              # [Planned] Single source of truth for toolchains
├── docs/
│   ├── src/                    # Documentation source
│   ├── book.toml               # mdbook configuration
│   └── rules.star              # Documentation build target
├── nix/
│   ├── shell.nix               # Development environment
│   ├── toolchain.nix           # [Planned] Backend-specific toolchain config
│   ├── generators/             # [Planned] Code generators
│   │   ├── shell.nix           # Shell environment generator
│   │   ├── buck2.nix           # Buck2 toolchain generator
│   │   └── prelude.nix         # Prelude customization generator
│   ├── toolchains/             # [Planned] Per-language derivations
│   │   ├── go.nix
│   │   ├── rust.nix
│   │   └── python.nix
│   ├── cells/                  # [Planned] External utility cell
│   │   └── tooling/
│   ├── dependencies/           # [Planned] Centralized deps
│   └── bridge/                 # [Planned] Proxy implementations
├── toolchains/
│   ├── BUCK                    # [Generated] System toolchain definitions
│   ├── go/
│   │   ├── BUCK                # [Generated] Go toolchain
│   │   └── toolchain.bzl       # [Generated] Go toolchain rules
│   ├── rust/
│   │   ├── BUCK                # [Generated] Rust toolchain
│   │   └── toolchain.bzl       # [Generated] Rust toolchain rules
│   └── mdbook/
│       └── mdbook.bzl          # Custom mdbook Buck2 rule
├── prelude/                    # [Planned] Forked Buck2 prelude
│   ├── rust/
│   ├── go/
│   └── toolchains/
│       └── register.bzl        # Auto-generated toolchain registration
├── experimental/               # Example projects
│   ├── rs-hello-world/
│   └── go-hello-world/
├── flake.nix                   # Main Nix flake
├── .buckconfig                 # Buck2 configuration (symlink, managed by turnkey)
└── .buckroot                   # Marks project boundary for Buck2
```

Buck2's root cell is configured to use `rules.star` as the buildfile name (set in the
turnkey-generated `.buckconfig`). Per-package build files therefore live as `rules.star`
rather than `BUCK`. Generated cells under `.turnkey/` (e.g. `.turnkey/toolchains/`,
`.turnkey/godeps/`) still use `BUCK` — Buck2's buildfile setting only applies to the
root cell.

### Development Workflow

1. **Environment Setup**:
   ```bash
   nix develop  # or direnv allow
   ```

2. **Build with Buck2**:
   ```bash
   buck2 build //experimental/rs-hello-world:rs-hello-world
   buck2 run //experimental/go-hello-world:go-hello-world
   ```

3. **Native Development** (works transparently):
   ```bash
   cd experimental/rs-hello-world
   cargo build
   cargo run
   ```

4. **Testing**:
   ```bash
   buck2 test //...  # All tests via Buck2
   # Or use native tooling in individual projects
   ```

## Benefits

### For Developers

1. **Familiar Tooling**: Standard language tools work as expected
2. **Fast Onboarding**: Single command environment setup
3. **IDE Support**: Full language server and IDE integration
4. **Flexible Development**: Choice between Buck2 and native tools

### For the Organization

1. **Reproducible Builds**: Guaranteed consistency across environments
2. **Efficient CI**: Hermetic builds with excellent caching
3. **Dependency Management**: Centralized control with security patching
4. **Ecosystem Compatibility**: Easy project extraction and publication

### For the Ecosystem

1. **Non-Contaminating**: Projects remain compatible with standard tooling
2. **Open Source Friendly**: Easy contribution and external collaboration
3. **Future-Proof**: Not locked into monorepo-specific solutions
4. **Standard Compliance**: Follows language best practices

---

This architecture represents a thoughtful balance between the benefits of monorepo development and the importance of ecosystem compatibility, providing a foundation for scalable, maintainable, and developer-friendly software development.

The key innovation is **guaranteed toolchain synchronization** through a single source of truth configuration that eliminates the traditional "two toolchains" problem. By having both shell and Buck2 reference identical Nix derivations, we ensure developers never encounter "works on my machine" issues caused by toolchain version drift. See [Toolchain Synchronization](./design/toolchain-synchronization.md) for the complete design.
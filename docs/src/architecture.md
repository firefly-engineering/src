# Firefly Engineering Monorepo Architecture

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

### Key Components

- **Nix + Flakes**: Provides reproducible development environments and toolchain provisioning
- **Buck2**: Fast, hermetic build system with excellent language support
- **System Toolchains**: Buck2 leverages toolchains provided by Nix instead of vendored ones
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

### Current Implementation

The repository uses Nix with flakes to provide a consistent development environment across all team members and CI systems.

**Key Files:**
- `flake.nix`: Main flake configuration
- `nix/shell.nix`: Development environment specification
- `nix/devenv/agents.nix`: Claude Code integration

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

Buck2 is configured to use "system toolchains" that are actually provided by Nix, avoiding the need to vendor toolchain binaries within the repository.

**Configuration:**
```python
# toolchains/BUCK
system_rust_toolchain(name = "rust", visibility = ["PUBLIC"])
system_go_toolchain(name = "go", visibility = ["PUBLIC"])
system_python_bootstrap_toolchain(name = "python_bootstrap", visibility = ["PUBLIC"])
system_cxx_toolchain(name = "cxx", visibility = ["PUBLIC"])
```

### Buck2 Configuration

```ini
# .buckconfig
[cells]
  root = .
  toolchains = toolchains

[build]
  execution_platforms = prelude//platforms:default
```

This setup allows Buck2 to find and use the toolchains provided by Nix in the development environment.

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
│   ├── BUCK                 # Buck2 build definition
│   ├── Cargo.toml          # Standard Rust manifest
│   ├── src/
│   │   └── main.rs
│   └── .cargo/config.toml  # Points to monorepo registry
└── go-hello-world/
    ├── BUCK                # Buck2 build definition
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

## Implementation Details

### Current Implementation Status

✅ **Completed:**
- Nix development environment with devenv
- Buck2 basic configuration with system toolchains
- Multi-language support (Rust, Go, Python, C++)
- Example projects demonstrating integration

🚧 **In Progress:**
- Documentation and architecture refinement
- Additional example projects

📋 **Planned:**
- Nix-based dependency management implementation
- Language-specific bridge layer components
- Advanced Buck2 rule customizations
- CI/CD pipeline integration

### File Organization

```
src/
├── docs/
│   └── architecture.md          # This document
├── nix/
│   ├── shell.nix               # Development environment
│   ├── dependencies/           # [Planned] Centralized deps
│   └── bridge/                 # [Planned] Proxy implementations
├── toolchains/
│   └── BUCK                    # System toolchain definitions
├── experimental/               # Example projects
│   ├── rs-hello-world/
│   └── go-hello-world/
├── flake.nix                   # Main Nix flake
├── .buckconfig                 # Buck2 configuration
└── BUCK                        # Root build definitions
```

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
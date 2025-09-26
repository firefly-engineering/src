# External Cell Dependency Management Design

## Overview

This document proposes an alternative approach to dependency management using Buck2's cell system combined with Nix-generated build files. Instead of using language-specific registries (GOPROXY, PyPI, npm), dependencies would be exposed as targets in a dedicated "ext" cell, providing explicit dependency declarations while maintaining hermetic builds.

## Core Concept

### The "ext" Cell Approach

Dependencies are managed as a separate Buck2 cell containing auto-generated build targets for external packages:

```python
# In your main code
go_binary(
    name = "my_app",
    srcs = ["main.go"],
    deps = [
        "ext//go/golang.org/x/example/hello:reverse",  # External Go dependency
        "//internal/utils:logger",                     # Internal dependency
    ],
)

rust_binary(
    name = "my_tool",
    srcs = ["main.rs"],
    deps = [
        "ext//rust/serde:serde",                      # External Rust dependency
        "ext//rust/clap:clap",                        # External Rust dependency
    ],
)
```

The `ext//` cell is:
1. **Nix-generated**: Build files created by Nix based on dependency declarations
2. **Symlinked**: Available as `ext/` directory in workspace for code review
3. **Hermetic**: All sources and build definitions managed by Nix
4. **Explicit**: Clear dependency graph in Buck2 build files

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Developer Interface                        │
├─────────────────────────────────────────────────────────────┤
│  Buck2 Build Commands        │        Native Tools          │
│  buck2 build //app:server    │  go build, cargo check       │
│  buck2 test //...            │  npm run dev, pytest         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        Buck2 Core                           │
│  ┌─────────────────┐ ┌──────────────┐ ┌──────────────────┐  │
│  │ Cell Resolution │ │ Target Graph │ │ Build Execution  │  │
│  │                 │ │              │ │                  │  │
│  │ root//app       │ │ ext//deps    │ │ Hermetic Builds  │  │
│  │ ext//deps       │ │ root//libs   │ │                  │  │
│  └─────────────────┘ └──────────────┘ └──────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     Ext Cell Layer                          │
│  ┌─────────────────┐ ┌──────────────┐ ┌──────────────────┐  │
│  │ Generated BUCK  │ │ Source Links │ │ Build Metadata   │  │
│  │ Files           │ │              │ │                  │  │
│  │ go_library()    │ │ Nix Store    │ │ Dependencies     │  │
│  │ rust_library()  │ │ Paths        │ │ Features/Flags   │  │
│  │ python_library()│ │              │ │                  │  │
│  └─────────────────┘ └──────────────┘ └──────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                         Nix Layer                           │
│  ┌─────────────────┐ ┌──────────────┐ ┌──────────────────┐  │
│  │ Dependency      │ │ Code         │ │ Build File       │  │
│  │ Declarations    │ │ Generation   │ │ Generation       │  │
│  │                 │ │              │ │                  │  │
│  │ JSON configs    │ │ Gazelle      │ │ BUCK targets     │  │
│  │ Lock files      │ │ Reindeer     │ │ Dependencies     │  │
│  │ Version pins    │ │ Custom tools │ │ Configurations   │  │
│  └─────────────────┘ └──────────────┘ └──────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Approach

### 1. Ext Cell Structure

```
ext/
├── BUCK                           # Cell root configuration
├── go/                            # Go namespace
│   └── golang.org/
│       └── x/
│           └── example/
│               └── hello/
│                   ├── BUCK       # Generated: go_library targets
│                   ├── reverse/
│                   │   └── BUCK   # Generated: go_library target
│                   └── reverse.go # Symlink to Nix store
├── rust/                          # Rust namespace
│   ├── serde/
│   │   ├── BUCK                   # Generated: rust_library target
│   │   └── src/                   # Symlink to Nix store
│   └── clap/
│       ├── BUCK                   # Generated: rust_library target
│       └── src/                   # Symlink to Nix store
├── python/                        # Python namespace
│   ├── fastapi/
│   │   ├── BUCK                   # Generated: python_library target
│   │   └── fastapi/               # Symlink to Nix store
│   └── requests/
│       ├── BUCK                   # Generated: python_library target
│       └── requests/              # Symlink to Nix store
└── node/                          # TypeScript/Node.js namespace
    ├── express/
    │   ├── BUCK                   # Generated: nodejs_library target
    │   └── lib/                   # Symlink to Nix store
    └── @types/
        └── express/
            ├── BUCK               # Generated: typescript_library target
            └── index.d.ts         # Symlink to Nix store
```

### 2. Nix Generation Process

```nix
# nix/dependencies/ext-cell.nix
{ lib, runCommand, ... }:

let
  # Import dependency specifications
  goDeps = import ./go-dependencies.nix;
  rustDeps = import ./rust-dependencies.nix;
  pythonDeps = import ./python-dependencies.nix;

  # Code generation tools
  gazelle = import ./tools/gazelle.nix;      # Go BUCK file generation
  reindeer = import ./tools/reindeer.nix;    # Rust BUCK file generation
  pythonGen = import ./tools/python-gen.nix; # Python BUCK file generation

  generateExtCell = runCommand "ext-cell" {} ''
    mkdir -p $out

    # Generate cell root
    cat > $out/BUCK << 'EOF'
    # External dependencies cell - generated by Nix
    # DO NOT EDIT MANUALLY
    EOF

    # Generate Go dependencies
    ${lib.concatMapStringsSep "\n" (pkg:
      let
        pkgPath = lib.replaceStrings ["."] ["/"] pkg.name;
      in ''
        mkdir -p "$out/go/${pkgPath}"

        # Link source code
        ln -sf ${pkg.src}/* "$out/go/${pkgPath}/"

        # Generate BUCK file using modified gazelle
        cd "$out/go/${pkgPath}"
        ${gazelle}/bin/gazelle -go_prefix=${pkg.name}
      ''
    ) goDeps}

    # Generate Rust dependencies
    ${lib.concatMapStringsSep "\n" (crate:
      ''
        mkdir -p "$out/rust/${crate.name}"

        # Link source code
        ln -sf ${crate.src}/* "$out/rust/${crate.name}/"

        # Generate BUCK file using modified reindeer
        cd "$out/rust/${crate.name}"
        ${reindeer}/bin/reindeer --buckfile-name=BUCK
      ''
    ) rustDeps}

    # Generate Python dependencies
    ${lib.concatMapStringsSep "\n" (pkg:
      ''
        mkdir -p "$out/python/${pkg.name}"

        # Link source code
        ln -sf ${pkg.src}/* "$out/python/${pkg.name}/"

        # Generate BUCK file using custom Python generator
        cd "$out/python/${pkg.name}"
        ${pythonGen}/bin/python-gen --package-name=${pkg.name}
      ''
    ) pythonDeps}

    # Generate Node.js/TypeScript dependencies
    ${lib.concatMapStringsSep "\n" (pkg:
      let
        # Handle scoped packages like @types/express
        pkgPath = if lib.hasPrefix "@" pkg.name
                  then pkg.name  # Keep @ prefix for scoped packages
                  else pkg.name;
      in ''
        mkdir -p "$out/node/${pkgPath}"

        # Link source code
        ln -sf ${pkg.src}/* "$out/node/${pkgPath}/"

        # Generate BUCK file using Node.js generator
        cd "$out/node/${pkgPath}"
        ${nodeGen}/bin/node-gen --package-name=${pkg.name}
      ''
    ) nodeDeps}

    # Similar for Python, TypeScript, etc...
  '';

in
generateExtCell
```

### 3. Buck2 Integration

#### Cell Configuration (.buckconfig)
```ini
[cells]
root = .
ext = ext

[buildfile]
includes = //ext//...

[external_cells]
ext = nix-store-path-to-generated-cell
```

#### Usage in Build Files
```python
# apps/web-service/BUCK
go_binary(
    name = "server",
    srcs = ["main.go"],
    deps = [
        "ext//go/golang.org/x/example/hello:reverse",
        "ext//go/github.com/gorilla/mux:mux",
        "//internal/config:config",
    ],
)

rust_binary(
    name = "cli",
    srcs = ["main.rs"],
    deps = [
        "ext//rust/serde:serde",
        "ext//rust/clap:clap",
        "//internal/utils:utils",
    ],
)

python_binary(
    name = "api",
    main = "main.py",
    srcs = ["main.py"],
    deps = [
        "ext//python/fastapi:fastapi",
        "ext//python/uvicorn:uvicorn",
        "//internal/auth:auth",
    ],
)

typescript_binary(
    name = "web_app",
    srcs = ["src/main.ts"],
    deps = [
        "ext//node/express:express",
        "ext//node/@types/express:types",
        "//shared/utils:utils",
    ],
)
```

## Advantages

### 1. **Explicit Dependency Management**
- All dependencies are visible in Buck2 build files
- Clear dependency graph for analysis and optimization
- Easy to track which packages depend on external libraries

### 2. **Reviewable Dependencies**
- External code available in workspace via symlinks
- Can review dependency source during code reviews
- Easy to inspect and debug external dependencies

### 3. **Buck2-Native Dependency Resolution & Analysis**
- Leverages Buck2's sophisticated dependency analysis
- Supports Buck2's caching and incremental builds
- No language-specific registry protocols to maintain
- **Powerful dependency graph queries**:
  ```bash
  # Find all targets that depend on a specific external library
  buck2 query "rdeps('//...', 'ext//rust/serde:serde')"

  # Find all external dependencies used by a target
  buck2 query "filter('ext//.*', deps('//apps/web-service:server'))"

  # Analyze dependency paths between targets
  buck2 query "somepath('//apps/api:server', 'ext//go/golang.org/x/example/hello:reverse')"

  # List all external dependencies by language
  buck2 query "ext//rust/..."
  buck2 query "ext//python/..."
  ```

### 4. **Single Version Constraint**
- Forces explicit resolution of version conflicts
- Prevents diamond dependency problems
- Simpler mental model - one version per dependency

### 5. **Tool Integration**
- Reuse existing code generation tools (gazelle, reindeer)
- Language servers see dependencies as regular source code
- Standard debugging and profiling tools work seamlessly

### 6. **Preserved Ecosystem Compatibility**
- **No Import Path Rewriting**: Source code uses standard import paths (`"example.com/foo"`, not Bazel-style rewrites)
- **Automatic Dependency Sync**: Tools automatically add `ext//go/example.com/foo:lib` when detecting `import "example.com/foo"`
- **Version Alignment Verification**: Sanity checks ensure `ext/` versions match `go.mod`/lock files
- **Standard Tooling Compatibility**: `go mod tidy`, `cargo check`, `npm install` continue to work normally

## Disadvantages

### 1. **Version Conflict Resolution**
- Must explicitly resolve conflicts between different required versions
- Cannot have multiple versions of same dependency simultaneously
- May require more manual intervention for complex dependency graphs

### 2. **Build File Complexity**
- More verbose dependency declarations in BUCK files
- Requires understanding Buck2 cell system
- Generated build files may be complex for debugging

### 3. **Workspace Size**
- Ext cell symlinks increase apparent workspace size
- More files visible in IDE (though can be filtered)
- May impact IDE performance with very large dependency sets

## Implementation Phases

### Phase 1: Core Infrastructure (2-3 weeks)

**Goal**: Establish basic ext cell generation and Buck2 integration

#### Deliverables
- Nix functions to generate ext cell structure
- Buck2 cell configuration and integration
- Basic source linking and BUCK file generation
- Simple test case with 2-3 Go packages

#### Technical Requirements
- Generate valid Buck2 cell structure
- Proper source code linking from Nix store
- Basic BUCK file generation for each language
- Cell integration with main build

### Phase 2: Code Generation Tools (3-4 weeks)

**Goal**: Integrate and adapt existing code generation tools

#### Go: Modified Gazelle
```nix
# nix/tools/gazelle.nix
{ buildGoModule, gazelle-upstream }:

buildGoModule rec {
  pname = "firefly-gazelle";
  version = "custom";

  src = ./gazelle-modifications;  # Fork with ext cell support

  # Modifications:
  # - Generate targets compatible with ext cell structure
  # - Handle Nix store source paths
  # - Support firefly-specific naming conventions
}
```

#### Rust: Modified Reindeer
```nix
# nix/tools/reindeer.nix
{ rustPlatform, reindeer-upstream }:

rustPlatform.buildRustPackage rec {
  pname = "firefly-reindeer";
  version = "custom";

  src = ./reindeer-modifications;  # Fork with ext cell support

  # Modifications:
  # - Generate rust_library targets for ext cell
  # - Handle feature flag propagation
  # - Support Nix store source paths
}
```

#### Python: Custom Generator
```nix
# nix/tools/python-gen.nix
{ python3, buildPythonPackage }:

buildPythonPackage rec {
  pname = "firefly-python-gen";
  version = "1.0.0";

  src = ./python-generator;  # Custom Python BUCK generator

  # Features:
  # - Parse setup.py/pyproject.toml for dependencies
  # - Generate python_library targets
  # - Handle optional dependencies and extras
}
```

### Phase 3: Multi-Language Integration (2-3 weeks)

**Goal**: Support all major languages with consistent patterns

#### Deliverables
- Go, Rust, Python, TypeScript/Node.js support
- Consistent naming conventions across languages
- Proper dependency resolution between languages
- Cross-language dependency examples

### Phase 4: Development Experience (1-2 weeks)

**Goal**: Optimize developer workflow and tooling

#### Deliverables
- IDE configuration for ext cell filtering/inclusion
- Development shell integration with ext symlink
- Documentation and migration guides
- Performance optimization for large dependency sets

## Ecosystem Compatibility Through Automated Tooling

The ext cell approach can maintain full ecosystem compatibility by avoiding the pitfalls of import path rewriting (like Bazel) and instead using intelligent tooling to keep Buck2 build files synchronized with standard language manifests.

### **Automatic Dependency Detection & Sync**

#### Go Example
```go
// In your Go source - standard imports, no rewriting
package main

import (
    "context"
    "fmt"
    "github.com/gorilla/mux"           // ← Standard Go import
    "golang.org/x/example/hello"      // ← Standard Go import
)
```

**Automated tooling detects imports and updates BUCK file**:
```python
# apps/my-service/BUCK (auto-updated by tooling)
go_binary(
    name = "my_service",
    srcs = ["main.go"],
    deps = [
        "ext//go/github.com/gorilla/mux:mux",           # ← Auto-added
        "ext//go/golang.org/x/example/hello:hello",     # ← Auto-added
    ],
)
```

#### Implementation Strategy
```bash
# Watch for source changes and auto-update BUCK files
firefly-sync --watch apps/my-service/

# Or run manually
firefly-sync --target //apps/my-service:my_service
```

### **Version Alignment & Verification**

#### Go Module Synchronization
```bash
# Verify ext/ versions align with go.mod requirements
firefly-verify --language=go --manifest=go.mod

# Example output:
✓ golang.org/x/example: ext/go/ has v0.0.0-20231025140028, go.mod requires v0.0.0-20231025140028
✗ github.com/gorilla/mux: ext/go/ has v1.8.0, go.mod requires v1.8.1
```

#### Auto-sync Process
```bash
# Update ext/ to match go.mod versions
firefly-sync --update-ext --from-manifest=go.mod

# Or update go.mod to match ext/ versions (for monorepo consistency)
firefly-sync --update-manifest --from-ext
```

### **Standard Tooling Integration**

#### Language Server Compatibility
- **gopls**: Sees source code with standard imports, works normally
- **rust-analyzer**: Uses standard Cargo.toml, unaware of Buck2
- **tsserver**: Standard node_modules or package.json, transparent operation

#### Development Workflow
```bash
# Standard language tooling continues to work
go mod tidy                    # Updates go.mod normally
go build                       # Works with standard GOPATH/modules
cargo check                    # Uses standard Cargo manifest
npm install                    # Works with package.json

# Buck2 builds use ext/ cell
buck2 build //apps/my-service:my_service

# Sync tool keeps everything aligned
firefly-sync --verify-all
```

### **Tooling Architecture**

```
┌─────────────────────────────────────────────────────────────┐
│                  Source Code Analysis                       │
│  ┌─────────────────┐ ┌──────────────┐ ┌──────────────────┐  │
│  │ Import Scanner  │ │ AST Parser   │ │ Dependency       │  │
│  │                 │ │              │ │ Extractor        │  │
│  │ Go: import "..."│ │ Tree-sitter  │ │ Language-specific│  │
│  │ Rust: use ...   │ │ or native    │ │ logic            │  │
│  │ TS: import {...}│ │ parsers      │ │                  │  │
│  └─────────────────┘ └──────────────┘ └──────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  Synchronization Engine                     │
│  ┌─────────────────┐ ┌──────────────┐ ┌──────────────────┐  │
│  │ BUCK File       │ │ Version      │ │ Manifest         │  │
│  │ Generation      │ │ Alignment    │ │ Verification     │  │
│  │                 │ │              │ │                  │  │
│  │ Add/remove deps │ │ ext/ ↔ .mod  │ │ go.mod ✓         │  │
│  │ Target mapping  │ │ Conflict     │ │ Cargo.toml ✓     │  │
│  │ Rule generation │ │ detection    │ │ package.json ✓   │  │
│  └─────────────────┘ └──────────────┘ └──────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Tool Modifications Required

### Gazelle (Go)
- **Source Path Handling**: Support Nix store paths as source roots
- **Target Naming**: Generate targets compatible with ext cell naming
- **Dependency Resolution**: Map Go imports to Buck2 targets correctly
- **Module Boundaries**: Handle Go modules spanning multiple directories

### Reindeer (Rust)
- **Crate Features**: Properly handle feature flags in Buck2 targets
- **Workspace Support**: Handle Rust workspaces in ext cell context
- **Edition Handling**: Support different Rust editions properly
- **Proc Macros**: Special handling for procedural macros

### Custom Python Generator
- **Package Discovery**: Parse Python package metadata (setup.py, pyproject.toml)
- **Namespace Packages**: Handle different Python namespace package styles
- **Optional Dependencies**: Support extras and optional dependencies
- **Build Systems**: Support different Python build backends

## Migration Strategy

### From Registry Approach
1. **Parallel Implementation**: Build ext cell alongside existing registry approach
2. **Gradual Migration**: Migrate one language at a time
3. **Compatibility Layer**: Maintain registry approach during transition
4. **Performance Comparison**: Benchmark both approaches

### Developer Experience
1. **Documentation**: Clear guides for both approaches
2. **Tooling**: Commands to switch between approaches easily
3. **IDE Support**: Configuration for both approaches
4. **Training**: Developer education on Buck2 cell system

## Comparison: Ext Cell vs Registry

| Aspect | Ext Cell Approach | Registry Approach |
|--------|-------------------|------------------|
| **Visibility** | ✅ All deps visible in build files | ❌ Hidden in language tooling |
| **Debugging** | ✅ Source available in workspace | ❌ Registry-dependent |
| **Caching** | ✅ Buck2-native caching | ⚠️ Language-specific caching |
| **Version Conflicts** | ❌ Must resolve explicitly | ✅ Can have multiple versions |
| **Tool Integration** | ✅ Standard tools work | ⚠️ Registry-aware tools needed |
| **Build Complexity** | ❌ More verbose BUCK files | ✅ Simpler build files |
| **Performance** | ✅ Buck2 optimizations | ⚠️ Language tool performance |
| **Ecosystem Compatibility** | ✅ Standard tooling + sync | ✅ Standard tooling |

## Decision Framework

### Choose Ext Cell When:
- Explicit dependency management is preferred
- Code review of dependencies is important
- Buck2-native optimizations are prioritized
- Single-version constraint is acceptable
- Team has Buck2 expertise

### Choose Registry When:
- Standard tooling compatibility is critical
- Multiple dependency versions are required
- Existing workflow preservation is important
- Language-specific features need full support
- Team prefers familiar package managers

## Dependency Analysis Capabilities

The ext cell approach unlocks Buck2's full dependency analysis power, providing insights impossible with registry approaches:

### **Security & Compliance Analysis**
```bash
# Find all targets affected by a vulnerable dependency
buck2 query "rdeps('//...', 'ext//node/lodash:lodash')"

# Audit external dependencies across the entire codebase
buck2 query "kind('.*_library', 'ext//...')" --output-attribute=srcs

# Find unused external dependencies
buck2 query "ext//..." --except "rdeps('//...', 'ext//...')"
```

### **Impact Analysis for Updates**
```bash
# Before updating serde, see what would be affected
buck2 query "rdeps('//...', 'ext//rust/serde:serde')"

# Find all Rust dependencies that need coordinated updates
buck2 query "filter('ext//rust/.*', deps('ext//rust/tokio:tokio'))"

# Analyze cross-language dependencies (e.g., Python calling Rust via FFI)
buck2 query "somepath('ext//python/...', 'ext//rust/...')"
```

### **Build Optimization**
```bash
# Find the most depended-upon external libraries (optimization targets)
buck2 query "ext//..." | xargs -I {} buck2 query "rdeps('//...', '{}')" | sort | uniq -c | sort -nr

# Identify potential build bottlenecks in external deps
buck2 query "deps('ext//rust/tokio:tokio')" --output-format=json
```

### **Language Ecosystem Analysis**
```bash
# Compare external dependency usage across languages
buck2 query "ext//go/..." | wc -l    # Go dependencies count
buck2 query "ext//rust/..." | wc -l  # Rust dependencies count

# Find mixed-language projects
buck2 query "intersect(rdeps('//...', 'ext//go/...'), rdeps('//...', 'ext//rust/...'))"
```

## Future Enhancements

### Advanced Features
- **Dependency Visualization**: Web UI for Buck2 dependency graphs with ext cell highlighting
- **Automatic Updates**: Nix-based dependency update automation with impact analysis
- **Security Scanning**: Integration with vulnerability databases and automated CVE tracking
- **Performance Analytics**: Build time analysis and optimization recommendations

### Integration Possibilities
- **Mixed Approach**: Some dependencies via ext cell, others via registry
- **Conditional Generation**: Choose approach per dependency based on criteria
- **Migration Tools**: Automated conversion between approaches
- **Hybrid Caching**: Combine Buck2 and language-specific caching

### Future: Transparent Command Interception

**Vision**: Make dependency management completely transparent by intercepting standard language commands and automatically keeping Buck2/Nix/source manifests synchronized.

#### **Intelligent Command Wrappers**

**Go Command Wrapper**:
```bash
# User runs standard command
go get -u github.com/gorilla/mux@v1.8.1

# Wrapped "go" binary (provided by Nix) automatically:
# 1. Runs standard "go get"
# 2. Updates Nix dependency source of truth
# 3. Regenerates ext//go/github.com/gorilla/mux
# 4. Refreshes current devshell environment
# 5. Updates Buck2 build files
```

**Implementation**:
```nix
# nix/devenv/go-wrapper.nix
{ writeShellScriptBin, go, firefly-sync }:

writeShellScriptBin "go" ''
  # Run original go command
  ${go}/bin/go "$@"

  # If this was a dependency-changing command, sync everything
  case "$1" in
    "get"|"mod")
      echo "🔄 Syncing Buck2 dependencies..."
      ${firefly-sync}/bin/firefly-sync --update-ext --from-manifest=go.mod
      echo "♻️  Refreshing development environment..."
      nix develop --refresh
      ;;
  esac
''
```

**Buck2 Command Wrapper**:
```bash
# User runs Buck2 build
buck2 build //apps/my-service:server

# Wrapped "buck2" binary automatically:
# 1. Checks if ext/ cell needs regeneration
# 2. Regenerates outdated ext/ targets if needed
# 3. Runs actual Buck2 build
```

**Implementation**:
```nix
# nix/devenv/buck2-wrapper.nix
{ writeShellScriptBin, buck2, firefly-regen }:

writeShellScriptBin "buck2" ''
  # Check if ext/ cell needs regeneration
  if ${firefly-regen}/bin/firefly-regen --check-stale; then
    echo "🔄 Regenerating stale ext/ dependencies..."
    ${firefly-regen}/bin/firefly-regen --update-stale
  fi

  # Run actual Buck2 command
  ${buck2}/bin/buck2 "$@"
''
```

#### **Cross-Language Coordination**

**Unified Dependency Command**:
```bash
# Future: single command for all languages
firefly deps add golang.org/x/example@latest
firefly deps add serde@1.0.193
firefly deps add express@^4.18.2

# Automatically:
# - Updates appropriate manifest (go.mod, Cargo.toml, package.json)
# - Updates Nix dependency declarations
# - Regenerates ext/ cell
# - Refreshes development environment
```

**Smart Conflict Resolution**:
```bash
# Detects cross-language version conflicts
firefly deps add some-binding-lib@2.0.0

# Output:
⚠️  Version conflict detected:
   - ext//go/some-binding-lib currently at v1.5.0
   - ext//rust/some-binding-lib-sys requires compatible version

🔄 Suggesting coordinated update:
   - some-binding-lib: v1.5.0 → v2.0.0
   - some-binding-lib-sys: v0.8.0 → v1.0.0

Apply changes? [y/N]
```

#### **Environment Refresh Strategies**

**Incremental Updates**:
```bash
# Instead of full nix develop --refresh
# Incrementally update only changed parts
firefly-env --update-dependency golang.org/x/example
```

**Background Synchronization**:
```bash
# File watcher automatically syncs changes
firefly-daemon --watch-manifests --background-sync
```

#### **IDE Integration Hooks**

**Language Server Coordination**:
```bash
# When IDE requests dependency info, ensure sync
# Wrapper around gopls, rust-analyzer, tsserver
gopls-wrapper() {
  firefly-sync --verify --language=go --quiet
  exec gopls "$@"
}
```

**Hot Reload Integration**:
```bash
# Development server automatically reloads on dependency changes
firefly dev --hot-reload --sync-deps
# Watches: go.mod, Cargo.toml, package.json
# Auto-syncs: ext/ cell, Buck2 builds, development environment
```

#### **Implementation Architecture**

```
┌─────────────────────────────────────────────────────────────┐
│                  Command Interception Layer                 │
│  ┌─────────────────┐ ┌──────────────┐ ┌──────────────────┐  │
│  │ Language        │ │ Buck2        │ │ Development      │  │
│  │ Wrappers        │ │ Wrapper      │ │ Tools            │  │
│  │                 │ │              │ │                  │  │
│  │ go → go-wrapper │ │ buck2 →      │ │ firefly deps     │  │
│  │ cargo → wrapper │ │ buck2-wrap   │ │ firefly env      │  │
│  │ npm → wrapper   │ │              │ │ firefly daemon   │  │
│  └─────────────────┘ └──────────────┘ └──────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  Synchronization Engine                     │
│  ┌─────────────────┐ ┌──────────────┐ ┌──────────────────┐  │
│  │ State Detection │ │ Multi-step   │ │ Environment      │  │
│  │                 │ │ Updates      │ │ Refresh          │  │
│  │ • Manifest diffs│ │              │ │                  │  │
│  │ • ext/ staleness│ │ 1. Update    │ │ • Incremental    │  │
│  │ • Version       │ │    manifests │ │ • Background     │  │
│  │   conflicts     │ │ 2. Regen ext/│ │ • Hot reload     │  │
│  │                 │ │ 3. Refresh   │ │                  │  │
│  └─────────────────┘ └──────────────┘ └──────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

#### **Developer Experience Vision**

**Completely Transparent Workflow**:
```bash
# Developer works with completely standard tools
cd apps/my-service/
go get -u github.com/gorilla/mux    # ← Standard command
# ✨ Automatically syncs Buck2 and refreshes environment

go mod tidy                         # ← Standard command
# ✨ Automatically updates ext/ cell

buck2 build :server                 # ← Uses updated dependencies
# ✨ Automatically regenerates stale ext/ targets

# IDE continues working normally
code .                              # ← gopls sees standard imports
# ✨ Language server works with synced dependencies
```

**Zero Configuration Required**:
- Nix devshell provides wrapped commands automatically
- All synchronization happens transparently
- Developers never think about Buck2/ext cell complexity
- Standard language tooling "just works"

This represents the ultimate evolution: **explicit dependency management with zero developer friction**.

---

This ext cell approach represents a fundamental shift toward explicit dependency management while maintaining the hermetic and reproducible builds that are core to our architecture. It leverages Buck2's strengths while providing clear visibility into the dependency graph.
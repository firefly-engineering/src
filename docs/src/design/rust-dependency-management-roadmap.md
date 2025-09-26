# Rust Dependency Management Implementation Roadmap

## Overview

This document outlines the roadmap for implementing Rust dependency management as described in the [Architecture document](../architecture.md). The implementation will demonstrate the Nix + Buck2 hybrid architecture with a concrete test case using popular Rust crates while maintaining compatibility with standard Cargo tooling.

## Test Case: Rust Web Service with Popular Crates

The implementation will focus on enabling a Rust application that uses common ecosystem crates:

```rust
// src/main.rs
use serde::{Deserialize, Serialize};
use tokio;
use axum::{
    extract::Query,
    response::Json,
    routing::get,
    Router,
};

#[derive(Serialize, Deserialize)]
struct HelloResponse {
    message: String,
    reversed: String,
}

#[derive(Deserialize)]
struct HelloQuery {
    name: String,
}

async fn hello(Query(params): Query<HelloQuery>) -> Json<HelloResponse> {
    let message = format!("Hello, {}!", params.name);
    let reversed = message.chars().rev().collect();

    Json(HelloResponse { message, reversed })
}

#[tokio::main]
async fn main() {
    let app = Router::new().route("/hello", get(hello));

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();
    println!("Server running on http://0.0.0.0:3000");
    axum::serve(listener, app).await.unwrap();
}
```

This serves as a practical demonstration of our dependency management system handling external Rust crates with complex dependency graphs.

## Current State Analysis

### ✅ Existing Infrastructure

- **Nix Development Environment**: Working devenv setup with Rust toolchain
- **Buck2 Integration**: System Rust toolchains configured and functional
- **Basic Rust Building**: Simple Rust programs build successfully with Buck2
- **Directory Structure**: Well-organized monorepo structure in place

### 📋 Missing Components

- **Centralized Dependency Declaration**: No Nix-based Rust crate management
- **Registry Implementation**: No local crate registry serving from Nix store
- **Environment Variable Configuration**: Missing transparent Cargo configuration
- **Dependency Bridge Layer**: No transparent access for both Buck2 and native tooling

## Implementation Phases

### Phase 1: Nix Dependency Declaration System

**Timeline**: 1-2 weeks
**Goal**: Establish centralized Rust crate dependency declarations in Nix

#### Deliverables

1. **JSON dependency declaration format**:
   ```json
   // nix/dependencies/rust-crates.json
   {
     "serde": [
       {
         "version": "1.0.193",
         "hash": "sha256-xNu8k7ZipOEeQY8iI6I4DhS8Kq5yOUuCe6wMhY7/xls=",
         "features": ["derive"],
         "dependencies": {
           "serde_derive": "1.0.193"
         }
       }
     ],
     "tokio": [
       {
         "version": "1.35.0",
         "hash": "sha256-VvMCRnstmaxeL/5t8ixLpMHdF6zZF8LFqGhvYZJqF8s=",
         "features": ["full"],
         "dependencies": {
           "libc": "0.2.150",
           "pin-project-lite": "0.2.13"
         }
       }
     ],
     "axum": [
       {
         "version": "0.7.2",
         "hash": "sha256-abc123...",
         "dependencies": {
           "serde": "1.0.193",
           "tokio": "1.35.0",
           "tower": "0.4.13"
         }
       }
     ]
   }
   ```

2. **Nix JSON parser and crate fetching**:
   ```nix
   # nix/dependencies/rust-parser.nix
   { lib, fetchCrate, rustPlatform, ... }:
   let
     rustCratesJson = builtins.fromJSON (builtins.readFile ./rust-crates.json);

     fetchCrateSource = crateSpec: fetchCrate {
       pname = crateSpec.name;
       version = crateSpec.version;
       sha256 = crateSpec.hash;
     };

     processCrates = lib.mapAttrs (crateName: versions:
       lib.map (version: {
         name = crateName;
         inherit (version) version hash features;
         src = fetchCrateSource (version // { name = crateName; });
         dependencies = version.dependencies or {};
       }) versions
     ) rustCratesJson;
   in
   processCrates
   ```

3. **Tooling for dependency management**:
   - Script to add new crates to JSON file
   - Hash calculation using `nix-prefetch` or `cargo-hash`
   - Feature resolution and conflict detection
   - Dependency graph validation

#### Technical Requirements

- JSON format must support crate features and optional dependencies
- Support multiple versions per crate for dependency resolution
- Use `fetchCrate` for reliable crate source fetching from crates.io
- Implement proper version pinning and hash verification
- Handle feature flags and conditional dependencies

#### Acceptance Criteria

- [ ] Rust crates declared in JSON format
- [ ] Nix successfully parses JSON and fetches crates
- [ ] Support for multiple versions per crate
- [ ] Crates successfully fetched and stored in Nix store
- [ ] Hash verification prevents supply chain attacks
- [ ] Tooling available for adding new dependencies

### Phase 2: Local Crate Registry Implementation

**Timeline**: 2-3 weeks
**Goal**: Generate a local crate registry compatible with Cargo's registry protocol

#### Deliverables

1. **Nix function to generate local registry**:
   ```nix
   # nix/dependencies/rust-registry.nix
   { lib, runCommand, jq, ... }:

   let
     rustCrates = import ./rust-parser.nix { inherit lib fetchCrate; };

     generateRegistry = runCommand "rust-registry" {
       buildInputs = [ jq ];
     } ''
       mkdir -p $out/index

       ${lib.concatMapStringsSep "\n" (crateName:
         let crateVersions = rustCrates.${crateName};
         in lib.concatMapStringsSep "\n" (crateInfo: ''
           # Generate registry entry for ${crateName}@${crateInfo.version}
           CRATE_PATH="${lib.substring 0 2 crateName}/${lib.substring 2 2 crateName}/${crateName}"
           mkdir -p "$out/index/$CRATE_PATH"

           # Create registry entry
           cat > "$out/index/$CRATE_PATH" << 'EOF'
           {
             "name": "${crateName}",
             "vers": "${crateInfo.version}",
             "deps": [${lib.concatMapStringsSep "," (depName: ''
               {
                 "name": "${depName}",
                 "req": "${crateInfo.dependencies.${depName}}",
                 "features": [],
                 "optional": false,
                 "default_features": true,
                 "target": null,
                 "kind": "normal"
               }'') (builtins.attrNames crateInfo.dependencies)}],
             "features": ${builtins.toJSON crateInfo.features},
             "cksum": "${crateInfo.hash}",
             "yanked": false
           }
           EOF

           # Link to actual crate source
           ln -s ${crateInfo.src} "$out/crates/${crateName}-${crateInfo.version}.crate"
         '') crateVersions
       ) (builtins.attrNames rustCrates)}

       # Create registry config
       cat > "$out/config.json" << 'EOF'
       {
         "dl": "file://$out/crates/{crate}-{version}.crate",
         "api": "file://$out/index"
       }
       EOF
     '';
   in
   generateRegistry
   ```

2. **Registry index structure**:
   - Implement Cargo registry index format
   - Generate proper crate metadata files
   - Handle crate path computation (first 2 chars / next 2 chars / name)
   - Create dependency specification in registry format

3. **Integration with Cargo configuration**:
   ```toml
   # Generated .cargo/config.toml
   [registries]
   firefly = { index = "file:///nix/store/.../registry-index" }

   [source.crates-io]
   replace-with = "firefly"

   [source.firefly]
   registry = "file:///nix/store/.../registry-index"
   ```

#### Technical Requirements

- Follow [Cargo registry format specification](https://doc.rust-lang.org/cargo/reference/registries.html)
- Handle crate name to path mapping correctly
- Generate proper dependency specifications with version requirements
- Support crate features and optional dependencies
- Compatible with both `cargo build` and Buck2's Rust rules

#### Acceptance Criteria

- [ ] Registry format matches Cargo specification
- [ ] Can serve popular crates via local file-based registry
- [ ] Compatible with Cargo toolchain (`cargo build`, `cargo check`)
- [ ] Integration tests pass with real Rust projects

### Phase 3: Environment Variable Configuration

**Timeline**: 1 week
**Goal**: Configure development environment to transparently use our local registry

#### Deliverables

1. **Enhanced devenv configuration**:
   ```nix
   # nix/devenv/languages.nix (enhanced)
   { ... }:
   let
     rustRegistry = import ../dependencies/rust-registry.nix {
       inherit lib runCommand jq;
     };
   in
   {
     languages = {
       # ... existing languages
       rust = {
         enable = true;
         channel = "stable";
       };
     };

     env = {
       CARGO_HOME = "$BUCK_OUT/cargo";
       CARGO_REGISTRY_DEFAULT = "firefly";
       CARGO_REGISTRIES_FIREFLY_INDEX = "file://${rustRegistry}/index";
       CARGO_NET_OFFLINE = "true";  # Force offline mode to use local registry
     };

     enterShell = ''
       echo "🦀 Welcome to Firefly Engineering Rust Environment"
       echo "Local registry available at: file://${rustRegistry}/index"
       echo "Available crates:"
       ${lib.concatMapStringsSep "\n" (name:
         "echo '  - ${name}'"
       ) (builtins.attrNames (builtins.fromJSON (builtins.readFile ../dependencies/rust-crates.json)))}

       # Create .cargo/config.toml for this session
       mkdir -p .cargo
       cat > .cargo/config.toml << 'EOF'
       [registries]
       firefly = { index = "file://${rustRegistry}/index" }

       [source.crates-io]
       replace-with = "firefly"
       EOF
     '';
   }
   ```

2. **No process management needed**:
   - Remove all HTTP server and service management complexity
   - Direct filesystem access to registry via `file://` URL
   - Zero runtime dependencies or background processes

3. **Buck2 integration verification**:
   - Ensure Buck2 Rust rules use the same registry configuration
   - Test that Buck2 builds use cached crates
   - Verify shared compilation cache behavior

#### Technical Requirements

- Non-intrusive configuration (no modification of user's `~/.cargo/config.toml`)
- No runtime processes or service management
- Filesystem-only approach with reproducible Nix store paths
- Fast crate resolution (no network overhead)
- Compatible with rust-analyzer and other Rust tooling

#### Acceptance Criteria

- [ ] CARGO_REGISTRIES configured automatically in development shell
- [ ] Cargo commands use local filesystem registry transparently
- [ ] Buck2 builds use same crate cache
- [ ] No background processes or service management required
- [ ] Crate resolution works offline

### Phase 4: Test Implementation

**Timeline**: 1 week
**Goal**: Create working example with popular Rust crates

#### Deliverables

1. **Test application implementation**:
   ```rust
   // experimental/rust-web-service/src/main.rs
   use serde::{Deserialize, Serialize};
   use tokio;
   use axum::{
       extract::Query,
       response::Json,
       routing::get,
       Router,
   };

   #[derive(Serialize, Deserialize)]
   struct HelloResponse {
       message: String,
       reversed: String,
   }

   // ... (rest of implementation as shown above)
   ```

2. **Buck2 build configuration**:
   ```python
   # experimental/rust-web-service/BUCK
   rust_binary(
       name = "web-service",
       srcs = glob(["src/**/*.rs"]),
       crate_root = "src/main.rs",
       visibility = ["PUBLIC"],
   )
   ```

3. **Standard Cargo configuration**:
   ```toml
   # experimental/rust-web-service/Cargo.toml
   [package]
   name = "rust-web-service"
   version = "0.1.0"
   edition = "2021"

   [dependencies]
   serde = { version = "1.0.193", features = ["derive"] }
   tokio = { version = "1.35.0", features = ["full"] }
   axum = "0.7.2"
   ```

4. **Comprehensive testing**:
   - Verify Buck2 build works: `buck2 build //experimental/rust-web-service:web-service`
   - Verify native build works: `cd experimental/rust-web-service && cargo build`
   - Verify both produce identical results
   - Test rust-analyzer integration (auto-completion, go-to-definition)

#### Technical Requirements

- Both Buck2 and native Cargo builds must work identically
- Crate resolution must be transparent
- IDE language server integration must function
- No Buck2-specific code in the Rust source

#### Acceptance Criteria

- [ ] Application builds and runs via Buck2
- [ ] Application builds and runs via native Cargo tooling
- [ ] IDE integration works (auto-completion, go-to-definition)
- [ ] Crate cache shared between build systems
- [ ] Output is identical from both build methods

### Phase 5: Documentation and Testing

**Timeline**: 1 week
**Goal**: Complete documentation and comprehensive testing

#### Deliverables

1. **Updated architecture documentation**:
   - Document implemented Rust dependency management
   - Include concrete examples and usage patterns
   - Update diagrams to reflect implemented components

2. **Developer guide**:
   - How to add new Rust dependencies
   - Troubleshooting common issues
   - Best practices for Rust development in the monorepo

3. **Automated testing**:
   - CI/CD integration tests
   - Crate resolution verification tests
   - Performance benchmarks for build times

4. **Migration guide**:
   - How to migrate existing Rust projects to use centralized dependencies
   - Extracting projects back to standalone crates

#### Technical Requirements

- Clear, actionable documentation
- Automated verification of examples
- Performance regression testing
- Backward compatibility considerations

#### Acceptance Criteria

- [ ] Documentation is complete and accurate
- [ ] All examples work as documented
- [ ] CI/CD pipeline includes Rust dependency tests
- [ ] Migration path is clear and tested

## Success Metrics

### Development Experience

- **Single Command Setup**: `nix develop` provides complete Rust development environment
- **Build Time Consistency**: Buck2 and native builds have similar performance
- **IDE Integration**: Full rust-analyzer support without additional configuration
- **Transparent Crate Resolution**: Developers don't need to think about the registry

### Technical Metrics

- **Crate Caching**: Shared cache reduces redundant downloads
- **Build Reproducibility**: Identical builds across different environments
- **Dependency Security**: Centralized patching and version management
- **Extraction Simplicity**: Projects easily convertible to standalone crates

### Architecture Validation

- **Non-Contaminating**: Standard Cargo tooling works without modification
- **Hermetic Builds**: All dependencies explicitly declared and versioned
- **Ecosystem Compatibility**: Projects remain compatible with standard Rust ecosystem
- **Vendor Lock-in Avoidance**: No Buck2-specific code required in Rust sources

## Risk Mitigation

### Technical Risks

1. **Registry Protocol Compliance**: Thorough testing against Cargo registry specification
2. **Dependency Resolution Edge Cases**: Comprehensive test suite covering feature flags and optional deps
3. **Performance Overhead**: Benchmarking and optimization of registry implementation
4. **Nix Store Integration**: Proper handling of Nix garbage collection and crate lifecycle

### Process Risks

1. **Developer Adoption**: Clear documentation and migration support
2. **CI/CD Integration**: Gradual rollout with fallback mechanisms
3. **Maintenance Burden**: Automation of dependency updates and security patches
4. **Complexity Management**: Keep implementation simple and well-documented

## Future Enhancements

### Advanced Features

- **Private Crate Support**: Extension to support internal/private Rust crates
- **Multi-Version Support**: Advanced dependency resolution for conflicting versions
- **Build Optimization**: Advanced caching and incremental compilation via sccache
- **Security Scanning**: Automated vulnerability scanning with cargo-audit

### Ecosystem Integration

- **Language Server Protocol**: Enhanced rust-analyzer integration with monorepo awareness
- **Testing Framework**: Advanced testing utilities for monorepo Rust projects
- **Deployment Tools**: Integration with deployment and packaging systems
- **Monitoring**: Metrics and observability for dependency usage

## Implementation Timeline

```
Week 1-2:  Phase 1 - Nix Dependency Declaration System
Week 3-5:  Phase 2 - Local Crate Registry Implementation
Week 6:    Phase 3 - Environment Variable Configuration
Week 7:    Phase 4 - Test Implementation
Week 8:    Phase 5 - Documentation and Testing
```

**Total Duration**: ~8 weeks
**Key Milestones**:
- Week 2: Dependencies managed in Nix
- Week 5: Working local crate registry
- Week 6: Transparent development environment
- Week 7: End-to-end working example
- Week 8: Production-ready with full documentation

---

This roadmap provides a structured approach to implementing Rust dependency management that aligns with our hybrid Nix + Buck2 architecture, maintaining our principles of non-contaminating ecosystem integration and transparent native tooling compatibility.
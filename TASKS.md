# Toolchain Synchronization Implementation Tasks

This document tracks the implementation roadmap for the [Toolchain Synchronization Architecture](./docs/src/design/toolchain-synchronization.md).

## Overview

The goal is to implement a registry-based toolchain resolution system that guarantees synchronization between native tooling (shell environment) and Buck2 builds. The source of truth consists of:

1. **`toolchain.toml`**: High-level declaration of toolchain versions
2. **`nix/toolchains/registry.nix`**: Resolution mechanism mapping versions to Nix derivations

Both the development shell and Buck2 toolchain configurations are generated from the same resolved derivations, ensuring identical binaries.

## Current Status

- [x] Design document completed
- [x] Documentation updated (architecture.md, introduction.md)
- [ ] Implementation not started

## Phase 1: Core Infrastructure

**Goal**: Establish foundational configuration and generation pipeline with registry-based resolution.

**Success Criteria**:
- [ ] `toolchain.toml` can declare toolchain versions
- [ ] Registry resolves versions to Nix derivations
- [ ] Shell environment includes resolved toolchains
- [ ] Buck2 toolchain files are generated with Nix store paths
- [ ] `which go` and `buck2 audit config go_bin` return identical paths

### 1.1 Schema Definition

- [ ] Define `toolchain.toml` schema
  - [ ] Create schema version field
  - [ ] Define toolchain sections (go, rust, python, etc.)
  - [ ] Define version field format
  - [ ] Add validation rules
  - [ ] Document schema in `docs/src/`

- [ ] Create initial `toolchain.toml` at repository root
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

### 1.2 Toolchain Registry

- [ ] Create `nix/toolchains/` directory structure
- [ ] Implement `nix/toolchains/registry.nix`
  - [ ] Define registry schema (version → { package, patches?, metadata? })
  - [ ] Add Go toolchain entries (1.21.5, 1.22.0)
  - [ ] Add Rust toolchain entries (1.75.0, 1.76.0)
  - [ ] Add Python toolchain entries (3.11, 3.12)
  - [ ] Add metadata fields for debugging (registry_version, description)

- [ ] Create example registry entry with patch
  ```nix
  go."1.21.5" = {
    package = pkgs.go_1_21;
    patches = [ ./patches/example.patch ];
    metadata = {
      registry_version = "2024-01-15";
      description = "Go 1.21.5 with example patch";
    };
  };
  ```

### 1.3 Resolution Layer

- [ ] Create `nix/generators/` directory
- [ ] Implement `nix/generators/resolve.nix`
  - [ ] Parse `toolchain.toml` (use `lib.importTOML`)
  - [ ] Load `nix/toolchains/registry.nix`
  - [ ] Resolve each declared toolchain version
  - [ ] Handle missing versions with clear error messages
  - [ ] Return resolved derivations structure

- [ ] Add validation
  - [ ] Check that declared versions exist in registry
  - [ ] Verify derivations are valid
  - [ ] Provide helpful error messages

### 1.4 Shell Environment Generation

- [ ] Update `nix/shell.nix` to use resolved toolchains
  - [ ] Import resolved toolchains from `resolve.nix`
  - [ ] Add resolved packages to `devShell.packages`
  - [ ] Remove hardcoded language tool versions

- [ ] Update `flake.nix` to integrate resolution layer
  - [ ] Wire up toolchain resolution
  - [ ] Ensure `nix develop` uses resolved toolchains

- [ ] Test shell environment
  - [ ] Verify `nix develop` succeeds
  - [ ] Check `which go` points to Nix store
  - [ ] Verify `go version` matches declared version
  - [ ] Repeat for rust, python

### 1.5 Buck2 Toolchain Generation

- [ ] Implement `nix/generators/buck2.nix`
  - [ ] Accept resolved toolchains as input
  - [ ] Generate `toolchains/BUCK` with system toolchain definitions
  - [ ] Use full Nix store paths in generated config
  - [ ] Add "DO NOT EDIT MANUALLY" header
  - [ ] Include generation timestamp and source info

- [ ] Generate per-language toolchain files
  - [ ] `toolchains/go/BUCK` with `system_go_toolchain`
  - [ ] `toolchains/rust/BUCK` with `system_rust_toolchain`
  - [ ] `toolchains/python/BUCK` with `system_python_bootstrap_toolchain`

- [ ] Add toolchain fingerprinting (optional, for debugging)
  - [ ] Extract Nix derivation hash
  - [ ] Include as `fingerprint` attribute in generated BUCK files

### 1.6 Integration and Testing

- [ ] Create generation script/hook
  - [ ] Add `nix/generate-toolchains.sh` script
  - [ ] Integrate with `nix develop` via devenv hooks
  - [ ] Auto-regenerate Buck2 configs when entering shell

- [ ] Update `.gitignore`
  - [ ] Add `toolchains/BUCK` (generated)
  - [ ] Add `toolchains/*/BUCK` (generated)
  - [ ] Document that these are generated files

- [ ] Validation tests
  - [ ] Script to compare shell paths vs Buck2 config paths
  - [ ] Test that `which go` == `buck2 audit config go_bin`
  - [ ] Verify cache invalidation on version change

- [ ] Update documentation
  - [ ] Document generation workflow in `docs/src/architecture.md`
  - [ ] Add troubleshooting guide
  - [ ] Update getting started guide

### 1.7 Example Project Testing

- [ ] Test with existing `experimental/rs-hello-world`
  - [ ] Verify builds work with generated toolchains
  - [ ] Test both `cargo build` and `buck2 build`
  - [ ] Confirm identical behavior

- [ ] Test with `experimental/go-hello-world`
  - [ ] Verify builds work with generated toolchains
  - [ ] Test both `go build` and `buck2 build`
  - [ ] Confirm identical behavior

## Phase 2: Buck2 Caching Validation

**Goal**: Verify Buck2 caching works correctly with Nix-based toolchains.

**Success Criteria**:
- [ ] Local caching works with generated toolchains
- [ ] Toolchain changes trigger cache invalidation
- [ ] Cache keys are stable across identical toolchain configs
- [ ] Cache hit rate > 80% for incremental builds

### 2.1 Local Caching Tests

- [ ] Set up local Buck2 cache
  - [ ] Configure `.buckconfig` for local caching
  - [ ] Test cache warming with sample project

- [ ] Verify cache invalidation on toolchain change
  - [ ] Build project with Go 1.21.5
  - [ ] Change `toolchain.toml` to Go 1.22.0
  - [ ] Regenerate Buck2 config
  - [ ] Verify rebuild occurs (cache miss)
  - [ ] Verify new cache entries created

- [ ] Verify cache invalidation on patch addition
  - [ ] Build project with unpatched Go 1.21.5
  - [ ] Add patch to registry for Go 1.21.5
  - [ ] Regenerate Buck2 config (new Nix store path)
  - [ ] Verify rebuild occurs (cache miss)

### 2.2 Cache Stability Tests

- [ ] Test cache stability across shell re-entry
  - [ ] Build project
  - [ ] Exit and re-enter `nix develop`
  - [ ] Rebuild project
  - [ ] Verify cache hit (no rebuild)

- [ ] Test cache stability across machines (requires flake.lock)
  - [ ] Build on machine A
  - [ ] Clone repo on machine B
  - [ ] Ensure same `flake.lock`
  - [ ] Verify `which go` returns same path on both machines
  - [ ] Build on machine B
  - [ ] Document expected cache behavior

### 2.3 Remote Caching (Optional)

- [ ] Set up remote cache server (if available)
  - [ ] Configure Buck2 remote cache URL
  - [ ] Test upload/download of artifacts

- [ ] Verify remote cache sharing
  - [ ] Build on machine A, upload to remote cache
  - [ ] Build on machine B, verify cache hit from remote

### 2.4 Monitoring and Debugging

- [ ] Add cache hit rate monitoring
  - [ ] Document `buck2 summary` usage
  - [ ] Add script to extract cache metrics

- [ ] Create debugging tools
  - [ ] Script to show toolchain fingerprints
  - [ ] Script to compare Nix derivation vs Buck2 config
  - [ ] Document cache miss diagnosis workflow

## Phase 3: Prelude Customization

**Goal**: Fork Buck2 prelude and customize for system toolchain integration.

**Success Criteria**:
- [ ] Custom prelude works with generated toolchains
- [ ] No embedded toolchains in prelude
- [ ] All language rules work with system toolchains

### 3.1 Prelude Fork

- [ ] Fork buck2-prelude repository
  - [ ] Create `prelude/` directory at repo root
  - [ ] Copy relevant language modules (go, rust, python)
  - [ ] Remove embedded toolchain binaries
  - [ ] Document fork point and rationale

- [ ] Customize toolchain registration
  - [ ] Create `prelude/toolchains/register.bzl`
  - [ ] Auto-generate registration from resolved toolchains
  - [ ] Wire up system toolchains

### 3.2 Integration

- [ ] Update `.buckconfig` to use custom prelude
  ```ini
  [repositories]
  prelude = prelude
  ```

- [ ] Test all language rules
  - [ ] `go_binary`, `go_test`
  - [ ] `rust_binary`, `rust_test`
  - [ ] `python_binary`, `python_test`

- [ ] Update build targets to use custom prelude
  - [ ] Update `experimental/rs-hello-world/BUCK`
  - [ ] Update `experimental/go-hello-world/BUCK`

## Phase 4: External Cell for Build Utilities

**Goal**: Create Nix-managed external cell with codegen tools.

**Success Criteria**:
- [ ] Gazelle-like tool for Go dependency management
- [ ] Reindeer-like tool for Rust dependency management
- [ ] Tools available automatically in `nix develop`

### 4.1 External Cell Structure

- [ ] Create `nix/cells/tooling/` directory structure
  - [ ] Add `BUCK` root file
  - [ ] Create subdirectories for each tool

- [ ] Register external cell in `.buckconfig`
  ```ini
  [cells]
  tooling = nix/cells/tooling
  ```

### 4.2 Build Utilities (To Be Designed)

- [ ] Evaluate existing tools
  - [ ] Research Gazelle for Go
  - [ ] Research reindeer for Rust
  - [ ] Research buckify alternatives

- [ ] Design integration approach
  - [ ] How tools are built/packaged in Nix
  - [ ] How tools are exposed to developers
  - [ ] How tools integrate with Buck2 workflow

## Phase 5: Advanced Registry Features

**Goal**: Add sophisticated toolchain management features to registry.

**Success Criteria**:
- [ ] Registry supports custom patches transparently
- [ ] Registry supports build-from-source options
- [ ] Registry includes comprehensive metadata

### 5.1 Patch Management

- [ ] Create `nix/toolchains/patches/` directory
- [ ] Add example patches
  - [ ] Security patch example
  - [ ] Performance patch example

- [ ] Update registry with patch examples
  - [ ] Go 1.21.5 with security patch
  - [ ] Document patch application process

### 5.2 Build-from-Source Support

- [ ] Add build-from-source example to registry
  - [ ] Example: latest Rust with specific LLVM version
  - [ ] Document performance implications

- [ ] Document when to use build-from-source
  - [ ] Security requirements
  - [ ] Custom features needed
  - [ ] Performance tuning

### 5.3 Metadata and Documentation

- [ ] Enhance registry metadata
  - [ ] Add version history tracking
  - [ ] Add deprecation notices
  - [ ] Add known issues / caveats

- [ ] Create registry documentation
  - [ ] How to add new versions
  - [ ] How to apply patches
  - [ ] How to deprecate old versions

## Phase 6: CI/CD Integration

**Goal**: Ensure architecture works seamlessly in CI environments.

**Success Criteria**:
- [ ] CI builds use same toolchains as local development
- [ ] Remote caching works in CI
- [ ] Cache hit rates are high in CI

### 6.1 CI Configuration

- [ ] Set up Nix in CI environment
  - [ ] Install Nix
  - [ ] Configure flake support
  - [ ] Cache Nix store between runs

- [ ] Configure Buck2 in CI
  - [ ] Set up remote cache
  - [ ] Configure cache credentials
  - [ ] Monitor cache hit rates

### 6.2 Validation

- [ ] Add CI job to validate toolchain synchronization
  - [ ] Check that generated Buck2 configs are up-to-date
  - [ ] Verify Nix store paths match between dev and CI
  - [ ] Fail if generated files are stale

- [ ] Add CI job to test cache behavior
  - [ ] Build all targets
  - [ ] Rebuild with no changes (verify cache hits)
  - [ ] Report cache hit rate

## Phase 7: Alternative Backend Exploration

**Goal**: Validate that architecture supports multiple backends (beyond Nix).

**Success Criteria**:
- [ ] Design documented for mise backend
- [ ] Proof-of-concept implementation (optional)

### 7.1 Backend Abstraction

- [ ] Document backend interface requirements
  - [ ] What must a backend provide?
  - [ ] How does backend integrate with toolchain.toml?
  - [ ] How does backend generate Buck2 configs?

- [ ] Design mise backend (documentation only)
  - [ ] How mise resolves versions
  - [ ] How mise applies patches
  - [ ] How mise generates Buck2 configs

### 7.2 Backend Selection

- [ ] Document backend selection mechanism
  - [ ] How repo chooses backend (env var, config file?)
  - [ ] How to switch backends
  - [ ] Migration guide between backends

## Documentation Tasks

- [ ] Update `docs/src/architecture.md` with implementation notes
- [ ] Create tutorial: "Adding a new toolchain version"
- [ ] Create tutorial: "Applying a security patch"
- [ ] Create troubleshooting guide
- [ ] Create performance optimization guide
- [ ] Add FAQ section

## Testing and Validation

- [ ] Create test suite for toolchain resolution
- [ ] Create test suite for Buck2 config generation
- [ ] Create test suite for cache behavior
- [ ] Add integration tests for end-to-end workflow
- [ ] Document testing procedures

## Future Enhancements (Backlog)

- [ ] Multi-platform support (Linux, macOS, different architectures)
- [ ] Toolchain composition (custom gopls with standard go)
- [ ] Automatic registry updates from upstream releases
- [ ] Toolchain version pinning for reproducibility audits
- [ ] Support for proprietary/internal toolchains

---

## Notes

- Each task should be broken down further during implementation
- Success criteria should be validated before marking phase complete
- Update this document as implementation progresses
- Link to relevant design documents and discussions
- Track blockers and dependencies between tasks

## References

- [Toolchain Synchronization Design](./docs/src/design/toolchain-synchronization.md)
- [Architecture Overview](./docs/src/architecture.md)
- [Buck2 Documentation](https://buck2.build/)
- [Nix Manual](https://nixos.org/manual/nix/stable/)

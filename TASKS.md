# Toolchain Synchronization Implementation Tasks

This document tracks the implementation roadmap for the [Toolchain Synchronization Architecture](./docs/src/design/toolchain-synchronization.md).

## Overview

The goal is to implement a registry-based toolchain resolution system that guarantees synchronization between native tooling (shell environment) and Buck2 builds. This will be packaged as a **reusable Nix flake module** that other repositories can import.

### Evolution Path

**Phase 0-7**: Develop the solution within this repository
- Prototype and iterate quickly
- Use this repo as a reference implementation
- Validate approach with real use cases

**Phase 8**: Extract into TWO standalone repositories

1. **`firefly-engineering/turnkey`**: Core toolchain synchronization module
   - Generic resolution mechanism
   - Shell environment generation
   - Buck2 config generation
   - Registry interface/API
   - **No toolchain versions** - just the mechanism

2. **`firefly-engineering/toolchain-registry`**: Default toolchain registry
   - Curated toolchain versions (Go, Rust, Python, etc.)
   - Patches and customizations
   - Metadata and documentation
   - Can be used with `turnkey` or replaced

**Final State**: This repository becomes a downstream consumer
- Imports both `turnkey` (module) and `toolchain-registry` (default versions)
- Demonstrates reference implementation
- May provide custom registry overrides for Firefly-specific needs

This separation allows:
- ✅ **Mechanism vs. Data**: Core logic separate from version catalog
- ✅ **Independent Versioning**: Module updates don't require registry updates and vice versa
- ✅ **Custom Registries**: Organizations can use turnkey with their own registries
- ✅ **Community Maintenance**: Registry can accept community contributions for new versions

### User Experience (Target State)

**Note**: These examples show the target user experience after extraction to a standalone repository (Phase 8). During initial development (Phases 0-7), this repository will contain the module code locally.

For downstream repositories using the extracted solution:

1. **Import the modules** in their `flake.nix`:
   ```nix
   # After Phase 8 extraction (two repositories):
   inputs.turnkey.url = "github:firefly-engineering/turnkey";
   inputs.toolchain-registry.url = "github:firefly-engineering/toolchain-registry";

   # During development (Phases 0-7), this repo contains everything:
   # inputs.firefly-toolchains.url = "github:firefly-engineering/src";
   ```

2. **Configure** in `flake.nix`:
   ```nix
   # Using default registry
   devShells.default = turnkey.lib.mkDevShell {
     system = "x86_64-linux";
     registry = toolchain-registry.registry;  # Use default registry
   };

   # Or with custom registry
   devShells.default = turnkey.lib.mkDevShell {
     system = "x86_64-linux";
     registry = ./my-custom-registry.nix;  # Override with custom
   };

   # Or extend default registry
   devShells.default = turnkey.lib.mkDevShell {
     system = "x86_64-linux";
     registry = turnkey.lib.extendRegistry
       toolchain-registry.registry
       ./my-additions.nix;
   };
   ```

3. **Define toolchains** in local `toolchain.toml`:
   ```toml
   [go]
   version = "1.21.5"
   ```

4. **Profit!** - Both shell and Buck2 automatically use synchronized toolchains

### Complete Example

**Downstream repository structure**:
```
my-app/
├── flake.nix              # Imports firefly-toolchains module
├── toolchain.toml         # Declares: go = "1.21.5"
├── .buckconfig
├── experimental/
│   └── my-service/
│       ├── BUCK
│       ├── main.go
│       └── go.mod
```

**Full flake.nix**:
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # After extraction (Phase 8) - Two separate repos:
    turnkey.url = "github:firefly-engineering/turnkey";
    toolchain-registry.url = "github:firefly-engineering/toolchain-registry";

    # During development (Phases 0-7) - Single repo:
    # firefly-toolchains.url = "github:firefly-engineering/src";
  };

  outputs = { self, nixpkgs, turnkey, toolchain-registry }: {
    devShells.x86_64-linux.default = turnkey.lib.mkDevShell {
      system = "x86_64-linux";
      registry = toolchain-registry.registry;  # Use community-maintained registry
      # toolchain.toml is automatically found at ./toolchain.toml
    };
  };
}
```

**Developer workflow**:
```bash
# Clone repo
git clone https://github.com/myorg/my-app
cd my-app

# Enter shell (first time: downloads Nix dependencies)
nix develop

# Verify toolchains
go version                    # go version go1.21.5 linux/amd64
which go                      # /nix/store/abc123.../bin/go
buck2 audit config go_bin     # /nix/store/abc123.../bin/go  ✅ Same!

# Build with native tools
cd experimental/my-service
go build
go test

# Build with Buck2
buck2 build //experimental/my-service:my-service
buck2 test //experimental/my-service:...

# Both use identical Go binary!
```

### Architecture Components

The complete system consists of three parts:

1. **`toolchain.toml`**: High-level declaration of toolchain versions (per-repository, local to each project)
   ```toml
   [go]
   version = "1.21.5"
   ```

2. **`turnkey` module**: Core synchronization mechanism (github:firefly-engineering/turnkey)
   - Resolution logic: `toolchain.toml` + registry → derivations
   - Shell environment generation
   - Buck2 config generation
   - Registry interface/API
   - **No toolchain versions** - completely generic

3. **`toolchain-registry`**: Version catalog (github:firefly-engineering/toolchain-registry)
   - Curated toolchain versions for all languages
   - Patches and customizations
   - Can be replaced or extended by users
   - Community-maintained

Both the development shell and Buck2 toolchain configurations are generated from the same resolved derivations, ensuring identical binaries.

**Key Insight**: The mechanism (`turnkey`) and data (`toolchain-registry`) are separate, allowing:
- Organizations to use `turnkey` with their own registries
- Community contributions to `toolchain-registry` without touching core logic
- Independent versioning (registry updates don't require module updates)

## Current Status

- [x] Design document completed
- [x] Documentation updated (architecture.md, introduction.md)
- [ ] Implementation not started

## Phase 0: Flake Module Architecture

**Goal**: Create the reusable Nix flake module infrastructure that other repositories can import.

**Important**: Design module for eventual extraction (Phase 8). Keep module code self-contained and avoid dependencies on this repository's specific structure.

**Success Criteria**:
- [ ] Flake module can be imported by downstream repos
- [ ] Module provides default registry
- [ ] Module exposes configuration options
- [ ] Module generates both shell and Buck2 configs
- [ ] Module code is self-contained and portable

### 0.1 Flake Module Structure

- [ ] Create `nix/modules/` directory structure
- [ ] Create `nix/modules/toolchains/default.nix` as main module
- [ ] Define module interface/API
  - [ ] `firefly.toolchains.registry` - Path to registry or use default
  - [ ] `firefly.toolchains.declarationFile` - Path to toolchain.toml (default: ./toolchain.toml)
  - [ ] `firefly.toolchains.buck2.enable` - Enable Buck2 config generation (default: true)

- [ ] Export module in root `flake.nix`
  ```nix
  outputs = { self, nixpkgs, ... }: {
    nixosModules.toolchains = import ./nix/modules/toolchains;
    # or for flake-parts:
    flakeModules.toolchains = import ./nix/modules/toolchains;
  };
  ```

### 0.2 Default Registry

- [ ] Create `nix/modules/toolchains/registry-default.nix`
  - [ ] Include commonly-used Go versions
  - [ ] Include commonly-used Rust versions
  - [ ] Include commonly-used Python versions
  - [ ] Include commonly-used C/C++ toolchains
  - [ ] Document versioning policy for default registry

- [ ] Make registry overridable
  - [ ] Allow downstream repos to provide custom registry
  - [ ] Allow downstream repos to extend default registry
  - [ ] Document registry extension patterns

### 0.3 Module Implementation

- [ ] Implement toolchain resolution in module
  - [ ] Read toolchain.toml from configured path
  - [ ] Load registry (default or custom)
  - [ ] Resolve versions to derivations
  - [ ] Handle missing versions gracefully

- [ ] Implement shell environment generation
  - [ ] Add resolved toolchains to devShell.packages
  - [ ] Set up environment variables if needed
  - [ ] Add any required shell hooks

- [ ] Implement Buck2 config generation
  - [ ] Generate toolchains/BUCK file
  - [ ] Generate per-language BUCK files
  - [ ] Make generation optional via config
  - [ ] Add generation hooks

### 0.4 Documentation for Module Users

- [ ] Create `docs/src/user-guide/` directory
- [ ] Write "Getting Started" guide for downstream repos
  - [ ] How to add flake input
  - [ ] How to import module
  - [ ] How to create toolchain.toml
  - [ ] How to verify setup

- [ ] Write "Configuration" guide
  - [ ] How to override default registry
  - [ ] How to extend default registry
  - [ ] How to customize Buck2 generation

- [ ] Write "Custom Registry" guide
  - [ ] Registry schema explanation
  - [ ] How to add custom versions
  - [ ] How to apply patches
  - [ ] Examples

### 0.5 Self-Hosting Test

- [ ] Use module in this repository (dog-fooding)
  - [ ] Import module from local path
  - [ ] Create toolchain.toml for this repo
  - [ ] Verify shell works
  - [ ] Verify Buck2 configs are generated

- [ ] Test module override capabilities
  - [ ] Test custom registry path
  - [ ] Test declarationFile override
  - [ ] Test buck2.enable = false

## Phase 1: Refinement and Testing

**Goal**: Refine the module implementation from Phase 0 and ensure it works robustly.

**Note**: This phase builds on Phase 0. By this point, the basic module architecture should be in place. Phase 1 focuses on refinement, edge case handling, and comprehensive testing.

**Success Criteria**:
- [ ] Module works in multiple test scenarios
- [ ] Error handling is comprehensive
- [ ] Documentation is complete and accurate
- [ ] `which go` and `buck2 audit config go_bin` return identical paths
- [ ] Module is ready for external users

### 1.1 Error Handling and Edge Cases

- [ ] Handle missing toolchain.toml
  - [ ] Provide clear error message
  - [ ] Suggest creating from template

- [ ] Handle unknown toolchain versions
  - [ ] List available versions in error message
  - [ ] Suggest checking registry or updating

- [ ] Handle malformed toolchain.toml
  - [ ] TOML parsing errors with line numbers
  - [ ] Schema validation errors with helpful messages

- [ ] Handle registry errors
  - [ ] Missing registry file
  - [ ] Invalid registry format
  - [ ] Derivation build failures

### 1.2 Validation and Testing

- [ ] Create validation script
  - [ ] Compare shell paths vs Buck2 config paths
  - [ ] Test that `which go` == `buck2 audit config go_bin`
  - [ ] Report any mismatches

- [ ] Test toolchain version changes
  - [ ] Change version in toolchain.toml
  - [ ] Re-enter shell
  - [ ] Verify new version is active
  - [ ] Verify Buck2 config updated

- [ ] Test with existing example projects
  - [ ] `experimental/rs-hello-world`: both cargo and buck2 builds
  - [ ] `experimental/go-hello-world`: both go and buck2 builds
  - [ ] Verify identical behavior

### 1.3 Downstream Repository Testing

- [ ] Create test downstream repository
  - [ ] Import this repo as flake input
  - [ ] Use module with default registry
  - [ ] Create simple toolchain.toml
  - [ ] Verify shell and Buck2 work

- [ ] Test custom registry in downstream
  - [ ] Create custom registry file
  - [ ] Override default registry
  - [ ] Verify custom versions work

- [ ] Test registry extension in downstream
  - [ ] Extend default registry with custom versions
  - [ ] Verify both default and custom versions work

### 1.4 Documentation Polish

- [ ] Review and update all user-facing docs
  - [ ] Getting started guide
  - [ ] Configuration reference
  - [ ] Custom registry guide
  - [ ] Troubleshooting guide

- [ ] Add examples
  - [ ] Minimal example
  - [ ] Custom registry example
  - [ ] Multi-language example
  - [ ] Patched toolchain example

- [ ] Add API reference
  - [ ] Module options documentation
  - [ ] Registry schema documentation
  - [ ] toolchain.toml schema documentation

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

## Phase 8: Repository Extraction and Migration

**Goal**: Extract toolchain synchronization solution into TWO standalone repositories (mechanism + registry), making this repo a downstream consumer.

**Success Criteria**:
- [ ] `turnkey` repo contains core mechanism
- [ ] `toolchain-registry` repo contains version catalog
- [ ] This repository successfully imports and uses both extracted repos
- [ ] No functionality loss during migration
- [ ] Clear separation: mechanism vs. data

### 8.1 Preparation

- [ ] Review current implementation for portability
  - [ ] Identify module code (goes to turnkey)
  - [ ] Identify registry code (goes to toolchain-registry)
  - [ ] Identify any repo-specific assumptions
  - [ ] Document dependencies between mechanism and registry

- [ ] Plan repository structures
  - [ ] `firefly-engineering/turnkey`: Module structure
  - [ ] `firefly-engineering/toolchain-registry`: Registry structure
  - [ ] Plan versioning strategy (semantic versioning for both)

### 8.2 Create Turnkey Repository (Core Mechanism)

- [ ] Create `firefly-engineering/turnkey` repository
  - [ ] Set up GitHub repository
  - [ ] Initialize with appropriate license (MIT or Apache 2.0)
  - [ ] Set up basic CI/CD

- [ ] Move mechanism code
  - [ ] Move `nix/modules/toolchains/` (without registry)
  - [ ] Move resolution logic
  - [ ] Move shell generation logic
  - [ ] Move Buck2 config generation logic
  - [ ] Define registry interface/API

- [ ] Set up documentation
  - [ ] Create README explaining "what" and "why"
  - [ ] Document registry interface
  - [ ] Add usage examples (with custom registries)
  - [ ] Set up mdbook for comprehensive docs

### 8.3 Create Toolchain Registry Repository (Version Catalog)

- [ ] Create `firefly-engineering/toolchain-registry` repository
  - [ ] Set up GitHub repository
  - [ ] Initialize with appropriate license
  - [ ] Set up CI/CD for testing registry entries

- [ ] Move registry code
  - [ ] Move default registry definitions
  - [ ] Move toolchain version entries
  - [ ] Move patches directory
  - [ ] Organize by language/tool

- [ ] Set up registry structure
  ```
  toolchain-registry/
  ├── registry.nix        # Main registry export
  ├── go/
  │   ├── versions.nix    # Go versions
  │   └── patches/        # Go patches
  ├── rust/
  │   ├── versions.nix
  │   └── patches/
  └── python/
      ├── versions.nix
      └── patches/
  ```

- [ ] Set up documentation
  - [ ] README with available versions
  - [ ] Contribution guide for adding versions
  - [ ] Testing guide for registry entries
  - [ ] Changelog for registry updates

### 8.4 Migration of This Repository

- [ ] Update this repo's `flake.nix`
  - [ ] Remove local module code
  - [ ] Add flake input for `turnkey`
  - [ ] Add flake input for `toolchain-registry`
  - [ ] Update to use external modules

- [ ] Create/update `toolchain.toml`
  - [ ] Verify format is compatible
  - [ ] Document versions used

- [ ] Test migration
  - [ ] Verify `nix develop` still works
  - [ ] Verify Buck2 config generation works
  - [ ] Verify all example projects build
  - [ ] Compare behavior before/after migration
  - [ ] Test registry override capability

- [ ] Update documentation in this repo
  - [ ] Update architecture docs to reference external modules
  - [ ] Add "Reference Implementation" guide
  - [ ] Keep design docs as historical reference
  - [ ] Document why we use specific registry versions

- [ ] Optional: Add Firefly-specific registry overrides
  - [ ] Create `nix/custom-registry.nix` if needed
  - [ ] Document custom versions/patches
  - [ ] Show how to extend community registry

### 8.5 Cleanup

- [ ] Remove now-redundant code from this repo
  - [ ] Archive old module code
  - [ ] Remove old registry code
  - [ ] Clean up nix/ directory structure
  - [ ] Update .gitignore if needed

- [ ] Document the split
  - [ ] Update README to explain relationship with both repos
  - [ ] Add badges/links to turnkey and toolchain-registry
  - [ ] Document benefits of two-repo architecture

### 8.6 Publishing Both Repositories

**Turnkey (Mechanism)**:
- [ ] Tag v1.0.0 release
- [ ] Create comprehensive README
- [ ] Emphasize registry flexibility
- [ ] Provide examples with different registries
- [ ] Set up GitHub Releases
- [ ] Configure branch protection

**Toolchain Registry (Data)**:
- [ ] Tag v1.0.0 release
- [ ] Create README listing all versions
- [ ] Set up automated testing for registry entries
- [ ] Create contribution guide
- [ ] Set up GitHub Releases
- [ ] Enable community PRs for new versions

**Discoverability**:
- [ ] Submit both to Nix flake registries
- [ ] Create announcement blog post explaining architecture
- [ ] Share in Nix community (Discourse, Reddit)
- [ ] Share in Buck2 community
- [ ] Create example repos using both

## Phase 9: Publishing and Distribution

**Goal**: Ongoing maintenance and community growth for standalone toolchain solution.

**Note**: This phase assumes the solution has been extracted (Phase 8).

**Success Criteria**:
- [ ] Module is published and discoverable
- [ ] Clear onboarding for new users
- [ ] Support channels established

### 8.1 Publishing

- [ ] Tag stable release
  - [ ] Version 1.0.0 when ready
  - [ ] Semantic versioning for future releases

- [ ] Announce in relevant communities
  - [ ] Nix community (Discourse, Reddit)
  - [ ] Buck2 community
  - [ ] Create blog post explaining benefits

### 8.2 Discoverability

- [ ] Add to Nix flake registries (if appropriate)
- [ ] Create example repositories
  - [ ] Minimal Go project
  - [ ] Minimal Rust project
  - [ ] Multi-language project

### 8.3 Support and Maintenance

- [ ] Create issue templates
  - [ ] Bug report template
  - [ ] Feature request template
  - [ ] Help request template

- [ ] Document contribution guidelines
  - [ ] How to add new toolchain versions to default registry
  - [ ] How to test changes
  - [ ] Code review process

- [ ] Establish support channels
  - [ ] GitHub Discussions for Q&A
  - [ ] GitHub Issues for bugs/features

## Documentation Tasks

- [ ] Update `docs/src/architecture.md` with implementation notes
- [ ] Create tutorial: "Getting Started - Using the Module"
- [ ] Create tutorial: "Adding a new toolchain version"
- [ ] Create tutorial: "Applying a security patch"
- [ ] Create tutorial: "Creating a custom registry"
- [ ] Create troubleshooting guide
- [ ] Create performance optimization guide
- [ ] Add FAQ section
- [ ] Add "Why use this?" comparison with alternatives

## Testing and Validation

- [ ] Create test suite for toolchain resolution
- [ ] Create test suite for Buck2 config generation
- [ ] Create test suite for cache behavior
- [ ] Add integration tests for end-to-end workflow
- [ ] Document testing procedures

## Future Enhancements (Backlog)

### For Standalone Project (Post-Extraction)

- [ ] Multi-platform support (Linux, macOS, different architectures)
- [ ] Toolchain composition (custom gopls with standard go)
- [ ] Automatic registry updates from upstream releases
- [ ] Toolchain version pinning for reproducibility audits
- [ ] Support for proprietary/internal toolchains
- [ ] Integration with other build systems (Bazel, Please Build)
- [ ] Web UI for browsing available toolchain versions
- [ ] Automatic security advisory notifications

### Repository Naming

**Decided Architecture** (as of Phase 8 planning):

1. **`firefly-engineering/turnkey`**
   - Name emphasizes ease of use ("turnkey solution")
   - Generic enough for community adoption
   - Not tied to specific build system (future: support Bazel, etc.)

2. **`firefly-engineering/toolchain-registry`**
   - Descriptive name, clear purpose
   - Emphasizes that it's data, not mechanism
   - Open to community contributions

**Alternative names considered** (archived for reference):
- `nix-buck2-sync` - too specific to implementation
- `hermetic-toolchains` - good but less memorable
- `nixbuck` - too cute, unclear meaning

**Why "turnkey"?**:
- Emphasizes the user experience: it "just works"
- Not locked to Buck2 or Nix (future extensibility)
- Memorable and searchable
- Communicates value proposition clearly

---

## Notes

- Each task should be broken down further during implementation
- Success criteria should be validated before marking phase complete
- Update this document as implementation progresses
- Link to relevant design documents and discussions
- Track blockers and dependencies between tasks

## References

### This Repository
- [Toolchain Synchronization Design](./docs/src/design/toolchain-synchronization.md)
- [Architecture Overview](./docs/src/architecture.md)

### Future Standalone Project (Post Phase 8)
- Repository: TBD (e.g., `github:firefly-engineering/firefly-buck2-toolchains`)
- Documentation: Will be established during extraction

### External
- [Buck2 Documentation](https://buck2.build/)
- [Buck2 GitHub](https://github.com/facebook/buck2)
- [Nix Manual](https://nixos.org/manual/nix/stable/)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)

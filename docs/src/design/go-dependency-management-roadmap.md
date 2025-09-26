# Go Dependency Management Implementation Roadmap

## Overview

This document outlines the roadmap for implementing Go dependency management as described in the [Architecture document](../architecture.md). The implementation will demonstrate the Nix + Buck2 hybrid architecture with a concrete test case using the `golang.org/x/example/hello/reverse` package.

## Test Case: golang.org/x/example/hello/reverse

The implementation will focus on enabling a Go program that uses the `golang.org/x/example/hello/reverse` package:

```go
package main

import (
    "fmt"
    "golang.org/x/example/hello/reverse"
)

func main() {
    fmt.Println(reverse.String("Hello, Firefly!"))
    // Output: !ylferif ,olleH
}
```

This serves as a practical demonstration of our dependency management system handling external Go modules.

## Current State Analysis

### ✅ Existing Infrastructure

- **Nix Development Environment**: Working devenv setup with Go toolchain
- **Buck2 Integration**: System Go toolchains configured and functional
- **Basic Go Building**: Simple Go programs build successfully with Buck2
- **Directory Structure**: Well-organized monorepo structure in place

### 📋 Missing Components

- **Centralized Dependency Declaration**: No Nix-based dependency management
- **GOPROXY Implementation**: No module proxy serving from Nix store
- **Environment Variable Configuration**: Missing transparent toolchain configuration
- **Dependency Bridge Layer**: No transparent access for both Buck2 and native tooling

## Implementation Phases

### Phase 1: Nix Dependency Declaration System

**Timeline**: 1-2 weeks
**Goal**: Establish centralized Go module dependency declarations in Nix

#### Deliverables

1. **JSON dependency declaration format**:
   ```json
   // nix/dependencies/go-modules.json
   {
     "golang.org/x/example": [
       {
         "version": "v0.0.0-20231025140028-3c0104f4b233",
         "hash": "sha256-8c+wXZC1cJAHCZQ6l1S4xxHAQfJ5KXvfvkZVV4j1Zw4=",
         "time": "2023-10-25T14:00:28Z",
         "repo": "https://go.googlesource.com/example",
         "packages": [
           "golang.org/x/example/hello/reverse"
         ]
       }
     ],
     "github.com/gorilla/mux": [
       {
         "version": "v1.8.1",
         "hash": "sha256-xyz123...",
         "time": "2023-11-01T10:00:00Z",
         "repo": "https://github.com/gorilla/mux"
       }
     ]
   }
   ```

2. **Nix JSON parser and module fetching**:
   ```nix
   # nix/dependencies/go-parser.nix
   { lib, fetchFromGitHub, fetchgit, ... }:
   let
     goModulesJson = builtins.fromJSON (builtins.readFile ./go-modules.json);

     fetchModule = moduleSpec: fetchgit {
       url = moduleSpec.repo;
       rev = moduleSpec.version;
       sha256 = moduleSpec.hash;
       # Additional fetchgit parameters
     };

     processModules = lib.mapAttrs (moduleName: versions:
       lib.map (version: {
         name = moduleName;
         inherit (version) version hash time;
         src = fetchModule version;
         submodules = version.submodules or [];
       }) versions
     ) goModulesJson;
   in
   processModules
   ```

3. **Tooling for dependency management**:
   - Script to add new dependencies to JSON file
   - Hash calculation and validation utilities
   - Version resolution and conflict detection

#### Technical Requirements

- JSON format must be valid and easily editable by developers
- Support multiple versions per module for dependency resolution
- Use `fetchgit` or `fetchFromGitHub` for reliable module fetching
- Implement proper version pinning and hash verification
- Handle both Git repositories and module proxy sources

#### Acceptance Criteria

- [ ] Go dependencies declared in JSON format
- [ ] Nix successfully parses JSON and fetches modules
- [ ] Support for multiple versions per module
- [ ] Modules successfully fetched and stored in Nix store
- [ ] Hash verification prevents supply chain attacks
- [ ] Tooling available for adding new dependencies

### Phase 2: GOPROXY Filesystem Layout

**Timeline**: 1-2 weeks
**Goal**: Generate a filesystem layout compatible with GOPROXY `file://` protocol

#### Deliverables

1. **Nix function to generate GOPROXY filesystem layout**:
   ```nix
   # nix/dependencies/goproxy-layout.nix
   { lib, runCommand, ... }:

   let
     goModules = import ./go-parser.nix { inherit lib fetchgit; };

     generateProxyLayout = runCommand "goproxy-layout" {} ''
       mkdir -p $out
       ${lib.concatMapStringsSep "\n" (moduleName:
         let moduleVersions = goModules.${moduleName};
         in lib.concatMapStringsSep "\n" (modInfo: ''
           # Generate proxy structure for ${moduleName}@${modInfo.version}
           ESCAPED_PATH="${lib.replaceStrings ["/"] ["!"] moduleName}"
           mkdir -p "$out/$ESCAPED_PATH/@v"

           # Add version to list (append if exists)
           echo "${modInfo.version}" >> "$out/$ESCAPED_PATH/@v/list"

           # Generate version info
           echo '{"Version":"${modInfo.version}","Time":"${modInfo.time}"}' > \
             "$out/$ESCAPED_PATH/@v/${modInfo.version}.info"

           # Copy go.mod from source
           if [ -f "${modInfo.src}/go.mod" ]; then
             cp "${modInfo.src}/go.mod" "$out/$ESCAPED_PATH/@v/${modInfo.version}.mod"
           else
             echo "module ${moduleName}" > "$out/$ESCAPED_PATH/@v/${modInfo.version}.mod"
           fi

           # Create module zip
           cd "${modInfo.src}"
           ${pkgs.zip}/bin/zip -r "$out/$ESCAPED_PATH/@v/${modInfo.version}.zip" . \
             -x "*.git*" "*/.DS_Store*"
         '') moduleVersions
       ) (builtins.attrNames goModules)}

       # Sort version lists
       find $out -name "list" -exec sort -V -o {} {} \;
     '';
   in
   generateProxyLayout
   ```

2. **Module proxy protocol compliance**:
   - Generate `{module}/@v/list` files with available versions
   - Generate `{module}/@v/{version}.info` files with version metadata
   - Generate `{module}/@v/{version}.mod` files with go.mod content
   - Generate `{module}/@v/{version}.zip` files with module source

3. **Integration with Nix store**:
   - Fetch modules using `fetchFromGitHub` or similar
   - Apply module path escaping (e.g., `/` becomes `!`)
   - Generate proper version metadata from Git tags/commits
   - Create filesystem layout that matches GOPROXY protocol

#### Technical Requirements

- Follow [GOPROXY protocol specification](https://go.dev/ref/mod#goproxy-protocol) for filesystem layout
- Handle module path escaping correctly (`golang.org/x/example` → `golang.org!x!example`)
- Generate proper version metadata and go.mod files
- Support reproducible builds with fixed timestamps

#### Acceptance Criteria

- [ ] Filesystem layout matches GOPROXY protocol specification
- [ ] Can serve `golang.org/x/example` module and subpackages via `file://` URL
- [ ] Compatible with Go toolchain (`go mod download`, `go build`)
- [ ] Integration tests pass with real Go projects

### Phase 3: Environment Variable Configuration

**Timeline**: 1 week
**Goal**: Configure development environment to transparently use our filesystem-based GOPROXY

#### Deliverables

1. **Simplified devenv configuration**:
   ```nix
   # nix/devenv/languages.nix (enhanced)
   { ... }:
   let
     goproxyLayout = import ../dependencies/goproxy-layout.nix {
       inherit lib runCommand fetchgit pkgs;
     };
   in
   {
     languages = {
       # ... existing languages
       go = {
         enable = true;
         package = pkgs.go;
       };
     };

     env = {
       GOPROXY = "file://${goproxyLayout}";
       GOPATH = "$BUCK_OUT/go";
       GOCACHE = "$BUCK_OUT/go/cache";
       GOSUMDB = "off";  # Disable sum database for internal modules
     };

     enterShell = ''
       echo "🚀 Welcome to Firefly Engineering Monorepo"
       echo "Go modules available at: file://${goproxyLayout}"
       echo "Available modules:"
       ${lib.concatMapStringsSep "\n" (name:
         "echo '  - ${name}'"
       ) (builtins.attrNames (builtins.fromJSON (builtins.readFile ../dependencies/go-modules.json)))}
     '';
   }
   ```

2. **No process management needed**:
   - Remove all HTTP server and service management complexity
   - Direct filesystem access via `file://` URL
   - Zero runtime dependencies or background processes

3. **Buck2 integration verification**:
   - Ensure Buck2 uses the same GOPROXY configuration
   - Test that Buck2 Go builds use cached modules
   - Verify shared cache behavior

#### Technical Requirements

- Non-intrusive configuration (no user file modification)
- No runtime processes or service management
- Filesystem-only approach with reproducible Nix store paths
- Consistent behavior across different development scenarios
- Fast module resolution (no network overhead)

#### Acceptance Criteria

- [ ] GOPROXY configured automatically in development shell
- [ ] Go commands use local filesystem proxy transparently
- [ ] Buck2 builds use same module cache
- [ ] No background processes or service management required
- [ ] Module resolution works offline

### Phase 4: Test Implementation

**Timeline**: 1 week
**Goal**: Create working example using golang.org/x/example/hello/reverse

#### Deliverables

1. **Test program implementation**:
   ```go
   // experimental/go-reverse-example/main.go
   package main

   import (
       "fmt"
       "golang.org/x/example/hello/reverse"
   )

   func main() {
       original := "Hello, Firefly Engineering!"
       reversed := reverse.String(original)
       fmt.Printf("Original: %s\n", original)
       fmt.Printf("Reversed: %s\n", reversed)
   }
   ```

2. **Buck2 build configuration**:
   ```python
   # experimental/go-reverse-example/BUCK
   go_binary(
       name = "go-reverse-example",
       srcs = ["main.go"],
       visibility = ["PUBLIC"],
   )
   ```

3. **Native Go module configuration**:
   ```
   // experimental/go-reverse-example/go.mod
   module example.com/go-reverse-example

   go 1.21

   require golang.org/x/example v0.0.0-20231025140028-3c0104f4b233
   ```

4. **Comprehensive testing**:
   - Verify Buck2 build works: `buck2 build //experimental/go-reverse-example:go-reverse-example`
   - Verify native build works: `cd experimental/go-reverse-example && go build`
   - Verify both produce identical results
   - Test IDE integration (gopls, VS Code)

#### Technical Requirements

- Both Buck2 and native Go builds must work identically
- Module resolution must be transparent
- IDE language server integration must function
- No Buck2-specific code in the Go source

#### Acceptance Criteria

- [ ] Program builds and runs via Buck2
- [ ] Program builds and runs via native Go tooling
- [ ] IDE integration works (auto-completion, go-to-definition)
- [ ] Module cache shared between build systems
- [ ] Output is identical from both build methods

### Phase 5: Documentation and Testing

**Timeline**: 1 week
**Goal**: Complete documentation and comprehensive testing

#### Deliverables

1. **Updated architecture documentation**:
   - Document implemented Go dependency management
   - Include concrete examples and usage patterns
   - Update diagrams to reflect implemented components

2. **Developer guide**:
   - How to add new Go dependencies
   - Troubleshooting common issues
   - Best practices for Go development in the monorepo

3. **Automated testing**:
   - CI/CD integration tests
   - Module resolution verification tests
   - Performance benchmarks for build times

4. **Migration guide**:
   - How to migrate existing Go projects to use centralized dependencies
   - Extracting projects back to standalone modules

#### Technical Requirements

- Clear, actionable documentation
- Automated verification of examples
- Performance regression testing
- Backward compatibility considerations

#### Acceptance Criteria

- [ ] Documentation is complete and accurate
- [ ] All examples work as documented
- [ ] CI/CD pipeline includes Go dependency tests
- [ ] Migration path is clear and tested

## Success Metrics

### Development Experience

- **Single Command Setup**: `nix develop` provides complete Go development environment
- **Build Time Consistency**: Buck2 and native builds have similar performance
- **IDE Integration**: Full language server support without additional configuration
- **Transparent Module Resolution**: Developers don't need to think about the proxy

### Technical Metrics

- **Module Caching**: Shared cache reduces redundant downloads
- **Build Reproducibility**: Identical builds across different environments
- **Dependency Security**: Centralized patching and version management
- **Extraction Simplicity**: Projects easily convertible to standalone modules

### Architecture Validation

- **Non-Contaminating**: Standard Go tooling works without modification
- **Hermetic Builds**: All dependencies explicitly declared and versioned
- **Ecosystem Compatibility**: Projects remain compatible with standard Go ecosystem
- **Vendor Lock-in Avoidance**: No Buck2-specific code required in Go sources

## Risk Mitigation

### Technical Risks

1. **GOPROXY Protocol Compliance**: Thorough testing against Go toolchain versions
2. **Module Resolution Edge Cases**: Comprehensive test suite covering complex dependency graphs
3. **Performance Overhead**: Benchmarking and optimization of proxy implementation
4. **Nix Store Integration**: Proper handling of Nix garbage collection and module lifecycle

### Process Risks

1. **Developer Adoption**: Clear documentation and migration support
2. **CI/CD Integration**: Gradual rollout with fallback mechanisms
3. **Maintenance Burden**: Automation of dependency updates and security patches
4. **Complexity Management**: Keep implementation simple and well-documented

## Future Enhancements

### Advanced Features

- **Private Module Support**: Extension to support internal/private Go modules
- **Multi-Version Support**: Advanced dependency resolution for conflicting versions
- **Build Optimization**: Advanced caching and incremental compilation
- **Security Scanning**: Automated vulnerability scanning of dependencies

### Ecosystem Integration

- **Language Server Protocol**: Enhanced IDE integration with monorepo awareness
- **Testing Framework**: Advanced testing utilities for monorepo Go projects
- **Deployment Tools**: Integration with deployment and packaging systems
- **Monitoring**: Metrics and observability for dependency usage

## Implementation Timeline

```
Week 1-2:  Phase 1 - Nix Dependency Declaration System
Week 3-4:  Phase 2 - GOPROXY Filesystem Layout
Week 5:    Phase 3 - Environment Variable Configuration
Week 6:    Phase 4 - Test Implementation
Week 7:    Phase 5 - Documentation and Testing
```

**Total Duration**: ~6 weeks
**Key Milestones**:
- Week 2: Dependencies managed in Nix
- Week 4: Working GOPROXY filesystem layout
- Week 5: Transparent development environment
- Week 6: End-to-end working example
- Week 7: Production-ready with full documentation

---

This roadmap provides a structured approach to implementing Go dependency management that aligns with our hybrid Nix + Buck2 architecture, maintaining our principles of non-contaminating ecosystem integration and transparent native tooling compatibility.
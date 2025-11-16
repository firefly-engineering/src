# Language: Complete Go Dependency Management Integration

## Overview

Complete the Go dependency management implementation by finishing Phase 3 (environment configuration) and integrating with the toolchain synchronization system.

## Context

According to the Go dependency management roadmap:
- ✅ Phase 1: JSON dependency declaration (COMPLETED)
- ✅ Phase 2: GOPROXY filesystem layout (COMPLETED)
- 🚧 Phase 3: Environment variable configuration (IN PROGRESS)

This task completes Phase 3 and integrates with Buck2 + Nix toolchains.

### Current State

From `docs/src/design/go-dependency-management-roadmap.md`:
- JSON-based dependency declaration works
- GOPROXY filesystem layout generated
- Test case: `golang.org/x/example/hello/reverse` working

### Target State

- GOPROXY environment automatically configured in dev shell
- Buck2 builds work seamlessly with Go dependencies
- Native `go build` and Buck2 builds use same dependency cache
- No manual environment setup required

## Prerequisites

- Phase 0: Toolchain synchronization working
- Go dependency management Phases 1-2 complete
- Understanding of GOPROXY protocol
- Understanding of Go module system

## Success Criteria

- [ ] GOPROXY environment variable automatically set in dev shell
- [ ] Go toolchain finds dependencies via GOPROXY
- [ ] Buck2 builds access same dependencies
- [ ] `go build` and `buck2 build` produce identical binaries
- [ ] Dependency updates work smoothly
- [ ] Documentation updated
- [ ] Example project demonstrates usage

## Implementation Guidance

### 1. Environment Variable Configuration

Update module to set Go environment:

```nix
let
  # Generate GOPROXY filesystem from JSON
  goProxyFS = pkgs.runCommand "go-proxy-fs" {
    buildInputs = [ pkgs.go ];
  } ''
    mkdir -p $out
    # ... (existing GOPROXY generation code)
  '';

  # Shell hook to configure Go
  goEnvHook = ''
    # Configure GOPROXY to use local filesystem
    export GOPROXY="file://$(realpath ${goProxyFS})"
    export GONOSUMDB="*"  # Disable checksum verification for local proxy
    export GOPRIVATE="*"  # Treat all as private (no proxy fallback)

    echo "Go dependency proxy configured:"
    echo "  GOPROXY=$GOPROXY"
  '';
in
{
  devShells.default = pkgs.mkShell {
    packages = [ resolved.go ];

    shellHook = goEnvHook + existingShellHook;
  };
}
```

### 2. Buck2 Integration

Ensure Buck2 builds also use GOPROXY:

```nix
# In Buck2 config generator
let
  buckGoConfig = ''
    [go]
    go_bin = ${resolved.go}/bin/go

    # Set environment for Go builds
    env_vars = GOPROXY=file://${goProxyFS},GONOSUMDB=*,GOPRIVATE=*
  '';
in
```

### 3. Dependency Declaration

Create convenient interface for declaring Go dependencies:

```nix
# go-deps.nix
{
  dependencies = [
    {
      module = "golang.org/x/example";
      version = "v0.0.0-20231031185854-cf748a1e51e0";
      packages = [
        "hello"
        "hello/reverse"
      ];
    }
    {
      module = "github.com/spf13/cobra";
      version = "v1.8.0";
      packages = [ "." ];
    }
  ];
}
```

Convert to JSON for processing:

```nix
let
  goDeps = import ./go-deps.nix;
  goDepsJSON = pkgs.writeText "go-deps.json" (builtins.toJSON goDeps);

  goProxyFS = import ./lib/go-proxy-filesystem.nix {
    inherit pkgs;
    depsFile = goDepsJSON;
  };
in
```

### 4. Dependency Update Workflow

Create helper script for updating dependencies:

```nix
let
  updateGoDeps = pkgs.writeScriptBin "update-go-deps" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Updating Go dependencies..."

    # Read current go.mod
    if [ ! -f go.mod ]; then
      echo "Error: go.mod not found"
      exit 1
    fi

    # Extract dependencies
    go list -m -json all | jq -s '
      map(select(.Main != true)) |
      map({
        module: .Path,
        version: .Version,
        packages: ["."]  # Simplified, could scan for actual packages
      })
    ' > go-deps.json

    echo "Updated go-deps.json"
    echo "Run 'nix develop' to regenerate GOPROXY filesystem"
  '';
in
{
  devShells.default = pkgs.mkShell {
    packages = [ resolved.go updateGoDeps ];
  };
}
```

### 5. Verify Identical Binaries

Test that both build methods produce identical results:

```bash
#!/usr/bin/env bash
# test-go-builds-identical.sh

set -euo pipefail

PROJECT="experimental/go-hello-world"

echo "Testing Go build identity"
echo "========================="

# Build with go build
echo ""
echo "Building with 'go build'..."
cd "$PROJECT"
go build -o app-go
GO_SHA=$(sha256sum app-go | cut -d' ' -f1)
echo "  SHA256: $GO_SHA"

# Build with Buck2
echo ""
echo "Building with 'buck2 build'..."
cd ..
buck2 build "//$PROJECT:app"
cp "buck-out/v2/gen/$PROJECT/app/app" "$PROJECT/app-buck2"
cd "$PROJECT"
BUCK2_SHA=$(sha256sum app-buck2 | cut -d' ' -f1)
echo "  SHA256: $BUCK2_SHA"

# Compare
echo ""
if [ "$GO_SHA" = "$BUCK2_SHA" ]; then
  echo "✅ Builds are IDENTICAL!"
else
  echo "⚠️  Builds differ (may be due to build metadata)"
  echo "   Comparing stripped binaries..."

  strip -o app-go-stripped app-go
  strip -o app-buck2-stripped app-buck2

  GO_STRIPPED_SHA=$(sha256sum app-go-stripped | cut -d' ' -f1)
  BUCK2_STRIPPED_SHA=$(sha256sum app-buck2-stripped | cut -d' ' -f1)

  if [ "$GO_STRIPPED_SHA" = "$BUCK2_STRIPPED_SHA" ]; then
    echo "✅ Stripped builds are identical (metadata differs only)"
  else
    echo "❌ Even stripped builds differ - investigate!"
    exit 1
  fi
fi
```

### 6. Example Project

Create comprehensive example:

```
experimental/go-with-deps/
├── BUCK
├── go.mod
├── go.sum
├── go-deps.nix        # Nix declaration of deps
├── main.go            # Uses external packages
└── README.md
```

`main.go`:

```go
package main

import (
    "fmt"
    "github.com/spf13/cobra"
    "golang.org/x/example/hello/reverse"
)

func main() {
    cmd := &cobra.Command{
        Use: "demo",
        Run: func(cmd *cobra.Command, args []string) {
            fmt.Println(reverse.String("Hello from synchronized dependencies!"))
        },
    }
    cmd.Execute()
}
```

`BUCK`:

```python
go_binary(
    name = "demo",
    srcs = ["main.go"],
    deps = [
        "//ext/go/github.com/spf13/cobra:pkg",
        "//ext/go/golang.org/x/example/hello/reverse:pkg",
    ],
)
```

### 7. Documentation

Update `docs/src/design/go-dependency-management-roadmap.md`:

```markdown
## Phase 3: Environment Variable Configuration ✅

**Status**: COMPLETED

### Implementation

Environment variables automatically configured in dev shell:
- `GOPROXY`: Points to local Nix-generated filesystem
- `GONOSUMDB`: Disables checksum verification for local proxy
- `GOPRIVATE`: Treats all modules as private

### Usage

1. Declare dependencies in `go-deps.nix`
2. Enter shell: `nix develop`
3. Build with either `go build` or `buck2 build`

Both methods use identical dependencies and produce identical binaries.

### Example

See: `experimental/go-with-deps/`
```

## Implementation Steps

1. Implement GOPROXY environment configuration in module
2. Update Buck2 config generation to include Go env vars
3. Create `update-go-deps` helper script
4. Create test for binary identity
5. Build comprehensive example project
6. Test native and Buck2 builds produce identical output
7. Document in roadmap
8. Update user guide with Go dependency management

## Testing

```bash
# Test environment configuration
nix develop --command bash -c "
  echo \$GOPROXY
  # Should show: file://nix/store/.../go-proxy-fs

  go env GOPROXY
  # Should match
"

# Test dependency resolution
cd experimental/go-with-deps
nix develop --command bash -c "
  go build
  ./demo
  # Should work
"

# Test Buck2 build
buck2 build //experimental/go-with-deps:demo
buck2 run //experimental/go-with-deps:demo
# Should work identically

# Test binary identity
./test-go-builds-identical.sh
# Should pass
```

## Related Documentation

- Design: `docs/src/design/go-dependency-management-roadmap.md`
- Architecture: `docs/src/architecture.md`
- Tasks: `TASKS.md`

## Next Steps

After completing this task:
- Apply similar approach to Rust (`lang-rust-implement-cargo-registry.md`)
- Apply to Python
- Apply to TypeScript

## Notes

- **GOPROXY**: Local filesystem proxy is fast and hermetic
- **Checksums**: Disabled for local proxy (Nix provides integrity)
- **Identical binaries**: Goal is reproducibility between build methods
- **Dependency updates**: Helper script makes updates easy
- **Buck2 integration**: Environment vars ensure Buck2 uses same proxy
- **Testing**: Binary comparison validates approach
- **Documentation**: Clear examples critical for adoption

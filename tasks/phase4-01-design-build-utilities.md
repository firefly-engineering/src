# Phase 4.1: Design Build Utilities Integration

## Overview

Design and evaluate integration of build utilities (Gazelle-like for Go, Reindeer-like for Rust) that help generate and maintain Buck2 BUILD files for external dependencies.

## Context

Managing external dependencies in Buck2 requires BUILD files for each dependency. This is tedious to do manually. Tools like Gazelle (for Bazel/Go) and Reindeer (for Rust) automate this process.

### The Problem

```
# Manual approach (painful):
go.mod lists dependency: golang.org/x/sync v0.5.0

# Need to manually create:
ext/go/golang.org/x/sync/BUCK
ext/go/golang.org/x/sync/errgroup/BUCK
ext/go/golang.org/x/sync/semaphore/BUCK
# ... etc

# Each with correct dependencies, sources, visibility
```

### Desired Solution

```bash
# Automated approach:
buck2-go-deps update    # Reads go.mod, generates all BUCK files
buck2-rust-deps update  # Reads Cargo.toml, generates all BUCK files
```

## Prerequisites

- Phase 0: Toolchain synchronization working
- Understanding of language dependency management
- Familiarity with existing tools (Gazelle, Reindeer)
- Understanding of Buck2 external cells

## Success Criteria

- [ ] Evaluation of existing tools (Gazelle, Reindeer, etc.)
- [ ] Design for tool integration with Nix
- [ ] Proof-of-concept for at least one language
- [ ] Documentation of approach and tradeoffs
- [ ] Decision on whether to build custom tools or adapt existing
- [ ] Integration plan with toolchain module

## Implementation Guidance

### 1. Evaluate Existing Tools

**For Go**:

**Option A: Gazelle** (Bazel tool)
- **Pros**: Mature, widely used, active development
- **Cons**: Designed for Bazel, not Buck2
- **Adaptation**: Would need Buck2 backend

**Option B: Custom Go Tool**
- **Pros**: Tailored to Buck2, can integrate with our setup
- **Cons**: Development and maintenance burden
- **Complexity**: Medium (parse go.mod, generate BUCK files)

**For Rust**:

**Option A: Reindeer** (Meta's tool)
- **Pros**: Designed for Buck2, Meta maintains it
- **Cons**: May not integrate well with Nix
- **Status**: Check current state and compatibility

**Option B: Custom Rust Tool**
- **Pros**: Full control over integration
- **Cons**: Cargo.lock parsing is complex
- **Complexity**: High (Cargo.lock format, dependency resolution)

**For Python**:

**Option A: Custom Python Tool**
- **Complexity**: Medium (parse requirements.txt or pyproject.toml)
- **Generate**: BUCK files for each package

### 2. Design: External Cell Structure

Proposed structure for generated dependencies:

```
ext/
├── BUCK                 # Root cell file
├── go/
│   ├── BUCK            # Generated
│   └── golang.org/
│       └── x/
│           └── sync/
│               ├── BUCK         # Generated
│               └── errgroup/
│                   └── BUCK     # Generated
├── rust/
│   ├── BUCK            # Generated
│   ├── serde/
│   │   └── BUCK        # Generated
│   └── tokio/
│       └── BUCK        # Generated
└── python/
    ├── BUCK
    └── fastapi/
        └── BUCK        # Generated
```

### 3. Design: Tool Architecture

```
┌─────────────┐
│  go.mod     │
│  Cargo.toml │
│  pyproject  │
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│ Dependency      │
│ Resolver        │
│ (Nix-based)     │
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│ BUCK File       │
│ Generator       │
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│ ext/*/BUCK      │
│ (Generated)     │
└─────────────────┘
```

### 4. Design: Nix Integration

**Key Insight**: Use Nix for dependency resolution, then generate BUCK files:

```nix
# In Nix module:
let
  # Parse Go dependencies
  goDeps = builtins.fromJSON (builtins.readFile ./go-deps.json);

  # Resolve each dependency to Nix derivation
  resolvedGoDeps = lib.mapAttrs (name: version:
    fetchgo {
      inherit name version;
      # ... Nix fetches and unpacks
    }
  ) goDeps;

  # Generate BUCK files
  generateBuckFiles = pkgs.writeScript "generate-go-buck" ''
    ${pkgs.python3}/bin/python ${./buck-gen.py} \
      --deps ${builtins.toJSON resolvedGoDeps} \
      --output ext/go/
  '';
in
```

### 5. Proof of Concept: Go Dependency Generator

Create minimal PoC:

```python
#!/usr/bin/env python3
"""
buck-go-deps - Generate Buck2 BUILD files for Go dependencies

Usage:
    buck-go-deps update
    buck-go-deps add golang.org/x/sync@v0.5.0
"""

import json
import subprocess
import sys
from pathlib import Path

def parse_go_mod():
    """Parse go.mod and return list of dependencies."""
    result = subprocess.run(
        ["go", "list", "-m", "-json", "all"],
        capture_output=True,
        text=True
    )

    deps = []
    for line in result.stdout.strip().split('\n'):
        if line:
            dep = json.loads(line)
            if 'Indirect' not in dep:  # Only direct dependencies
                deps.append({
                    'path': dep['Path'],
                    'version': dep['Version']
                })

    return deps

def generate_buck_file(dep, output_dir):
    """Generate BUCK file for a Go dependency."""
    # Simplified - real implementation would:
    # 1. Fetch dependency source
    # 2. Parse Go packages
    # 3. Identify dependencies between packages
    # 4. Generate BUCK file with correct deps

    pkg_path = Path(output_dir) / dep['path'].replace('/', os.sep)
    pkg_path.mkdir(parents=True, exist_ok=True)

    buck_content = f"""
# Generated by buck-go-deps
# Package: {dep['path']}
# Version: {dep['version']}

load("@prelude//go:go.bzl", "go_library")

go_library(
    name = "pkg",
    srcs = glob(["*.go"]),
    visibility = ["PUBLIC"],
)
"""

    (pkg_path / "BUCK").write_text(buck_content)
    print(f"Generated BUCK for {dep['path']}")

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    command = sys.argv[1]

    if command == "update":
        deps = parse_go_mod()
        for dep in deps:
            generate_buck_file(dep, "ext/go")
        print(f"Generated BUCK files for {len(deps)} dependencies")

    elif command == "add":
        # Add specific dependency
        pass

if __name__ == "__main__":
    main()
```

Package as Nix derivation:

```nix
let
  buckGoDeps = pkgs.writeScriptBin "buck-go-deps" ''
    #!${pkgs.python3}/bin/python3
    ${builtins.readFile ./buck-go-deps.py}
  '';
in
{
  devShells.default = pkgs.mkShell {
    packages = toolchainPackages ++ [ buckGoDeps ];
  };
}
```

### 6. Design: Dependency Workflow

**Initial setup**:

```bash
# 1. Developer adds dependency normally
go get golang.org/x/sync

# 2. Generate BUCK files
buck-go-deps update

# 3. Use in BUCK files
# my-project/BUCK:
go_binary(
    name = "app",
    deps = [
        "//ext/go/golang.org/x/sync:pkg",
    ],
)
```

**Updating dependencies**:

```bash
# 1. Update go.mod
go get -u golang.org/x/sync

# 2. Regenerate BUCK files
buck-go-deps update

# 3. Rebuild
buck2 build //...
```

### 7. Alternative Approach: Hybrid (Go-specific)

Use existing GOPROXY implementation (from Go dependency management roadmap):

```
Instead of generating BUCK files for each dependency:
1. Use GOPROXY to serve dependencies
2. Go toolchain handles dependency resolution
3. Buck2 just invokes `go build` with correct env

Tradeoff: Less Buck2 cache granularity, but simpler
```

### 8. Evaluation Criteria

Compare approaches:

| Criterion | Custom Tool | Adapt Gazelle | Use GOPROXY |
|-----------|-------------|---------------|-------------|
| Development effort | High | Medium | Low |
| Buck2 cache granularity | High | High | Low |
| Maintenance | High | Medium | Low |
| Nix integration | Easy | Hard | Easy |
| Community support | None | High | Medium |

### 9. Decision Framework

Ask these questions:

1. **How many external dependencies** do we typically have?
   - Few (<10): Manual BUCK files acceptable
   - Many (>50): Automation essential

2. **How often do dependencies update**?
   - Rarely: One-time generation acceptable
   - Frequently: Need robust automation

3. **Do we need fine-grained caching**?
   - Yes: Generate BUCK files per package
   - No: Invoke language tools directly

4. **Development resources available**?
   - Limited: Use existing tools or GOPROXY approach
   - Available: Build custom integration

## Implementation Steps

1. Research existing tools (Gazelle, Reindeer, etc.)
2. Create evaluation matrix
3. Build proof-of-concept for Go
4. Test PoC with real dependencies
5. Evaluate maintenance burden
6. Make recommendation
7. Document decision and rationale
8. Create implementation plan if building custom tools

## Testing

```bash
# Test PoC
cd test-project/
echo "module test" > go.mod
go get golang.org/x/sync@v0.5.0

buck-go-deps update

# Should create:
# ext/go/golang.org/x/sync/BUCK

# Test build
buck2 build //ext/go/golang.org/x/sync:pkg

# Test usage
# Create app that depends on it
buck2 build //my-app:app
```

## Related Documentation

- Design: `docs/src/design/ext-cell-dependency-management.md`
- Design: `docs/src/design/go-dependency-management-roadmap.md`
- Tasks: `TASKS.md` (Phase 4)
- Gazelle: https://github.com/bazelbuild/bazel-gazelle
- Reindeer: https://github.com/facebookincubator/reindeer

## Next Steps

After completing this task:
- Implement chosen approach (if custom tool)
- Or integrate existing tool (if adapting)
- Or document GOPROXY workflow (if hybrid approach)
- Phase 5: Advanced registry features

## Notes

- **Don't over-engineer**: Start simple, add complexity as needed
- **Learn from existing**: Gazelle and Reindeer are well-designed
- **Consider maintenance**: Custom tools need ongoing maintenance
- **User experience**: Tools should be easy to use
- **Integration**: Should work seamlessly with Nix and Buck2
- **Documentation**: Clear usage documentation critical
- **Incremental**: Can start with one language, add others later
- **Community**: Consider contributing improvements to existing tools

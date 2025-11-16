# Phase 1.3: Test Downstream Repository Usage

## Overview

Create a test downstream repository that imports and uses the toolchain module. This validates that the module works as advertised when used by external repositories.

## Context

The module is designed to be **imported and used by other repositories**. We need to test this integration to ensure:

1. Import mechanism works correctly
2. Module API is usable
3. Documentation is accurate
4. Common use cases work
5. Custom configurations work

This test simulates what real users will do in Phase 8+ (after extraction to standalone repo).

## Prerequisites

- Phase 0: Complete module implementation
- Phase 1.1: Error handling implemented
- Phase 1.2: Validation tools created
- Module exported correctly in flake.nix

## Success Criteria

- [ ] Test repo successfully imports module
- [ ] Test repo can use default registry
- [ ] Test repo can use custom registry
- [ ] Test repo can extend default registry
- [ ] Shell and Buck2 both work in test repo
- [ ] Verification tools work in test repo
- [ ] Documentation matches reality

## Implementation Guidance

### 1. Create Test Repository

Create separate directory outside main repo:

```bash
# Outside the main repository
mkdir -p /tmp/test-toolchain-module
cd /tmp/test-toolchain-module
git init
```

### 2. Test Case 1: Minimal Setup with Default Registry

Create `flake.nix`:

```nix
{
  description = "Test downstream repository";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Import from local path during development
    # After Phase 8, this would be:
    # firefly-toolchains.url = "github:firefly-engineering/src";
    firefly-toolchains.url = "path:/Users/yann/src/github.com/firefly-engineering/src";
  };

  outputs = { self, nixpkgs, firefly-toolchains }:
    let
      system = "x86_64-linux";  # or your system
      pkgs = import nixpkgs { inherit system; };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        imports = [ firefly-toolchains.flakeModules.toolchains ];

        # Use defaults - should work out of the box
      };
    };
}
```

Create `toolchain.toml`:

```toml
[go]
version = "1.21.5"
```

Create `.buckconfig`:

```ini
[buildfile]
name = BUCK

<file:.buckconfig.toolchains>
```

Test:

```bash
nix develop

# Should see version banner
# Should have go available
which go
go version

# Should generate Buck2 configs
ls -la .buckconfig.toolchains
ls -la toolchains/

# Verify synchronization
verify-toolchains
# Should pass ✅
```

### 3. Test Case 2: Custom Registry

Create custom registry (`custom-registry.nix`):

```nix
{ pkgs }:
{
  go = {
    "1.21.5" = pkgs.go_1_21;
    "1.22.0" = pkgs.go_1_22;
    "custom" = pkgs.go_1_22.overrideAttrs (old: {
      # Custom Go with patches
      pname = "go-custom";
    });
  };

  rust = {
    "1.75.0" = pkgs.rustc;
  };
}
```

Update `flake.nix`:

```nix
{
  devShells.${system}.default = pkgs.mkShell {
    imports = [ firefly-toolchains.flakeModules.toolchains ];

    firefly.toolchains = {
      registry = ./custom-registry.nix;
    };
  };
}
```

Update `toolchain.toml`:

```toml
[go]
version = "custom"

[rust]
version = "1.75.0"
```

Test:

```bash
nix develop
verify-toolchains
```

### 4. Test Case 3: Extend Default Registry

Create registry extension (`registry-additions.nix`):

```nix
{ pkgs, defaultRegistry }:

pkgs.lib.recursiveUpdate defaultRegistry {
  # Add new version to existing toolchain
  go."1.23.0" = pkgs.go_1_23;

  # Add completely new toolchain
  nodejs = {
    "20" = pkgs.nodejs_20;
    "21" = pkgs.nodejs_21;
  };
}
```

Update `flake.nix`:

```nix
{
  devShells.${system}.default = pkgs.mkShell {
    imports = [ firefly-toolchains.flakeModules.toolchains ];

    firefly.toolchains = {
      registry = import ./registry-additions.nix {
        inherit pkgs;
        defaultRegistry = firefly-toolchains.defaultRegistry;
      };
    };
  };
}
```

### 5. Test Case 4: Multiple Toolchains

Create comprehensive `toolchain.toml`:

```toml
[go]
version = "1.21.5"

[rust]
version = "1.75.0"

[python]
version = "3.12"

[clang]
version = "17"
```

Test all toolchains:

```bash
nix develop

go version
rustc --version
python --version
clang --version

verify-toolchains
# Should verify all 4 toolchains
```

### 6. Test Case 5: Configuration Options

Test all module options:

```nix
{
  devShells.${system}.default = pkgs.mkShell {
    imports = [ firefly-toolchains.flakeModules.toolchains ];

    firefly.toolchains = {
      declarationFile = ./config/toolchains.toml;

      buck2 = {
        enable = true;
        autoGenerate = true;
      };

      shell = {
        showVersions = true;
        autoVerify = false;
      };
    };
  };
}
```

### 7. Test Case 6: Error Scenarios

Test error handling in downstream context:

```bash
# Test 1: Missing toolchain.toml
rm toolchain.toml
nix develop
# Should show helpful error

# Test 2: Unknown version
echo '[go]\nversion = "999.999"' > toolchain.toml
nix develop
# Should list available versions

# Test 3: Unknown toolchain
echo '[nonexistent]\nversion = "1.0"' > toolchain.toml
nix develop
# Should list available toolchains
```

### 8. Test Case 7: Real Build

Create actual buildable project:

```
test-repo/
├── flake.nix
├── toolchain.toml
├── .buckconfig
├── hello/
│   ├── BUCK
│   └── main.go
```

`hello/main.go`:

```go
package main

import "fmt"

func main() {
    fmt.Println("Hello from synchronized toolchains!")
}
```

`hello/BUCK`:

```python
go_binary(
    name = "hello",
    srcs = ["main.go"],
)
```

Test native build:

```bash
cd hello
go build
./hello
```

Test Buck2 build:

```bash
buck2 build //hello:hello
buck2 run //hello:hello
```

Both should use same Go binary and work identically.

### 9. Validation Checklist

For each test case, verify:

- [ ] `nix flake check` passes
- [ ] `nix develop` enters shell successfully
- [ ] Toolchains available in shell (`which <tool>`)
- [ ] Buck2 configs generated correctly
- [ ] `verify-toolchains` passes
- [ ] `buck2 build` works
- [ ] Error messages are helpful
- [ ] Documentation examples work

## Implementation Steps

1. Create test repository directory
2. Implement Test Case 1 (minimal setup)
3. Implement Test Case 2 (custom registry)
4. Implement Test Case 3 (extend registry)
5. Implement Test Case 4 (multiple toolchains)
6. Implement Test Case 5 (all options)
7. Implement Test Case 6 (error scenarios)
8. Implement Test Case 7 (real build)
9. Document any issues found
10. Fix issues in main module
11. Re-test all cases

## Testing

Automated test script:

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_PATH="/path/to/firefly-engineering/src"
TEST_DIR="/tmp/test-toolchain-$(date +%s)"

echo "Creating test repository at $TEST_DIR"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# Test Case 1: Minimal
echo "Test 1: Minimal setup..."
cat > flake.nix <<EOF
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.firefly-toolchains.url = "path:$REPO_PATH";
  outputs = { nixpkgs, firefly-toolchains, ... }: {
    devShells.x86_64-linux.default = (import nixpkgs { system = "x86_64-linux"; }).mkShell {
      imports = [ firefly-toolchains.flakeModules.toolchains ];
    };
  };
}
EOF

cat > toolchain.toml <<EOF
[go]
version = "1.21.5"
EOF

nix develop --command bash -c "verify-toolchains"

echo "✅ All tests passed!"
```

## Related Documentation

- Design: `docs/src/design/toolchain-synchronization.md`
- User Guide: `docs/src/user-guide/getting-started.md`
- Tasks: `TASKS.md` (Phase 1.3)

## Next Steps

After completing this task:
- Phase 1.4: Polish documentation based on findings (`phase1-04-polish-documentation.md`)
- Phase 2: Buck2 caching validation

## Notes

- **Fresh perspective**: Testing from outside helps catch assumptions
- **Documentation validation**: This tests whether docs are accurate
- **User experience**: Simulates real user workflow
- **Edge cases**: Uncovers corner cases not obvious from inside
- **Breaking changes**: Helps identify API that should not change
- **Examples**: Test cases can become documentation examples
- **Automation**: Consider making this part of CI
- **Multiple systems**: Test on Linux and macOS if possible

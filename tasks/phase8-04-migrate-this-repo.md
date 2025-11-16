# Phase 8.4: Migrate This Repository to Use Extracted Modules

## Overview

Convert this repository from hosting the toolchain module to being a downstream consumer of the extracted `turnkey` and `toolchain-registry` repositories.

## Context

After extraction:
- `turnkey`: Core mechanism (Phase 8.2)
- `toolchain-registry`: Version catalog (Phase 8.3)
- **This repo**: Reference implementation and example

This repository demonstrates how to use the extracted solution and may provide Firefly-specific customizations.

### Migration Goals

1. Remove module code (now in turnkey)
2. Remove default registry (now in toolchain-registry)
3. Import turnkey and toolchain-registry as flake inputs
4. Verify everything still works
5. Update documentation
6. Become reference implementation

## Prerequisites

- Phase 8.2: Turnkey repository created and tested
- Phase 8.3: Toolchain registry created and tested
- Both repos published (at least to GitHub)
- Migration plan from Phase 8.1

## Success Criteria

- [ ] `flake.nix` imports turnkey and toolchain-registry
- [ ] All local module code removed
- [ ] `toolchain.toml` works with external modules
- [ ] All builds still work
- [ ] All tests still pass
- [ ] Verification scripts still work
- [ ] Documentation updated to reflect new structure
- [ ] Example projects updated
- [ ] No functionality loss
- [ ] Clear before/after comparison

## Implementation Guidance

### 1. Create Migration Branch

```bash
# Create branch for migration
git checkout -b migrate-to-external-modules

# Tag current state for rollback if needed
git tag pre-migration
```

### 2. Update flake.nix

**Before**:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    devShells.x86_64-linux.default =
      let
        pkgs = import nixpkgs { system = "x86_64-linux"; };
      in
      pkgs.mkShell {
        imports = [ ./nix/modules/toolchains ];

        firefly.toolchains = {
          # registry uses default from local module
        };
      };
  };
}
```

**After**:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Add external modules
    turnkey.url = "github:firefly-engineering/turnkey";
    toolchain-registry.url = "github:firefly-engineering/toolchain-registry";

    # Ensure compatible versions
    turnkey.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, turnkey, toolchain-registry }: {
    devShells.x86_64-linux.default =
      let
        pkgs = import nixpkgs { system = "x86_64-linux"; };
      in
      pkgs.mkShell {
        imports = [ turnkey.flakeModules.default ];

        turnkey.toolchains = {
          registry = toolchain-registry.registry;
        };
      };
  };
}
```

### 3. Update flake.lock

```bash
# Update inputs
nix flake update

# Verify inputs
nix flake metadata
# Should show:
# - turnkey: github:firefly-engineering/turnkey
# - toolchain-registry: github:firefly-engineering/toolchain-registry
```

### 4. Remove Local Module Code

```bash
# Archive the old module code (don't delete immediately)
mkdir -p .archive/nix-modules
mv nix/modules/toolchains .archive/nix-modules/

# Update .gitignore if needed
echo ".archive/" >> .gitignore
```

### 5. Verify toolchain.toml Works

Test existing `toolchain.toml`:

```bash
# Current toolchain.toml should work without changes
cat toolchain.toml
# [go]
# version = "1.21.5"

# Enter shell
nix develop

# Verify synchronization
verify-toolchains
# Should show ✅ for all toolchains

# Verify paths
which go
# Should be Nix store path

buck2 audit config go.go_bin
# Should match `which go`
```

### 6. Test All Functionality

Comprehensive testing:

```bash
#!/usr/bin/env bash
# test-migration.sh

set -euo pipefail

echo "Testing Migration to External Modules"
echo "======================================"

# Test 1: Shell environment
echo ""
echo "Test 1: Shell environment"
nix develop --command bash -c "
  echo 'Go: '$(go version)
  echo 'Rust: '$(rustc --version)
  which go
"

# Test 2: Verification
echo ""
echo "Test 2: Toolchain synchronization"
nix develop --command verify-toolchains

# Test 3: Buck2 config generation
echo ""
echo "Test 3: Buck2 configs"
nix develop --command bash -c "
  generate-buck2-configs
  cat .buckconfig.toolchains
"

# Test 4: Builds
echo ""
echo "Test 4: Build projects"
nix develop --command bash -c "
  buck2 build //experimental/go-hello-world:...
  buck2 build //experimental/rs-hello-world:...
"

# Test 5: Tests
echo ""
echo "Test 5: Run tests"
nix develop --command bash -c "
  buck2 test //experimental/go-hello-world:...
  buck2 test //experimental/rs-hello-world:...
"

# Test 6: Compare with pre-migration
echo ""
echo "Test 6: Compare toolchain paths"
echo "Pre-migration Go: $(git show pre-migration:toolchain-paths.txt | grep go)"
echo "Post-migration Go: $(nix develop --command which go)"

echo ""
echo "✅ All tests passed!"
```

### 7. Update Documentation

Update all references to module location:

**`README.md`** changes:

```markdown
# Before:
This repository includes a toolchain synchronization module...

# After:
This repository demonstrates using the [Turnkey](https://github.com/firefly-engineering/turnkey)
toolchain synchronization system with Buck2.

See the extracted modules:
- [Turnkey](https://github.com/firefly-engineering/turnkey) - Core mechanism
- [Toolchain Registry](https://github.com/firefly-engineering/toolchain-registry) - Version catalog
```

**`docs/src/architecture.md`** updates:

```markdown
## Toolchain Synchronization

The toolchain synchronization is provided by [Turnkey](https://github.com/firefly-engineering/turnkey),
which ensures development shell and Buck2 use identical toolchain binaries.

[Link to Turnkey documentation](https://turnkey.dev/docs)
```

### 8. Update Example Projects

If examples reference local module:

```nix
# Before:
imports = [ ../../nix/modules/toolchains ];

# After:
# Add to flake inputs first
turnkey.url = "github:firefly-engineering/turnkey";

# Then import:
imports = [ turnkey.flakeModules.default ];
```

### 9. Optional: Add Custom Registry Extensions

If Firefly needs custom toolchains:

```nix
# custom-toolchains.nix
{ pkgs }:

{
  # Firefly-specific custom toolchains
  go = {
    "1.21.5-firefly" = pkgs.go_1_21.overrideAttrs (old: {
      # Firefly-specific patches or config
    });
  };
}
```

Use in `flake.nix`:

```nix
{
  turnkey.toolchains = {
    registry = toolchain-registry.lib.extendRegistry
      toolchain-registry.registry
      (import ./custom-toolchains.nix);
  };
}
```

### 10. Create Migration Documentation

`docs/migration-guide.md`:

```markdown
# Migration to External Modules

This repository has migrated from hosting the toolchain synchronization module
to using the extracted [Turnkey](https://github.com/firefly-engineering/turnkey)
and [Toolchain Registry](https://github.com/firefly-engineering/toolchain-registry) modules.

## What Changed

**Before** (commit: pre-migration):
- Module code in `nix/modules/toolchains/`
- Registry in `nix/modules/toolchains/registry-default.nix`
- Self-contained

**After** (current):
- Module from `github:firefly-engineering/turnkey`
- Registry from `github:firefly-engineering/toolchain-registry`
- Reference implementation

## For Users

### If you forked this repository

Update your `flake.nix`:

```nix
{
  inputs = {
    turnkey.url = "github:firefly-engineering/turnkey";
    toolchain-registry.url = "github:firefly-engineering/toolchain-registry";
  };
}
```

Your `toolchain.toml` continues to work without changes.

### If you imported the local module

Replace:

```nix
imports = [ firefly-src.modules.toolchains ];
```

With:

```nix
imports = [ turnkey.flakeModules.default ];
turnkey.toolchains.registry = toolchain-registry.registry;
```

## Benefits

- ✅ Get updates to turnkey independently
- ✅ Get new toolchain versions independently
- ✅ Use with your own registry
- ✅ Community-maintained modules
- ✅ Better documentation and support
```

### 11. Update CI/CD

Ensure CI works with external modules:

```yaml
# .github/workflows/build.yml
- name: Verify external modules work
  run: |
    nix flake show  # Should show turnkey and toolchain-registry as inputs

    nix develop --command bash -c "
      verify-toolchains
      buck2 build //...
    "
```

### 12. Create Comparison Report

Document what changed:

```bash
#!/usr/bin/env bash
# generate-migration-report.sh

cat > MIGRATION_REPORT.md <<'EOF'
# Migration Report

## Changes

### Removed
- `nix/modules/toolchains/` (moved to turnkey repo)
- Local registry (moved to toolchain-registry repo)

### Added
- Flake input: `turnkey`
- Flake input: `toolchain-registry`

### Modified
- `flake.nix`: Imports from external modules
- Documentation: Updated links and references

### Unchanged
- `toolchain.toml`: No changes required
- Build configuration: Works identically
- Example projects: Work identically (after update)

## Verification

| Test | Pre-Migration | Post-Migration | Status |
|------|---------------|----------------|--------|
| Shell entry | ✅ | ✅ | Pass |
| Toolchain sync | ✅ | ✅ | Pass |
| Buck2 builds | ✅ | ✅ | Pass |
| Go path | /nix/store/abc-go | /nix/store/abc-go | Same |
| Rust path | /nix/store/xyz-rust | /nix/store/xyz-rust | Same |

## Performance

| Metric | Pre-Migration | Post-Migration |
|--------|---------------|----------------|
| Shell entry time | 2.3s | 2.4s |
| Build time | 45s | 45s |
| Flake evaluation | 0.8s | 1.1s |

Slight increase in flake evaluation due to additional inputs, but negligible.

## Recommendations

✅ Merge migration - all tests passing
✅ Update documentation - completed
✅ Archive old code - completed
EOF
```

## Implementation Steps

1. Create migration branch
2. Update `flake.nix` with new inputs
3. Run `nix flake update`
4. Archive local module code
5. Test shell environment
6. Test verification scripts
7. Test builds and tests
8. Update all documentation
9. Update example projects
10. Create migration guide
11. Update CI/CD
12. Generate comparison report
13. Review and merge

## Testing

```bash
# Full migration test
./test-migration.sh

# Compare with pre-migration
git checkout pre-migration
nix develop --command which go > /tmp/pre-go-path

git checkout migrate-to-external-modules
nix develop --command which go > /tmp/post-go-path

diff /tmp/pre-go-path /tmp/post-go-path
# Should be identical or very similar

# Performance comparison
time nix develop --command true  # After migration
git checkout pre-migration
time nix develop --command true  # Before migration
```

## Related Documentation

- Tasks: `TASKS.md` (Phase 8.4)
- Phase 8.2: Turnkey repository
- Phase 8.3: Toolchain registry

## Next Steps

After completing this task:
- Phase 8.5: Publish repositories (`phase8-05-publish-repositories.md`)
- Monitor for issues
- Gather feedback from team

## Notes

- **No functionality loss**: Everything should work identically
- **Rollback plan**: Tagged pre-migration state for easy rollback
- **Testing**: Comprehensive testing critical
- **Documentation**: Update all references
- **Communication**: Inform team before merging
- **Gradual**: Can test in branch before merging
- **Benefits**: Access to community updates and improvements
- **Reference**: This repo becomes reference implementation

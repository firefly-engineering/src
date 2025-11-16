# Phase 8.1: Prepare for Repository Extraction

## Overview

Audit the current implementation and prepare for extracting the toolchain synchronization solution into two standalone repositories: `turnkey` (core mechanism) and `toolchain-registry` (version catalog).

## Context

After Phases 0-7, the solution is mature and battle-tested. Phase 8 extracts it into standalone, reusable repositories that the community can use.

### The Split Architecture

**Current State** (single repo):
```
firefly-engineering/src/
├── nix/modules/toolchains/
│   ├── default.nix          # Module code
│   ├── registry-default.nix # Version catalog
│   └── patches/             # Toolchain patches
└── [rest of Firefly code]
```

**Target State** (three repos):

1. **`firefly-engineering/turnkey`** (mechanism):
   ```
   ├── flake.nix
   ├── modules/
   │   └── default.nix      # Core resolution logic
   ├── lib/
   │   ├── registry.nix     # Registry interface/API
   │   └── generators.nix   # Shell & Buck2 generators
   └── docs/
   ```

2. **`firefly-engineering/toolchain-registry`** (data):
   ```
   ├── flake.nix
   ├── registry.nix         # Main export
   ├── go/
   │   ├── versions.nix
   │   └── patches/
   ├── rust/
   │   ├── versions.nix
   │   └── patches/
   └── docs/
   ```

3. **`firefly-engineering/src`** (downstream consumer):
   ```
   ├── flake.nix
   │   inputs.turnkey = ...
   │   inputs.toolchain-registry = ...
   ├── toolchain.toml      # Local configuration
   └── [rest of code]
   ```

## Prerequisites

- Phases 0-7: Complete implementation
- Module battle-tested in production
- Good understanding of what should/shouldn't be in each repo
- Documentation complete

## Success Criteria

- [ ] Complete audit of current implementation
- [ ] Clear mapping: code → which repository
- [ ] All dependencies identified and documented
- [ ] Versioning strategy defined for both repos
- [ ] Migration plan documented
- [ ] Breaking changes identified
- [ ] Communication plan for transition

## Implementation Guidance

### 1. Audit Current Implementation

Create comprehensive inventory:

```bash
#!/usr/bin/env bash
# audit-implementation.sh

echo "Current Implementation Audit"
echo "============================"
echo ""

echo "Module Code (→ turnkey):"
find nix/modules/toolchains -name "*.nix" ! -name "registry-default.nix" -type f | while read f; do
  LINES=$(wc -l < "$f")
  echo "  $f ($LINES lines)"
done

echo ""
echo "Registry Code (→ toolchain-registry):"
find nix/modules/toolchains -name "registry-default.nix" -o -path "*/patches/*" | while read f; do
  echo "  $f"
done

echo ""
echo "Documentation (split between both):"
find docs -name "*.md" | grep -E "(toolchain|registry)" | while read f; do
  echo "  $f"
done

echo ""
echo "Scripts and Tools:"
find . -name "*toolchain*" -o -name "*buck2*" | grep -E "\.(sh|py)$"
```

### 2. Create Dependency Map

Document dependencies between components:

```markdown
# Dependency Analysis

## Turnkey Dependencies

**Nix dependencies**:
- nixpkgs (for lib functions)
- No other dependencies

**Internal dependencies**:
- Registry interface (must be stable)
- None (self-contained)

## Toolchain Registry Dependencies

**Nix dependencies**:
- nixpkgs (for actual toolchain packages)
- Turnkey (for lib.extendRegistry helper - optional)

**External dependencies**:
- None (just data)

## This Repository Dependencies (After Extraction)

**Flake inputs**:
- nixpkgs
- turnkey (from GitHub)
- toolchain-registry (from GitHub)

**Internal**:
- toolchain.toml (local)
```

### 3. Define Repository Boundaries

**What Goes in `turnkey`** (mechanism):
```
✅ Module definition (default.nix)
✅ Resolution logic
✅ Shell generation logic
✅ Buck2 config generation logic
✅ Registry interface/API definition
✅ Validation scripts (verify-toolchains, etc.)
✅ Core documentation
✅ Examples of custom registries

❌ Specific toolchain versions
❌ Toolchain patches
❌ Firefly-specific code
```

**What Goes in `toolchain-registry`** (data):
```
✅ Default registry with common versions
✅ Toolchain patches (security, bugs)
✅ Version metadata
✅ Registry documentation
✅ Contribution guidelines
✅ Versioning policy

❌ Resolution logic
❌ Code generation
❌ Module definition
```

**What Stays in `firefly-engineering/src`**:
```
✅ toolchain.toml (local config)
✅ Custom registry extensions (if any)
✅ Firefly-specific code
✅ Example/reference usage

❌ Shared module code
❌ Shared registry
```

### 4. Define Registry Interface (API Contract)

This is the contract between turnkey and registries:

```nix
# Registry Interface v1.0
#
# A registry MUST be a function: { pkgs }: attrset
# The attrset MUST have this structure:
#
# {
#   <toolchain-name> = {
#     "<version-string>" = <nixpkgs-derivation>;
#   };
# }
#
# Example:
# { pkgs }: {
#   go = {
#     "1.21.5" = pkgs.go_1_21;
#   };
# }
#
# Optional extensions:
# - Metadata (for documentation)
# - Patches (via .overrideAttrs)
# - Build-from-source options
#
# Turnkey promises:
# - Will call registry with { pkgs }
# - Will look up toolchains by name
# - Will look up versions by string key
# - Will handle missing gracefully (error message)
#
# Version: 1.0.0
# Stability: Stable (won't break in minor versions)
```

### 5. Plan Versioning Strategy

**Turnkey versioning**:
- Semantic versioning: MAJOR.MINOR.PATCH
- MAJOR: Breaking changes to registry interface
- MINOR: New features (new options, etc.)
- PATCH: Bug fixes

**Toolchain Registry versioning**:
- Date-based or semantic
- Format: YYYY-MM or semantic
- Adding versions: MINOR bump
- Removing versions: MAJOR bump (breaking)
- Patches: PATCH bump

**Lock-step or independent**:
- Decision: **Independent**
- Turnkey v1.x works with any registry v1.x
- Turnkey v2.x may require registry v2.x (if interface changes)

### 6. Identify Breaking Changes

**Potential breaking changes**:

1. **Module options rename**:
   ```nix
   # Before (local):
   firefly.toolchains.registry = ...

   # After (extracted):
   turnkey.toolchains.registry = ...
   # OR keep firefly namespace? Decision needed.
   ```

2. **Registry location**:
   ```nix
   # Before:
   registry = ./nix/modules/toolchains/registry-default.nix

   # After:
   registry = toolchain-registry.registry
   ```

3. **Import mechanism**:
   ```nix
   # Before:
   imports = [ ./nix/modules/toolchains ];

   # After:
   imports = [ turnkey.flakeModules.default ];
   ```

**Migration guide needed** for all changes.

### 7. Plan Communication

**Announcement Plan**:

1. **Internal team** (2 weeks before):
   - Email explaining changes
   - Migration guide
   - Q&A session

2. **Public announcement** (at launch):
   - Blog post explaining architecture
   - Show before/after
   - Migration guide
   - Examples

3. **Community outreach**:
   - Post to Nix Discourse
   - Post to Buck2 community
   - GitHub releases
   - Documentation site

### 8. Create Migration Checklist

**Pre-extraction**:
- [ ] All tests passing
- [ ] Documentation complete
- [ ] Example projects working
- [ ] CI/CD working
- [ ] Security review done
- [ ] Performance acceptable

**During extraction**:
- [ ] Create new repositories
- [ ] Move code
- [ ] Update imports
- [ ] Test each repo independently
- [ ] Create examples
- [ ] Write migration guide

**Post-extraction**:
- [ ] Update this repo to use extracted repos
- [ ] Verify everything works
- [ ] Announce publicly
- [ ] Monitor for issues

### 9. Document Current State

Create snapshot of working system:

```bash
# Create snapshot for comparison
git tag pre-extraction-snapshot
git archive --format=tar.gz --prefix=pre-extraction/ HEAD > pre-extraction.tar.gz

# Document versions
nix flake show > pre-extraction-flake-structure.txt
tree nix/ > pre-extraction-nix-tree.txt

# Test and capture results
nix develop --command verify-toolchains > pre-extraction-verification.txt
```

### 10. Risk Assessment

**Risks**:

| Risk | Impact | Likelihood | Mitigation |
|------|---------|-----------|------------|
| Breaking existing users | High | High | Migration guide, deprecation period |
| Module incompatibility | High | Medium | Extensive testing, CI |
| Registry version mismatch | Medium | Low | Clear versioning, warnings |
| Documentation gaps | Medium | Medium | Thorough review, user testing |
| Community adoption low | Low | Medium | Good examples, advocacy |

## Implementation Steps

1. Run comprehensive audit of current implementation
2. Create dependency map
3. Define clear repository boundaries
4. Document registry interface/API
5. Plan versioning strategy
6. Identify all breaking changes
7. Write migration guide (draft)
8. Create communication plan
9. Document current working state
10. Review and get team approval

## Testing

```bash
# Audit current implementation
./audit-implementation.sh > audit-report.txt

# Test that current system works
nix develop --command bash -c "
  verify-toolchains
  buck2 build //...
  buck2 test //...
"

# Snapshot for later comparison
git tag pre-extraction-v$(date +%Y%m%d)
```

## Related Documentation

- Tasks: `TASKS.md` (Phase 8.1)
- All previous phases (0-7)
- Design documents

## Next Steps

After completing this task:
- Phase 8.2: Create turnkey repository (`phase8-02-create-turnkey-repo.md`)
- Phase 8.3: Create toolchain-registry repository (`phase8-03-create-registry-repo.md`)

## Notes

- **Careful planning**: Extraction is a one-way door, plan carefully
- **Backwards compatibility**: Consider providing compatibility shim
- **Testing**: Test extracted repos independently AND together
- **Documentation**: Migration guide is critical
- **Communication**: Clear communication prevents confusion
- **Timing**: Choose low-activity period for extraction
- **Rollback plan**: Have plan to rollback if problems occur
- **Community**: Think about community needs, not just internal

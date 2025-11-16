# Phase 0.2: Create Default Toolchain Registry

## Overview

Build the default toolchain registry that maps version strings (like "1.21.5") to concrete Nix derivations. This registry will provide commonly-used toolchain versions for Go, Rust, Python, and C/C++ toolchains.

## Context

The registry is a critical component of the toolchain synchronization architecture:

- **Purpose**: Map high-level version declarations to Nix derivations
- **Separation**: Registry (data) is separate from module (mechanism)
- **Overridable**: Downstream repos can provide custom registries
- **Future**: Will be extracted to `firefly-engineering/toolchain-registry`

### Registry Architecture

```
toolchain.toml          registry.nix           Resolved Derivations
─────────────           ────────────           ────────────────────
[go]                    "1.21.5" → pkgs.go_1_21    /nix/store/abc123-go-1.21.5
version = "1.21.5" ───→ "1.22.0" → pkgs.go_1_22    /nix/store/def456-go-1.22.0

[rust]                  "1.75.0" → pkgs.rust     /nix/store/xyz789-rust-1.75.0
version = "1.75.0" ───→
```

Both the development shell and Buck2 use the **same resolved derivation** (same Nix store path).

## Prerequisites

- Phase 0.1: Flake module structure created
- Understanding of nixpkgs structure
- Familiarity with language toolchain packages in nixpkgs

## Success Criteria

- [ ] `nix/modules/toolchains/registry-default.nix` exists
- [ ] Registry includes 3-5 versions each for Go, Rust, Python
- [ ] Registry includes C/C++ toolchain entries
- [ ] Each entry maps to valid nixpkgs derivation
- [ ] Registry has clear, documented structure
- [ ] Registry is overridable by downstream users

## Implementation Guidance

### 1. Registry File Structure

Create `nix/modules/toolchains/registry-default.nix`:

```nix
{ pkgs }:

{
  # Go toolchains
  go = {
    "1.21.5" = pkgs.go_1_21;
    "1.21" = pkgs.go_1_21;  # Alias for latest 1.21.x
    "1.22.0" = pkgs.go_1_22;
    "1.22" = pkgs.go_1_22;
    "1.23.0" = pkgs.go_1_23;
    "1.23" = pkgs.go_1_23;
  };

  # Rust toolchains
  rust = {
    "1.75.0" = pkgs.rust-bin.stable."1.75.0".default;
    "1.76.0" = pkgs.rust-bin.stable."1.76.0".default;
    "1.77.0" = pkgs.rust-bin.stable."1.77.0".default;
    "stable" = pkgs.rustc;  # Latest stable from nixpkgs
  };

  # Python toolchains
  python = {
    "3.11" = pkgs.python311;
    "3.12" = pkgs.python312;
    "3.13" = pkgs.python313;
  };

  # C/C++ toolchains
  clang = {
    "17" = pkgs.clang_17;
    "18" = pkgs.clang_18;
    "latest" = pkgs.clang;
  };

  gcc = {
    "12" = pkgs.gcc12;
    "13" = pkgs.gcc13;
    "14" = pkgs.gcc14;
  };
}
```

### 2. Registry Design Principles

**Versioning Strategy**:
- Use **semantic version strings** as keys: "1.21.5", not internal nixpkgs names
- Provide **aliases** for convenience: "1.21" → latest 1.21.x
- Include **special versions**: "stable", "latest" where appropriate

**Nixpkgs Integration**:
- Prefer **stable nixpkgs** packages when available
- Document any **overlays** or **custom derivations** needed
- Consider using **fenix** for Rust (more version control)

**Future Extraction**:
- Keep registry **self-contained**
- No dependencies on this repository's specifics
- Document versioning policy for community maintenance

### 3. Make Registry Overridable

The module (from Phase 0.1) should allow:

```nix
# Downstream repo can override
firefly.toolchains.registry = ./my-custom-registry.nix;

# Or extend default
firefly.toolchains.registry = lib.attrsets.recursiveUpdate
  (import firefly-toolchains.defaultRegistry { inherit pkgs; })
  {
    go."1.24.0" = pkgs.go_1_24;  # Add custom version
  };
```

### 4. Documentation in Comments

Add comprehensive documentation:

```nix
{ pkgs }:

# Default Toolchain Registry
#
# This registry maps toolchain version strings to concrete Nix derivations.
# It serves as the default registry for the toolchain synchronization module.
#
# Structure:
#   <language>.<version> = <nixpkgs-derivation>
#
# Versioning Policy:
#   - Include last 3 major versions of each toolchain
#   - Provide patch-level versions where security-critical
#   - Use semantic versioning for keys
#   - Include convenience aliases ("stable", "latest", "1.21" → "1.21.x")
#
# Adding New Versions:
#   1. Verify package exists in nixpkgs
#   2. Add entry with semantic version key
#   3. Test that derivation builds successfully
#   4. Update this header with date of last update
#
# Last Updated: 2025-01-XX

{
  # ... registry entries ...
}
```

### 5. Common Toolchain Sources

**Go**: Available directly in nixpkgs as `pkgs.go_1_XX`

**Rust**: Two options:
- Simple: `pkgs.rustc`, `pkgs.cargo` (latest stable)
- Advanced: Use fenix overlay for specific versions

**Python**: Available as `pkgs.python3XX`

**C/C++**: Available as `pkgs.gcc`, `pkgs.clang`, with version suffixes

### 6. Validation

Create test to verify all registry entries are valid:

```nix
# In registry file or separate test
let
  testRegistry = go: {
    "1.21.5" = go;
  };
in
assert (testRegistry pkgs.go_1_21) != null;
```

## Implementation Steps

1. Create `nix/modules/toolchains/registry-default.nix`
2. Add Go versions (3-5 versions from nixpkgs)
3. Add Rust versions (consider fenix overlay)
4. Add Python versions (3.11, 3.12, 3.13)
5. Add C/C++ toolchains (gcc, clang)
6. Add comprehensive documentation in comments
7. Document versioning policy
8. Test that all derivations are valid

## Testing

```bash
# Test that registry evaluates
nix eval .#flakeModules.toolchains.registry-default

# Test specific entry
nix eval .#flakeModules.toolchains.registry-default.go.\"1.21.5\"

# Build a specific toolchain to verify
nix build .#flakeModules.toolchains.registry-default.go.\"1.21.5\"
```

## Related Documentation

- Design: `docs/src/design/toolchain-synchronization.md` (section 2: "Registry Resolution")
- Tasks: `TASKS.md` (Phase 0.2)
- Nixpkgs Manual: https://nixos.org/manual/nixpkgs/stable/

## Next Steps

After completing this task:
- Phase 0.3: Implement resolution logic to use this registry (`phase0-03-implement-resolution-logic.md`)

## Notes

- **Keep it simple initially**: Start with nixpkgs packages, add complexity later
- **Document everything**: This will become community-maintained in Phase 8
- **Think about patches**: Leave room for patch application (Phase 5)
- **Version availability**: Check nixpkgs for available versions before adding
- **Future split**: This file will move to `firefly-engineering/toolchain-registry` in Phase 8

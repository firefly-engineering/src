# Phase 5.1: Implement Toolchain Patch Management

## Overview

Add support for applying security patches and customizations to toolchains in the registry. This enables quick security responses and toolchain customization without waiting for upstream nixpkgs updates.

## Context

Sometimes you need to apply patches to toolchains:

1. **Security patches**: Fix vulnerabilities before official release
2. **Bug fixes**: Apply fixes not yet in nixpkgs
3. **Customizations**: Company-specific modifications
4. **Backports**: Backport fixes to older versions

The registry should make this transparent to users.

### Example Use Case

```
CVE-2024-XXXX discovered in Go 1.21.5
Official fix won't be released for 2 days
Need to patch production builds immediately

Solution:
1. Apply patch to Go 1.21.5 in registry
2. Nix rebuilds Go with patch
3. New Nix store path triggers Buck2 cache invalidation
4. All builds automatically use patched version
```

## Prerequisites

- Phase 0.2: Default registry created
- Phase 0.3: Resolution logic working
- Understanding of Nix package overriding
- Familiarity with patch application in Nix

## Success Criteria

- [ ] Registry supports patched toolchain versions
- [ ] Patches applied automatically during resolution
- [ ] Patched versions have different Nix store paths (auto cache invalidation)
- [ ] Patch application documented in registry
- [ ] Example patches provided
- [ ] Testing shows patches applied correctly
- [ ] Users can add custom patches easily

## Implementation Guidance

### 1. Patch Directory Structure

Create organized patch storage:

```
nix/modules/toolchains/
├── registry-default.nix
└── patches/
    ├── go/
    │   ├── cve-2024-xxxx-fix.patch
    │   └── performance-improvement.patch
    ├── rust/
    │   └── security-fix.patch
    └── python/
        └── ssl-fix.patch
```

### 2. Registry Entry with Patch

Update registry to support patches:

```nix
{ pkgs }:

let
  # Helper function to apply patches
  applyPatches = derivation: patches:
    if patches == [] then
      derivation
    else
      derivation.overrideAttrs (old: {
        patches = (old.patches or []) ++ patches;
      });
in
{
  go = {
    # Unpatched version
    "1.21.5" = pkgs.go_1_21;

    # Patched version
    "1.21.5-patched" = applyPatches pkgs.go_1_21 [
      ./patches/go/cve-2024-xxxx-fix.patch
    ];

    # Explicitly named patch version
    "1.21.5-cve-fix" = applyPatches pkgs.go_1_21 [
      ./patches/go/cve-2024-xxxx-fix.patch
    ];

    # Multiple patches
    "1.21.5-hardened" = applyPatches pkgs.go_1_21 [
      ./patches/go/cve-2024-xxxx-fix.patch
      ./patches/go/performance-improvement.patch
    ];
  };

  rust = {
    "1.75.0" = pkgs.rustc;

    "1.75.0-patched" = applyPatches pkgs.rustc [
      ./patches/rust/security-fix.patch
    ];
  };
}
```

### 3. Automatic Patching (Alternative Approach)

Apply patches automatically to all versions:

```nix
{ pkgs }:

let
  # Security patches to apply to all Go 1.21.x versions
  go121Patches = [
    ./patches/go/cve-2024-xxxx-fix.patch
  ];

  # Helper to auto-patch based on version
  autoPatch = derivation: version:
    let
      patches =
        if lib.hasPrefix "1.21" version then go121Patches
        else [];
    in
    applyPatches derivation patches;
in
{
  go = {
    "1.21.5" = autoPatch pkgs.go_1_21 "1.21.5";
    "1.21.6" = autoPatch pkgs.go_1_21 "1.21.6";
    "1.22.0" = pkgs.go_1_22;  # No auto-patches for 1.22
  };
}
```

### 4. Patch Documentation

Create `nix/modules/toolchains/patches/README.md`:

```markdown
# Toolchain Patches

This directory contains patches applied to toolchains in the default registry.

## Structure

```
patches/
├── <language>/
│   ├── <patch-name>.patch
│   └── README.md       # Explains each patch
```

## Adding a Patch

### 1. Create the patch file

```bash
# For Go example:
cd /tmp
nix-shell -p go_1_21
# Make modifications to Go source
diff -u original modified > go-fix.patch
```

### 2. Add to patches directory

```bash
cp go-fix.patch nix/modules/toolchains/patches/go/
```

### 3. Update registry

Edit `registry-default.nix`:

```nix
go = {
  "1.21.5-patched" = applyPatches pkgs.go_1_21 [
    ./patches/go/go-fix.patch
  ];
};
```

### 4. Document the patch

Create `patches/go/README.md`:

```markdown
## go-fix.patch

- **Purpose**: Fix CVE-2024-XXXX
- **Upstream Issue**: https://github.com/golang/go/issues/XXXXX
- **Applies to**: Go 1.21.x
- **Remove when**: Go 1.21.7+ released with fix
```

### 5. Update toolchain.toml

```toml
[go]
version = "1.21.5-patched"
```

## Current Patches

### Go

#### cve-2024-xxxx-fix.patch
- **CVE**: CVE-2024-XXXX
- **Severity**: High
- **Description**: Fixes buffer overflow in net/http
- **Status**: Temporary until Go 1.21.7 released
- **Applied to**: All 1.21.x versions

[Document each patch...]
```

### 5. Patch Testing

Create test to verify patches apply correctly:

```nix
let
  testPatchApplication = pkgs.writeScriptBin "test-patches" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Testing Patch Application"
    echo "========================="

    # Build patched toolchain
    echo ""
    echo "Building patched Go 1.21.5..."
    nix build .#resolvedToolchains.go --no-link

    # Verify it's different from unpatched
    PATCHED_PATH=$(nix eval --raw .#resolvedToolchains.go)
    UNPATCHED_PATH=$(nix eval --raw .#nixpkgs.go_1_21)

    echo ""
    echo "Unpatched: $UNPATCHED_PATH"
    echo "Patched:   $PATCHED_PATH"

    if [ "$PATCHED_PATH" != "$UNPATCHED_PATH" ]; then
      echo "✅ Patch changed derivation (different store path)"
    else
      echo "❌ Patch did not change derivation!"
      exit 1
    fi

    # Verify patch was applied (check for expected changes)
    echo ""
    echo "Verifying patch was applied..."
    # This is language/patch specific
    # Example: Check that patched file exists
  '';
in
```

### 6. Emergency Patch Workflow

Document emergency security patch process:

```markdown
# Emergency Security Patch Workflow

When a critical CVE is discovered:

## 1. Obtain Patch (15 minutes)

```bash
# Download official patch or create from diff
curl https://go.dev/security/cve-xxxx.patch -o patches/go/cve-xxxx.patch

# Or create from upstream commit:
git diff commit1 commit2 > patches/go/cve-xxxx.patch
```

## 2. Add to Registry (5 minutes)

Edit `registry-default.nix`:

```nix
"1.21.5-cve-xxxx-fix" = applyPatches pkgs.go_1_21 [
  ./patches/go/cve-xxxx.patch
];
```

## 3. Test Locally (10 minutes)

```bash
# Update toolchain.toml
sed -i 's/version = "1.21.5"/version = "1.21.5-cve-xxxx-fix"/' toolchain.toml

# Enter shell and verify
nix develop
go version  # Should show patched version

# Build and test
buck2 test //...
```

## 4. Deploy (5 minutes)

```bash
# Commit and push
git add .
git commit -m "security: Apply CVE-XXXX fix to Go 1.21.5"
git push

# Team members update
git pull
nix develop  # Automatically gets patched version
buck2 build //...  # Cache invalidates, uses patched Go
```

**Total time**: ~35 minutes from CVE disclosure to patched production builds
```

### 7. Patch Metadata

Track patch metadata in registry:

```nix
{
  go = {
    "1.21.5-cve-fix" = {
      derivation = applyPatches pkgs.go_1_21 [
        ./patches/go/cve-2024-xxxx-fix.patch
      ];

      metadata = {
        patches = [
          {
            name = "cve-2024-xxxx-fix.patch";
            cve = "CVE-2024-XXXX";
            severity = "high";
            description = "Fix buffer overflow in net/http";
            upstream = "https://github.com/golang/go/issues/XXXXX";
            removeWhen = "Go 1.21.7+ released";
          }
        ];
      };
    };
  };
}

# Accessor function
getPatchedToolchain = name: version:
  let
    entry = registry.${name}.${version};
  in
  if builtins.isAttrs entry && entry ? derivation
  then entry.derivation
  else entry;  # Backward compatible
```

### 8. Verification in Buck2 Config

Generated Buck2 config should show patch is applied:

```ini
# .buckconfig.toolchains
# Generated by firefly-toolchains module

[go]
# Toolchain: Go 1.21.5-cve-fix
# Patches applied:
#   - cve-2024-xxxx-fix.patch (CVE-2024-XXXX)
go_bin = /nix/store/xyz-go-1.21.5-patched/bin/go
```

## Implementation Steps

1. Create `patches/` directory structure
2. Implement `applyPatches` helper function
3. Add example patches for Go, Rust, Python
4. Update registry to use `applyPatches`
5. Test patch application
6. Verify Nix store path changes
7. Verify Buck2 cache invalidation
8. Document patch addition process
9. Document emergency patch workflow
10. Create patch metadata tracking (optional)

## Testing

```bash
# Test patch application
echo '[go]\nversion = "1.21.5-patched"' > toolchain.toml
nix develop

# Verify different path than unpatched
GO_PATCHED=$(which go)
echo '[go]\nversion = "1.21.5"' > toolchain.toml
nix develop
GO_UNPATCHED=$(which go)

[ "$GO_PATCHED" != "$GO_UNPATCHED" ] && echo "✅ Paths differ" || echo "❌ Paths same!"

# Test cache invalidation
buck2 build //... # With unpatched
# ... change to patched version ...
buck2 build //... # Should rebuild (cache miss)

# Test emergency workflow
./test-emergency-patch.sh
```

## Related Documentation

- Design: `docs/src/design/toolchain-synchronization.md` (section on patches)
- Tasks: `TASKS.md` (Phase 5.1)
- User Guide: `docs/src/user-guide/custom-registry.md` (patch section)

## Next Steps

After completing this task:
- Phase 6: CI/CD integration (use patches in CI)
- Create alerts for when patches should be removed (upstream fixed)

## Notes

- **Security**: Patches enable rapid security response
- **Transparency**: Document why each patch exists
- **Temporary**: Patches should be temporary until upstream fixes
- **Testing**: Always test patched versions thoroughly
- **Cache invalidation**: Automatic via Nix store path change
- **Metadata**: Track patch provenance for auditing
- **Removal**: Document when to remove patch (fixed upstream)
- **Community**: Share patches with community if applicable

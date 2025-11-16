# Phase 3.1: Fork and Customize Buck2 Prelude

## Overview

Fork the Buck2 prelude and customize it to work seamlessly with system toolchains from Nix. Remove embedded toolchain binaries and integrate with the toolchain synchronization module.

## Context

Buck2's default prelude includes embedded toolchains and toolchain download logic. We want to replace this with our Nix-provided system toolchains.

### Current State (Default Prelude)

```
prelude/
├── go/
│   ├── toolchain.bzl       # Downloads Go if not present
│   └── go_binary.bzl
└── rust/
    ├── toolchain.bzl       # Downloads Rust if not present
    └── rust_binary.bzl
```

### Desired State (Custom Prelude)

```
prelude/
├── go/
│   ├── toolchain.bzl       # Uses system Go from Buck2 config
│   └── go_binary.bzl       # Unchanged
└── rust/
    ├── toolchain.bzl       # Uses system Rust from Buck2 config
    └── rust_binary.bzl     # Unchanged
```

## Prerequisites

- Phase 0.5: Buck2 config generation working
- Understanding of Buck2 prelude structure
- Understanding of Starlark (Buck2's configuration language)
- Ability to read and modify Buck2 rules

## Success Criteria

- [ ] Custom prelude forked in `prelude/` directory
- [ ] Toolchain registration uses system toolchains
- [ ] No embedded toolchain binaries in prelude
- [ ] `go_binary`, `go_library`, `go_test` rules work with system Go
- [ ] `rust_binary`, `rust_library`, `rust_test` rules work with system Rust
- [ ] Python rules work with system Python
- [ ] C/C++ rules work with system clang/gcc
- [ ] `.buckconfig` configured to use custom prelude

## Implementation Guidance

### 1. Fork Prelude Structure

```bash
# Create prelude directory at repo root
mkdir -p prelude

# Download Buck2 prelude as reference
git clone https://github.com/facebook/buck2-prelude.git /tmp/buck2-prelude

# Copy relevant modules
cp -r /tmp/buck2-prelude/go prelude/
cp -r /tmp/buck2-prelude/rust prelude/
cp -r /tmp/buck2-prelude/python prelude/
cp -r /tmp/buck2-prelude/cxx prelude/
cp /tmp/buck2-prelude/prelude.bzl prelude/

# Note fork point for documentation
echo "Forked from buck2-prelude commit: $(cd /tmp/buck2-prelude && git rev-parse HEAD)" > prelude/FORK_INFO
```

### 2. Customize Go Toolchain Registration

Modify `prelude/go/toolchain.bzl`:

```python
# Original (downloads Go):
# def _go_toolchain_impl(ctx):
#     go_root = ctx.actions.declare_output("go")
#     ctx.actions.download(
#         url = "https://go.dev/dl/go1.21.5.tar.gz",
#         output = go_root,
#     )
#     return [GoToolchainInfo(go_root = go_root)]

# Modified (uses system Go):
def _go_toolchain_impl(ctx):
    # Get Go path from Buck2 config (set by our module)
    go_bin = read_root_config("go", "go_bin")

    if not go_bin:
        fail("Go toolchain not configured. Ensure .buckconfig.toolchains is generated.")

    # Go root is parent of bin/ directory
    go_root = go_bin.rpartition("/bin/")[0]

    return [GoToolchainInfo(
        go = go_bin,
        go_root = go_root,
    )]

go_toolchain = rule(
    impl = _go_toolchain_impl,
    attrs = {},
    is_toolchain_rule = True,
)
```

### 3. Customize Rust Toolchain Registration

Modify `prelude/rust/toolchain.bzl`:

```python
def _rust_toolchain_impl(ctx):
    # Get Rust paths from Buck2 config
    rustc_bin = read_root_config("rust", "rustc_bin")
    cargo_bin = read_root_config("rust", "cargo_bin")

    if not rustc_bin or not cargo_bin:
        fail("Rust toolchain not configured. Ensure .buckconfig.toolchains is generated.")

    return [RustToolchainInfo(
        rustc = rustc_bin,
        cargo = cargo_bin,
    )]

rust_toolchain = rule(
    impl = _rust_toolchain_impl,
    attrs = {},
    is_toolchain_rule = True,
)
```

### 4. Customize Python Toolchain

Modify `prelude/python/toolchain.bzl`:

```python
def _python_toolchain_impl(ctx):
    python_bin = read_root_config("python", "python_bin")

    if not python_bin:
        fail("Python toolchain not configured.")

    return [PythonToolchainInfo(
        python = python_bin,
    )]

python_toolchain = rule(
    impl = _python_toolchain_impl,
    attrs = {},
    is_toolchain_rule = True,
)
```

### 5. Update Toolchains Registration

Create `prelude/toolchains/BUCK`:

```python
load("@prelude//go:toolchain.bzl", "go_toolchain")
load("@prelude//rust:toolchain.bzl", "rust_toolchain")
load("@prelude//python:toolchain.bzl", "python_toolchain")

go_toolchain(
    name = "go",
    visibility = ["PUBLIC"],
)

rust_toolchain(
    name = "rust",
    visibility = ["PUBLIC"],
)

python_toolchain(
    name = "python",
    visibility = ["PUBLIC"],
)

# CXX toolchain uses system compilers
cxx_toolchain(
    name = "cxx",
    compiler = read_root_config("cxx", "cc"),
    cxx_compiler = read_root_config("cxx", "cxx"),
    visibility = ["PUBLIC"],
)
```

### 6. Configure Buck2 to Use Custom Prelude

Update `.buckconfig`:

```ini
[repositories]
# Use local custom prelude instead of downloading
prelude = prelude
root = .

[buildfile]
name = BUCK

# Other Buck2 configuration
<file:.buckconfig.toolchains>
```

### 7. Remove Embedded Toolchains

```bash
# Remove any embedded toolchain binaries
find prelude/ -name "*.tar.gz" -delete
find prelude/ -name "*.zip" -delete
find prelude/ -type d -name "embedded" -exec rm -rf {} +

# Document what was removed
git diff prelude/ > prelude/CUSTOMIZATIONS.patch
```

### 8. Document Customizations

Create `prelude/README.md`:

```markdown
# Custom Buck2 Prelude

This is a customized fork of the Buck2 prelude that integrates with
Nix-provided system toolchains.

## Fork Information

- **Upstream**: https://github.com/facebook/buck2-prelude
- **Fork point**: [commit hash from FORK_INFO]
- **Customizations**: See CUSTOMIZATIONS.patch

## Changes from Upstream

### Go Toolchain
- Removed: Toolchain download logic
- Added: Integration with system Go from .buckconfig

### Rust Toolchain
- Removed: Toolchain download logic
- Added: Integration with system Rust from .buckconfig

### Python Toolchain
- Removed: Toolchain download logic
- Added: Integration with system Python from .buckconfig

### C/C++ Toolchain
- Uses system clang/gcc from .buckconfig

## Maintenance

To update to newer Buck2 prelude:

1. Fetch upstream changes
2. Reapply customizations from CUSTOMIZATIONS.patch
3. Test all language rules
4. Update fork point in FORK_INFO

## Rationale

By using system toolchains:
- ✅ Developers and Buck2 use identical toolchain binaries
- ✅ No network downloads during builds
- ✅ Consistent behavior between `go build` and `buck2 build`
- ✅ Nix provides reproducibility guarantees
```

### 9. Test Language Rules

Create test targets for each language:

**Go test** (`test-prelude/go/BUCK`):

```python
go_library(
    name = "lib",
    srcs = ["lib.go"],
)

go_binary(
    name = "app",
    srcs = ["main.go"],
    deps = [":lib"],
)

go_test(
    name = "test",
    srcs = ["lib_test.go"],
    deps = [":lib"],
)
```

**Rust test** (`test-prelude/rust/BUCK`):

```python
rust_library(
    name = "lib",
    srcs = ["lib.rs"],
)

rust_binary(
    name = "app",
    srcs = ["main.rs"],
    deps = [":lib"],
)

rust_test(
    name = "test",
    srcs = ["lib.rs"],
)
```

Test:

```bash
# Go
buck2 build //test-prelude/go:app
buck2 test //test-prelude/go:test

# Rust
buck2 build //test-prelude/rust:app
buck2 test //test-prelude/rust:test
```

### 10. Update Nix Module to Reference Prelude Location

The Buck2 config generator should know about prelude:

```nix
let
  buckConfigContent = ''
    # Generated by firefly-toolchains module

    [repositories]
    prelude = prelude
    root = .

    [buildfile]
    name = BUCK

    ${generateBuckConfig resolved}
  '';
in
```

## Implementation Steps

1. Create `prelude/` directory
2. Fork Buck2 prelude from upstream
3. Document fork point and rationale
4. Customize Go toolchain integration
5. Customize Rust toolchain integration
6. Customize Python toolchain integration
7. Customize C/C++ toolchain integration
8. Remove embedded toolchain binaries
9. Update `.buckconfig` to use custom prelude
10. Create test projects for each language
11. Test all language rules work
12. Document all customizations

## Testing

```bash
# Verify Buck2 recognizes custom prelude
buck2 audit prelude

# Test Go rules
buck2 build //test-prelude/go:...
buck2 test //test-prelude/go:...

# Test Rust rules
buck2 build //test-prelude/rust:...
buck2 test //test-prelude/rust:...

# Test Python rules
buck2 build //test-prelude/python:...

# Verify system toolchains are used
buck2 build //test-prelude/go:app --verbose 2>&1 | grep "go_bin"
# Should show Nix store path
```

## Related Documentation

- Design: `docs/src/design/toolchain-synchronization.md` (Phase 3)
- Tasks: `TASKS.md` (Phase 3)
- Buck2 Prelude: https://github.com/facebook/buck2-prelude
- Buck2 Docs: Custom prelude

## Next Steps

After completing this task:
- Phase 4: External cell for build utilities
- Use custom prelude in all example projects

## Notes

- **Maintenance burden**: Custom prelude requires keeping up with upstream changes
- **Minimal changes**: Only modify what's necessary for system toolchain integration
- **Testing**: Comprehensive testing required to ensure rules work correctly
- **Documentation**: Document all changes for future maintenance
- **Fork point**: Track upstream commit for easy rebasing
- **Community**: Consider contributing system toolchain support upstream
- **Fallback**: Keep reference to upstream prelude for comparison

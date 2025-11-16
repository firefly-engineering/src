# Phase 0.4: Implement Development Shell Generation

## Overview

Implement the shell environment generation that adds resolved toolchains to the development shell. This ensures developers have the correct toolchain binaries available when they run `nix develop`.

## Context

The development shell is one half of the synchronization equation:

- **Shell Environment**: Developers use `go build`, `cargo check`, IDE language servers
- **Buck2 Environment**: Buck2 uses system toolchains for builds

Both must use **identical binaries** from the same Nix store paths.

### Shell Generation Flow

```
Resolved Toolchains                Development Shell
───────────────────                ─────────────────
{ go = /nix/store/abc-go;          devShell.packages = [
  rust = /nix/store/xyz-rust;        /nix/store/abc-go
  python = /nix/store/def-py;  ───→  /nix/store/xyz-rust
}                                    /nix/store/def-py
                                   ]

                                   $ which go
                                   /nix/store/abc-go/bin/go
```

## Prerequisites

- Phase 0.1: Flake module structure created
- Phase 0.2: Default registry implemented
- Phase 0.3: Resolution logic implemented
- Understanding of Nix devShell configuration

## Success Criteria

- [ ] Resolved toolchains added to `devShell.packages`
- [ ] `which go` returns Nix store path from resolved toolchain
- [ ] Multiple toolchains can coexist in shell
- [ ] Environment variables set if needed
- [ ] Shell hooks configured if needed
- [ ] Verification that shell path matches resolved derivation

## Implementation Guidance

### 1. Basic Shell Integration

Update module to provide shell packages:

```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.firefly.toolchains;
  resolved = cfg.resolved;  # From Phase 0.3

  # Extract derivations as list for shell
  toolchainPackages = lib.attrValues resolved;
in
{
  config = {
    # Add resolved toolchains to development shell
    devShells.default = pkgs.mkShell {
      packages = toolchainPackages ++ [
        # Other development tools
        pkgs.buck2
        pkgs.git
      ];
    };
  };
}
```

### 2. Environment Variable Configuration

Some toolchains may need environment variables:

```nix
let
  # Language-specific environment setup
  shellEnv = {
    # Go configuration
    GOROOT = lib.optionalString (resolved ? go) "${resolved.go}/share/go";

    # Rust configuration
    RUSTC = lib.optionalString (resolved ? rust) "${resolved.rust}/bin/rustc";
    CARGO = lib.optionalString (resolved ? rust) "${resolved.rust}/bin/cargo";

    # Python configuration
    PYTHONPATH = lib.optionalString (resolved ? python)
      "${resolved.python}/lib/python${resolved.python.pythonVersion}/site-packages";
  };
in
{
  devShells.default = pkgs.mkShell {
    packages = toolchainPackages;

    # Set environment variables
    shellHook = ''
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList
        (name: value: ''export ${name}="${value}"'')
        (lib.filterAttrs (n: v: v != "") shellEnv)
      )}
    '';
  };
}
```

### 3. Shell Hooks

Add initialization hooks for better UX:

```nix
let
  shellHook = ''
    # Print toolchain versions on shell entry
    echo "🔧 Toolchain Synchronization Active"
    echo ""
    ${lib.optionalString (resolved ? go) ''
      echo "  Go:     $(${resolved.go}/bin/go version | cut -d' ' -f3)"
    ''}
    ${lib.optionalString (resolved ? rust) ''
      echo "  Rust:   $(${resolved.rust}/bin/rustc --version | cut -d' ' -f2)"
    ''}
    ${lib.optionalString (resolved ? python) ''
      echo "  Python: $(${resolved.python}/bin/python --version | cut -d' ' -f2)"
    ''}
    echo ""
    echo "ℹ️  Buck2 configs synchronized to same toolchains"
    echo ""
  '';
in
{
  devShells.default = pkgs.mkShell {
    packages = toolchainPackages;
    inherit shellHook;
  };
}
```

### 4. Integration with Existing devShell

If repo already has a devShell, extend it:

```nix
{
  config = lib.mkIf (resolved != {}) {
    devShells.default = lib.mkOverride 100 (
      pkgs.mkShell {
        packages = toolchainPackages ++ (config.devShells.default.packages or []);
        shellHook = shellHook + (config.devShells.default.shellHook or "");
      }
    );
  };
}
```

### 5. Module Option for Shell Configuration

Expose configuration options:

```nix
{
  options.firefly.toolchains = {
    # ... existing options ...

    shell = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Add resolved toolchains to development shell";
      };

      showVersions = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Print toolchain versions on shell entry";
      };

      extraPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [];
        description = "Additional packages to add to development shell";
      };
    };
  };
}
```

### 6. Verification Function

Add helper to verify synchronization:

```nix
let
  verifyScript = pkgs.writeScriptBin "verify-toolchains" ''
    #!/usr/bin/env bash
    echo "Verifying toolchain synchronization..."
    echo ""

    ${lib.optionalString (resolved ? go) ''
      GO_SHELL="$(which go)"
      GO_EXPECTED="${resolved.go}/bin/go"
      if [ "$GO_SHELL" = "$GO_EXPECTED" ]; then
        echo "✅ Go: $GO_SHELL"
      else
        echo "❌ Go mismatch!"
        echo "   Shell:    $GO_SHELL"
        echo "   Expected: $GO_EXPECTED"
      fi
    ''}

    ${lib.optionalString (resolved ? rust) ''
      RUSTC_SHELL="$(which rustc)"
      RUSTC_EXPECTED="${resolved.rust}/bin/rustc"
      if [ "$RUSTC_SHELL" = "$RUSTC_EXPECTED" ]; then
        echo "✅ Rust: $RUSTC_SHELL"
      else
        echo "❌ Rust mismatch!"
        echo "   Shell:    $RUSTC_SHELL"
        echo "   Expected: $RUSTC_EXPECTED"
      fi
    ''}
  '';
in
{
  devShells.default = pkgs.mkShell {
    packages = toolchainPackages ++ [ verifyScript ];
  };
}
```

## Implementation Steps

1. Update module to export devShell configuration
2. Add resolved toolchains to shell packages
3. Implement environment variable configuration
4. Add shell hook with version printing
5. Create verification script
6. Add module options for shell customization
7. Test shell environment with multiple toolchains
8. Verify `which <tool>` returns correct Nix store path

## Testing

```bash
# Enter development shell
nix develop

# Should see version banner:
# 🔧 Toolchain Synchronization Active
#   Go:     go1.21.5
#   Rust:   1.75.0
#   Python: 3.12.0

# Verify paths
which go
# Should output: /nix/store/...-go-1.21.5/bin/go

which rustc
# Should output: /nix/store/...-rust-1.75.0/bin/rustc

# Run verification script
verify-toolchains
# Should show ✅ for all configured toolchains

# Test actual usage
go version
rustc --version
python --version
```

## Related Documentation

- Design: `docs/src/design/toolchain-synchronization.md` (section 3: "Dev Environment")
- Architecture: `docs/src/architecture.md` (section 2: "Nix Development Environment")
- Tasks: `TASKS.md` (Phase 0.3)
- Nix Manual: `mkShell`, development environments

## Next Steps

After completing this task:
- Phase 0.5: Implement Buck2 config generation (`phase0-05-implement-buck2-generation.md`)
- Phase 1.2: Create validation tools (`phase1-02-create-validation-tools.md`)

## Notes

- **Path verification is critical**: Shell path must match resolved derivation exactly
- **Performance**: Shell entry should be fast (< 1 second)
- **UX matters**: Version banner provides confidence that system works
- **Flexibility**: Allow users to disable features they don't want
- **Documentation**: Add comments explaining why each environment variable is needed
- **Future**: Consider integration with direnv for automatic shell activation

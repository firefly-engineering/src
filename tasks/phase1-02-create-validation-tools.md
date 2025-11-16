# Phase 1.2: Create Validation and Testing Tools

## Overview

Create automated tools to validate that toolchain synchronization is working correctly. The key validation is that shell and Buck2 use identical binaries.

## Context

The **core promise** of this architecture is synchronization:

```
which go  ==  buck2 audit config go_bin
```

If these don't match, the system is broken. We need tools to:
1. Verify synchronization automatically
2. Compare before/after toolchain changes
3. Debug mismatches
4. Run in CI to prevent regressions

## Prerequisites

- Phase 0.4: Shell generation implemented
- Phase 0.5: Buck2 config generation implemented
- Both shell and Buck2 configs working
- Understanding of both environments

## Success Criteria

- [ ] `verify-toolchains` script exists and works
- [ ] Script checks `which <tool>` == `buck2 audit config <tool>_bin`
- [ ] Script reports success/failure clearly
- [ ] Script works for all configured toolchains
- [ ] Script can be run in CI
- [ ] Exit code indicates pass/fail

## Implementation Guidance

### 1. Basic Verification Script

Create comprehensive verification tool:

```nix
let
  verifyScript = pkgs.writeScriptBin "verify-toolchains" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "🔍 Verifying Toolchain Synchronization"
    echo "======================================"
    echo ""

    PASS=0
    FAIL=0

    # Function to verify a single toolchain
    verify_toolchain() {
      local name=$1
      local shell_cmd=$2
      local buck2_config=$3

      echo "Checking $name..."

      # Get shell path
      if ! SHELL_PATH=$(which "$shell_cmd" 2>/dev/null); then
        echo "  ❌ '$shell_cmd' not found in shell PATH"
        ((FAIL++))
        return
      fi

      # Get Buck2 config path
      if ! BUCK2_PATH=$(buck2 audit config "$buck2_config" 2>/dev/null); then
        echo "  ❌ Buck2 config '$buck2_config' not found"
        ((FAIL++))
        return
      fi

      # Compare
      if [ "$SHELL_PATH" = "$BUCK2_PATH" ]; then
        echo "  ✅ $SHELL_PATH"
        ((PASS++))
      else
        echo "  ❌ MISMATCH!"
        echo "     Shell:  $SHELL_PATH"
        echo "     Buck2:  $BUCK2_PATH"
        ((FAIL++))
      fi
      echo ""
    }

    # Verify each configured toolchain
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: deriv:
      if name == "go" then ''
        verify_toolchain "Go" "go" "go.go_bin"
      ''
      else if name == "rust" then ''
        verify_toolchain "Rust (rustc)" "rustc" "rust.rustc_bin"
        verify_toolchain "Rust (cargo)" "cargo" "rust.cargo_bin"
      ''
      else if name == "python" then ''
        verify_toolchain "Python" "python" "python.python_bin"
      ''
      else if name == "clang" then ''
        verify_toolchain "Clang" "clang" "cxx.cc"
        verify_toolchain "Clang++" "clang++" "cxx.cxx"
      ''
      else ""
    ) resolved)}

    # Summary
    echo "======================================"
    echo "Results: $PASS passed, $FAIL failed"
    echo ""

    if [ $FAIL -eq 0 ]; then
      echo "✅ All toolchains synchronized!"
      exit 0
    else
      echo "❌ Synchronization check failed!"
      echo ""
      echo "To fix:"
      echo "  1. Run: generate-buck2-configs"
      echo "  2. Or exit and re-enter: nix develop"
      echo ""
      exit 1
    fi
  '';
in
```

### 2. Detailed Diagnostic Tool

Create tool to show detailed information:

```nix
let
  diagnoseScript = pkgs.writeScriptBin "diagnose-toolchains" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "📊 Toolchain Diagnostic Report"
    echo "======================================"
    echo ""

    # Show resolved toolchains from Nix
    echo "Resolved Toolchains (from Nix):"
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: deriv: ''
      echo "  ${name}: ${deriv}"
    '') resolved)}
    echo ""

    # Show shell PATH entries
    echo "Shell PATH (Nix store entries):"
    echo "$PATH" | tr ':' '\n' | grep '/nix/store' | head -10
    echo ""

    # Show Buck2 config
    echo "Buck2 Configuration:"
    if command -v buck2 &> /dev/null; then
      buck2 audit config go rust python cxx 2>/dev/null || echo "  (Buck2 config not yet generated)"
    else
      echo "  (Buck2 not available)"
    fi
    echo ""

    # Show generated files
    echo "Generated Files:"
    if [ -f .buckconfig.toolchains ]; then
      echo "  ✅ .buckconfig.toolchains"
      echo "     Modified: $(stat -f %Sm .buckconfig.toolchains)"
    else
      echo "  ❌ .buckconfig.toolchains (missing)"
    fi

    if [ -d toolchains ]; then
      echo "  ✅ toolchains/ directory"
      ls -1 toolchains/ | sed 's/^/     - /'
    else
      echo "  ❌ toolchains/ directory (missing)"
    fi
    echo ""

    # Show toolchain.toml
    echo "toolchain.toml:"
    if [ -f toolchain.toml ]; then
      cat toolchain.toml | sed 's/^/  /'
    else
      echo "  (file not found)"
    fi
  '';
in
```

### 3. Version Comparison Tool

Create tool to track version changes:

```nix
let
  compareVersionsScript = pkgs.writeScriptBin "compare-toolchain-versions" ''
    #!/usr/bin/env bash
    set -euo pipefail

    CACHE_FILE=".toolchain-versions.cache"

    # Get current versions
    get_current_versions() {
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: deriv:
        if name == "go" then ''
          echo "go=$(${deriv}/bin/go version 2>/dev/null || echo 'not available')"
        ''
        else if name == "rust" then ''
          echo "rust=$(${deriv}/bin/rustc --version 2>/dev/null || echo 'not available')"
        ''
        else if name == "python" then ''
          echo "python=$(${deriv}/bin/python --version 2>/dev/null || echo 'not available')"
        ''
        else ""
      ) resolved)}
    }

    CURRENT=$(get_current_versions | sort)

    # Compare with cached versions
    if [ -f "$CACHE_FILE" ]; then
      CACHED=$(cat "$CACHE_FILE")

      if [ "$CURRENT" = "$CACHED" ]; then
        echo "✅ Toolchain versions unchanged"
      else
        echo "🔄 Toolchain versions changed:"
        echo ""
        diff <(echo "$CACHED") <(echo "$CURRENT") || true
        echo ""
        echo "Buck2 cache will be invalidated due to path changes"
      fi
    else
      echo "📝 First run - caching toolchain versions"
    fi

    # Update cache
    echo "$CURRENT" > "$CACHE_FILE"
  '';
in
```

### 4. CI-Friendly Validation

Create variant for CI environments:

```nix
let
  ciVerifyScript = pkgs.writeScriptBin "ci-verify-toolchains" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # CI-friendly output (less emoji, more structured)

    echo "::group::Toolchain Synchronization Check"

    ERRORS=()

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: deriv:
      if name == "go" then ''
        SHELL_GO=$(which go 2>/dev/null || echo "")
        BUCK2_GO=$(buck2 audit config go.go_bin 2>/dev/null || echo "")

        if [ -z "$SHELL_GO" ]; then
          ERRORS+=("Go not found in shell PATH")
        elif [ -z "$BUCK2_GO" ]; then
          ERRORS+=("Go not configured in Buck2")
        elif [ "$SHELL_GO" != "$BUCK2_GO" ]; then
          ERRORS+=("Go path mismatch: shell=$SHELL_GO buck2=$BUCK2_GO")
        else
          echo "PASS: Go synchronized at $SHELL_GO"
        fi
      ''
      else ""
    ) resolved)}

    echo "::endgroup::"

    if [ ''${#ERRORS[@]} -gt 0 ]; then
      echo "::error::Toolchain synchronization failed"
      for err in "''${ERRORS[@]}"; do
        echo "::error::$err"
      done
      exit 1
    else
      echo "All toolchains synchronized successfully"
      exit 0
    fi
  '';
in
```

### 5. Integration with Module

Add all scripts to devShell:

```nix
{
  config = {
    devShells.default = pkgs.mkShell {
      packages = toolchainPackages ++ [
        verifyScript
        diagnoseScript
        compareVersionsScript
        ciVerifyScript
      ];

      shellHook = ''
        ${existingShellHook}

        # Auto-verify on shell entry (optional)
        ${lib.optionalString cfg.shell.autoVerify ''
          if ! verify-toolchains --quiet; then
            echo "⚠️  Warning: Toolchain synchronization check failed"
            echo "   Run 'verify-toolchains' for details"
          fi
        ''}
      '';
    };
  };
}
```

### 6. Add Module Options

```nix
{
  options.firefly.toolchains.shell = {
    autoVerify = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Automatically verify synchronization on shell entry";
    };
  };
}
```

## Implementation Steps

1. Create `verify-toolchains` script
2. Create `diagnose-toolchains` script
3. Create `compare-toolchain-versions` script
4. Create `ci-verify-toolchains` script
5. Add all scripts to devShell packages
6. Add auto-verification option (disabled by default)
7. Test all scripts with various scenarios
8. Document usage in user guide

## Testing

```bash
# Basic verification
nix develop
verify-toolchains
# Should show ✅ for all toolchains

# Diagnostic information
diagnose-toolchains
# Should show complete system state

# Test mismatch detection
# Manually break synchronization
export PATH="/usr/bin:$PATH"  # Prioritize system tools
verify-toolchains
# Should show ❌ mismatch

# Test version tracking
compare-toolchain-versions
# First run: "caching versions"

# Change toolchain version
echo '[go]\nversion = "1.22"' > toolchain.toml
exit && nix develop
compare-toolchain-versions
# Should show "versions changed"

# CI mode
ci-verify-toolchains
echo $?  # Should be 0 for success
```

## Related Documentation

- Design: `docs/src/design/toolchain-synchronization.md` (section 5: "Verification")
- Architecture: `docs/src/architecture.md`
- Tasks: `TASKS.md` (Phase 1.2)

## Next Steps

After completing this task:
- Phase 1.3: Test downstream usage (`phase1-03-test-downstream-usage.md`)
- Phase 2.1: Buck2 caching validation (`phase2-01-validate-local-caching.md`)

## Notes

- **Critical validation**: `which` and `buck2 audit config` must match exactly
- **Exit codes**: Scripts should exit non-zero on failure for CI integration
- **Performance**: Validation should be fast (< 1 second)
- **Debugging**: Diagnostic tool should provide everything needed to debug issues
- **CI integration**: CI script should integrate with GitHub Actions/GitLab CI
- **Auto-verification**: Disabled by default to avoid annoying developers
- **Documentation**: Add usage examples to troubleshooting guide

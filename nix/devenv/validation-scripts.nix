{ pkgs, lib, config, ... }:

let
  # Verification script to check toolchain synchronization
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
        echo "  ⚠️  Buck2 config '$buck2_config' not found (may not be configured yet)"
        echo "     Shell: $SHELL_PATH"
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
    ${lib.optionalString config.languages.go.enable ''
    verify_toolchain "Go" "go" "go.go_bin"
    ''}

    ${lib.optionalString config.languages.rust.enable ''
    verify_toolchain "Rust (rustc)" "rustc" "rust.rustc_bin"
    verify_toolchain "Rust (cargo)" "cargo" "rust.cargo_bin"
    ''}

    ${lib.optionalString config.languages.python.enable ''
    verify_toolchain "Python" "python" "python.python_bin"
    ''}

    ${lib.optionalString (config.languages.c.enable || config.languages.cplusplus.enable) ''
    verify_toolchain "Clang" "clang" "cxx.cc"
    verify_toolchain "Clang++" "clang++" "cxx.cxx"
    ''}

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
      echo "  1. Run: generate-buck2-configs (if available)"
      echo "  2. Or exit and re-enter: nix develop"
      echo ""
      exit 1
    fi
  '';

  # Diagnostic script to show detailed information
  diagnoseScript = pkgs.writeScriptBin "diagnose-toolchains" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "📊 Toolchain Diagnostic Report"
    echo "======================================"
    echo ""

    # Show enabled languages from Nix configuration
    echo "Enabled Languages (from devenv):"
    ${lib.optionalString config.languages.go.enable ''
    echo "  ✅ Go"
    ''}
    ${lib.optionalString config.languages.rust.enable ''
    echo "  ✅ Rust"
    ''}
    ${lib.optionalString config.languages.python.enable ''
    echo "  ✅ Python"
    ''}
    ${lib.optionalString (config.languages.c.enable || config.languages.cplusplus.enable) ''
    echo "  ✅ C/C++ (Clang)"
    ''}
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
      if command -v stat &> /dev/null; then
        if stat --version 2>&1 | grep -q "GNU"; then
          echo "     Modified: $(stat -c %y .buckconfig.toolchains)"
        else
          echo "     Modified: $(stat -f %Sm .buckconfig.toolchains)"
        fi
      fi
    else
      echo "  ❌ .buckconfig.toolchains (missing)"
    fi

    if [ -d toolchains ]; then
      echo "  ✅ toolchains/ directory"
      ls -1 toolchains/ 2>/dev/null | sed 's/^/     - /' || echo "     (empty)"
    else
      echo "  ❌ toolchains/ directory (missing)"
    fi
    echo ""

    # Show toolchain.toml if it exists
    echo "toolchain.toml:"
    if [ -f toolchain.toml ]; then
      cat toolchain.toml | sed 's/^/  /'
    else
      echo "  (file not found)"
    fi
    echo ""

    # Show tool versions
    echo "Tool Versions:"
    ${lib.optionalString config.languages.go.enable ''
    if command -v go &> /dev/null; then
      echo "  Go: $(go version)"
    fi
    ''}
    ${lib.optionalString config.languages.rust.enable ''
    if command -v rustc &> /dev/null; then
      echo "  Rust: $(rustc --version)"
    fi
    if command -v cargo &> /dev/null; then
      echo "  Cargo: $(cargo --version)"
    fi
    ''}
    ${lib.optionalString config.languages.python.enable ''
    if command -v python &> /dev/null; then
      echo "  Python: $(python --version)"
    fi
    ''}
    ${lib.optionalString (config.languages.c.enable || config.languages.cplusplus.enable) ''
    if command -v clang &> /dev/null; then
      echo "  Clang: $(clang --version | head -1)"
    fi
    ''}
  '';

  # Version comparison script
  compareVersionsScript = pkgs.writeScriptBin "compare-toolchain-versions" ''
    #!/usr/bin/env bash
    set -euo pipefail

    CACHE_FILE=".toolchain-versions.cache"

    # Get current versions
    get_current_versions() {
      ${lib.optionalString config.languages.go.enable ''
      if command -v go &> /dev/null; then
        echo "go=$(go version 2>/dev/null || echo 'not available')"
      fi
      ''}
      ${lib.optionalString config.languages.rust.enable ''
      if command -v rustc &> /dev/null; then
        echo "rust=$(rustc --version 2>/dev/null || echo 'not available')"
      fi
      ''}
      ${lib.optionalString config.languages.python.enable ''
      if command -v python &> /dev/null; then
        echo "python=$(python --version 2>/dev/null || echo 'not available')"
      fi
      ''}
      ${lib.optionalString (config.languages.c.enable || config.languages.cplusplus.enable) ''
      if command -v clang &> /dev/null; then
        echo "clang=$(clang --version 2>/dev/null | head -1 || echo 'not available')"
      fi
      ''}
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

  # CI-friendly validation script
  ciVerifyScript = pkgs.writeScriptBin "ci-verify-toolchains" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # CI-friendly output (less emoji, more structured)

    echo "::group::Toolchain Synchronization Check"

    ERRORS=()

    # Verify Go
    ${lib.optionalString config.languages.go.enable ''
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
    ''}

    # Verify Rust
    ${lib.optionalString config.languages.rust.enable ''
    SHELL_RUSTC=$(which rustc 2>/dev/null || echo "")
    BUCK2_RUSTC=$(buck2 audit config rust.rustc_bin 2>/dev/null || echo "")

    if [ -z "$SHELL_RUSTC" ]; then
      ERRORS+=("Rust (rustc) not found in shell PATH")
    elif [ -z "$BUCK2_RUSTC" ]; then
      ERRORS+=("Rust (rustc) not configured in Buck2")
    elif [ "$SHELL_RUSTC" != "$BUCK2_RUSTC" ]; then
      ERRORS+=("Rust (rustc) path mismatch: shell=$SHELL_RUSTC buck2=$BUCK2_RUSTC")
    else
      echo "PASS: Rust (rustc) synchronized at $SHELL_RUSTC"
    fi

    SHELL_CARGO=$(which cargo 2>/dev/null || echo "")
    BUCK2_CARGO=$(buck2 audit config rust.cargo_bin 2>/dev/null || echo "")

    if [ -z "$SHELL_CARGO" ]; then
      ERRORS+=("Rust (cargo) not found in shell PATH")
    elif [ -z "$BUCK2_CARGO" ]; then
      ERRORS+=("Rust (cargo) not configured in Buck2")
    elif [ "$SHELL_CARGO" != "$BUCK2_CARGO" ]; then
      ERRORS+=("Rust (cargo) path mismatch: shell=$SHELL_CARGO buck2=$BUCK2_CARGO")
    else
      echo "PASS: Rust (cargo) synchronized at $SHELL_CARGO"
    fi
    ''}

    # Verify Python
    ${lib.optionalString config.languages.python.enable ''
    SHELL_PYTHON=$(which python 2>/dev/null || echo "")
    BUCK2_PYTHON=$(buck2 audit config python.python_bin 2>/dev/null || echo "")

    if [ -z "$SHELL_PYTHON" ]; then
      ERRORS+=("Python not found in shell PATH")
    elif [ -z "$BUCK2_PYTHON" ]; then
      ERRORS+=("Python not configured in Buck2")
    elif [ "$SHELL_PYTHON" != "$BUCK2_PYTHON" ]; then
      ERRORS+=("Python path mismatch: shell=$SHELL_PYTHON buck2=$BUCK2_PYTHON")
    else
      echo "PASS: Python synchronized at $SHELL_PYTHON"
    fi
    ''}

    # Verify Clang
    ${lib.optionalString (config.languages.c.enable || config.languages.cplusplus.enable) ''
    SHELL_CLANG=$(which clang 2>/dev/null || echo "")
    BUCK2_CLANG=$(buck2 audit config cxx.cc 2>/dev/null || echo "")

    if [ -z "$SHELL_CLANG" ]; then
      ERRORS+=("Clang not found in shell PATH")
    elif [ -z "$BUCK2_CLANG" ]; then
      ERRORS+=("Clang not configured in Buck2")
    elif [ "$SHELL_CLANG" != "$BUCK2_CLANG" ]; then
      ERRORS+=("Clang path mismatch: shell=$SHELL_CLANG buck2=$BUCK2_CLANG")
    else
      echo "PASS: Clang synchronized at $SHELL_CLANG"
    fi

    SHELL_CLANGXX=$(which clang++ 2>/dev/null || echo "")
    BUCK2_CLANGXX=$(buck2 audit config cxx.cxx 2>/dev/null || echo "")

    if [ -z "$SHELL_CLANGXX" ]; then
      ERRORS+=("Clang++ not found in shell PATH")
    elif [ -z "$BUCK2_CLANGXX" ]; then
      ERRORS+=("Clang++ not configured in Buck2")
    elif [ "$SHELL_CLANGXX" != "$BUCK2_CLANGXX" ]; then
      ERRORS+=("Clang++ path mismatch: shell=$SHELL_CLANGXX buck2=$BUCK2_CLANGXX")
    else
      echo "PASS: Clang++ synchronized at $SHELL_CLANGXX"
    fi
    ''}

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
{
  packages = [
    verifyScript
    diagnoseScript
    compareVersionsScript
    ciVerifyScript
  ];
}

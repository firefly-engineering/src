{ config, lib, pkgs, ... }:

let
  cfg = config.firefly.toolchains;

  # Load toolchain declarations from TOML file
  tomlContent = if builtins.pathExists cfg.declarationFile
    then builtins.readFile cfg.declarationFile
    else "";

  toolchainDeclarations = if tomlContent != ""
    then builtins.fromTOML tomlContent
    else {};

  # Load registry
  registry = import cfg.registry { inherit pkgs; };

  # Resolve a single toolchain entry
  resolveToolchain = name: spec:
    let
      version = spec.version or (throw "Missing version for toolchain '${name}'");
      toolchainRegistry = registry.${name} or (throw
        "Unknown toolchain '${name}'. Available toolchains: ${lib.concatStringsSep ", " (lib.attrNames registry)}"
      );
      derivation = toolchainRegistry.${version} or (throw
        "Unknown version '${version}' for toolchain '${name}'. " +
        "Available versions: ${lib.concatStringsSep ", " (lib.attrNames toolchainRegistry)}"
      );
    in
    derivation;

  # Resolve all declared toolchains
  resolved = lib.mapAttrs resolveToolchain toolchainDeclarations;

  # Extract derivations as list for shell
  toolchainPackages = lib.attrValues resolved;

  # Shell hook with version printing
  shellHook = lib.optionalString cfg.shell.showVersions ''
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
    ${lib.optionalString (resolved ? clang) ''
      echo "  Clang:  $(${resolved.clang}/bin/clang --version | head -n1 | cut -d' ' -f3)"
    ''}
    ${lib.optionalString (resolved ? gcc) ''
      echo "  GCC:    $(${resolved.gcc}/bin/gcc --version | head -n1 | cut -d' ' -f3)"
    ''}
    echo ""
    echo "ℹ️  Buck2 configs synchronized to same toolchains"
    echo ""
  '';

  # Verification script
  verifyScript = pkgs.writeScriptBin "verify-toolchains" ''
    #!/usr/bin/env bash
    echo "Verifying toolchain synchronization..."
    echo ""

    ${lib.optionalString (resolved ? go) ''
      GO_SHELL="$(which go 2>/dev/null || echo "not found")"
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
      RUSTC_SHELL="$(which rustc 2>/dev/null || echo "not found")"
      RUSTC_EXPECTED="${resolved.rust}/bin/rustc"
      if [ "$RUSTC_SHELL" = "$RUSTC_EXPECTED" ]; then
        echo "✅ Rust: $RUSTC_SHELL"
      else
        echo "❌ Rust mismatch!"
        echo "   Shell:    $RUSTC_SHELL"
        echo "   Expected: $RUSTC_EXPECTED"
      fi
    ''}

    ${lib.optionalString (resolved ? python) ''
      PYTHON_SHELL="$(which python 2>/dev/null || echo "not found")"
      PYTHON_EXPECTED="${resolved.python}/bin/python"
      if [ "$PYTHON_SHELL" = "$PYTHON_EXPECTED" ]; then
        echo "✅ Python: $PYTHON_SHELL"
      else
        echo "❌ Python mismatch!"
        echo "   Shell:    $PYTHON_SHELL"
        echo "   Expected: $PYTHON_EXPECTED"
      fi
    ''}

    ${lib.optionalString (resolved ? clang) ''
      CLANG_SHELL="$(which clang 2>/dev/null || echo "not found")"
      CLANG_EXPECTED="${resolved.clang}/bin/clang"
      if [ "$CLANG_SHELL" = "$CLANG_EXPECTED" ]; then
        echo "✅ Clang: $CLANG_SHELL"
      else
        echo "❌ Clang mismatch!"
        echo "   Shell:    $CLANG_SHELL"
        echo "   Expected: $CLANG_EXPECTED"
      fi
    ''}

    ${lib.optionalString (resolved ? gcc) ''
      GCC_SHELL="$(which gcc 2>/dev/null || echo "not found")"
      GCC_EXPECTED="${resolved.gcc}/bin/gcc"
      if [ "$GCC_SHELL" = "$GCC_EXPECTED" ]; then
        echo "✅ GCC: $GCC_SHELL"
      else
        echo "❌ GCC mismatch!"
        echo "   Shell:    $GCC_SHELL"
        echo "   Expected: $GCC_EXPECTED"
      fi
    ''}
  '';
in
{
  options.firefly.toolchains = {
    registry = lib.mkOption {
      type = lib.types.path;
      default = ./registry-default.nix;
      description = "Path to toolchain registry file";
    };

    declarationFile = lib.mkOption {
      type = lib.types.path;
      default = ./../../toolchain.toml;
      description = "Path to toolchain.toml declaration file";
    };

    resolved = lib.mkOption {
      type = lib.types.attrs;
      internal = true;
      description = "Resolved toolchain derivations (internal use)";
    };

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

    buck2 = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Buck2 config generation";
      };
    };
  };

  config = lib.mkIf (toolchainDeclarations != {}) {
    # Expose resolved toolchains for internal use
    firefly.toolchains.resolved = resolved;

    # Extend devenv shell configuration if shell integration is enabled
    devenv.shells.default = lib.mkIf cfg.shell.enable {
      packages = toolchainPackages ++ cfg.shell.extraPackages ++ [ verifyScript ];

      enterShell = lib.mkBefore shellHook;
    };
  };
}

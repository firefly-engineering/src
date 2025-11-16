# Firefly Toolchains Flake Module
#
# This module provides a reusable mechanism for toolchain synchronization between
# Nix development shells and Buck2 builds. It defines configuration options for:
# - Toolchain declaration files (toolchain.toml)
# - Toolchain registries (mapping versions to Nix derivations)
# - Buck2 configuration generation
#
# Design Principles:
# - Single Source of Truth: Both shell and Buck2 derive from same configuration
# - Registry-Based Resolution: toolchain.toml + registry → concrete Nix derivations
# - Content-Addressed Binaries: Nix store paths ensure automatic cache invalidation
# - Modular Design: Self-contained code ready for extraction to turnkey repository
#
# Usage Example:
#   imports = [ firefly-toolchains.flakeModules.toolchains ];
#
#   firefly.toolchains = {
#     registry = ./my-custom-registry.nix;  # Or use default
#     declarationFile = ./toolchain.toml;
#     buck2.enable = true;
#   };

{ config, lib, pkgs, ... }:

let
  cfg = config.firefly.toolchains;
in
{
  options.firefly.toolchains = {
    registry = lib.mkOption {
      type = lib.types.path;
      default = ./registry-default.nix;
      description = ''
        Path to toolchain registry file.

        The registry maps toolchain names and versions to Nix derivations.
        It should export a function that takes nixpkgs and returns an attrset
        mapping toolchain identifiers to derivations.

        Example registry structure:
          { pkgs }: {
            rust."1.75.0" = pkgs.rust-bin.stable."1.75.0".default;
            go."1.21.0" = pkgs.go_1_21;
          }
      '';
    };

    declarationFile = lib.mkOption {
      type = lib.types.path;
      default = ./toolchain.toml;
      description = ''
        Path to toolchain.toml declaration file.

        This file declares which toolchains and versions are required for
        the project. The format follows the toolchain declaration spec:

          [toolchains]
          rust = "1.75.0"
          go = "1.21.0"

        The declaration file is the single source of truth for toolchain
        requirements, used to generate both Nix shells and Buck2 configs.
      '';
    };

    buck2 = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Enable Buck2 configuration generation.

          When enabled, the module will generate Buck2 toolchain configuration
          files based on the declared toolchains. This includes:
          - .buckconfig entries pointing to Nix store paths
          - Platform-specific toolchain configurations
          - Cache invalidation based on content-addressed binaries
        '';
      };

      configPath = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Optional path where Buck2 configuration should be written.
          If null, configuration will be available via module outputs
          but not written to filesystem.
        '';
      };
    };

    shell = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Enable development shell environment generation.

          When enabled, toolchains will be made available in the Nix
          development shell environment.
        '';
      };
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = ''
        Additional packages to include in the development environment
        beyond the declared toolchains.
      '';
    };
  };

  config = {
    # Implementation will be added in subsequent tasks:
    # - Phase 0.3: Resolution logic (toolchain.toml + registry → derivations)
    # - Phase 0.4: Shell integration
    # - Phase 0.5: Buck2 config generation

    # For now, this module defines only the interface.
    # Downstream modules can import this without errors, but functionality
    # will be added incrementally.
  };
}

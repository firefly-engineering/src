{ config, lib, pkgs, ... }:

let
  cfg = config.firefly.toolchains;

  # Load toolchain declarations from TOML file
  toolchainDeclarations =
    if builtins.pathExists cfg.declarationFile then
      builtins.fromTOML (builtins.readFile cfg.declarationFile)
    else
      throw ''
        Toolchain declaration file not found: ${toString cfg.declarationFile}

        Create a toolchain.toml file with:
          [go]
          version = "1.21.5"

          [rust]
          version = "1.75.0"

        See documentation for more details.
      '';

  # Load registry
  registry = import cfg.registry { inherit pkgs; };

  # Validate a single toolchain entry
  validateToolchain = name: spec:
    let
      checks = {
        hasVersion = spec ? version;
        toolchainExists = registry ? ${name};
        versionExists =
          if (registry ? ${name}) && (spec ? version)
          then (registry.${name} or {}) ? ${spec.version}
          else false;
      };
    in
    if !checks.hasVersion then
      throw ''
        Toolchain '${name}' is missing required 'version' field in ${toString cfg.declarationFile}

        Example:
          [${name}]
          version = "..."
      ''
    else if !checks.toolchainExists then
      throw ''
        Unknown toolchain '${name}' in ${toString cfg.declarationFile}

        Available toolchains: ${lib.concatStringsSep ", " (lib.attrNames registry)}

        Check your toolchain.toml configuration.
      ''
    else if !checks.versionExists then
      throw ''
        Unknown version '${spec.version}' for toolchain '${name}'

        Available versions: ${lib.concatStringsSep ", " (lib.attrNames registry.${name})}

        Update your toolchain.toml to use one of the available versions.
      ''
    else
      true;

  # Resolve a single toolchain entry
  resolveToolchain = name: spec:
    let
      version = spec.version or (throw "Missing version for toolchain '${name}'");
      toolchainRegistry = registry.${name} or (throw "Unknown toolchain '${name}'");
      derivation = toolchainRegistry.${version} or (throw
        "Unknown version '${version}' for toolchain '${name}'. " +
        "Available versions: ${lib.concatStringsSep ", " (lib.attrNames toolchainRegistry)}"
      );
    in
    derivation;

  # Validate all toolchains before resolving
  validated = lib.all
    (name: validateToolchain name toolchainDeclarations.${name})
    (lib.attrNames toolchainDeclarations);

  # Resolve all declared toolchains
  # Only computed if validation passes
  resolvedToolchains =
    if validated
    then lib.mapAttrs resolveToolchain toolchainDeclarations
    else {};

in
{
  options.firefly.toolchains = {
    registry = lib.mkOption {
      type = lib.types.path;
      default = ./registry-default.nix;
      description = ''
        Path to toolchain registry file.
        The registry maps version strings to Nix derivations.

        Example: { go."1.21.5" = pkgs.go_1_21; }
      '';
    };

    declarationFile = lib.mkOption {
      type = lib.types.path;
      default = ./toolchain.toml;
      description = ''
        Path to toolchain.toml declaration file.
        This file declares which toolchain versions to use.

        Example:
          [go]
          version = "1.21.5"
      '';
    };

    buck2 = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Buck2 config generation";
      };
    };

    resolved = lib.mkOption {
      type = lib.types.attrs;
      internal = true;
      description = "Resolved toolchain derivations (internal use)";
      readOnly = true;
      default = resolvedToolchains;
    };
  };

  config = {
    # The resolved toolchains are available via cfg.resolved
    # This will be used by shell and Buck2 generators in future phases
  };
}

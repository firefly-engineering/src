{ config, lib, pkgs, ... }:

let
  cfg = config.firefly.toolchains;

  # Helper function to parse TOML with error handling
  parseToml = path:
    let
      content = builtins.readFile path;
      parsed = builtins.tryEval (builtins.fromTOML content);
    in
    if parsed.success then
      parsed.value
    else
      throw ''
        Failed to parse TOML file: ${toString path}

        The file contains syntax errors. Common issues:
        - Missing quotes around strings
        - Unclosed brackets
        - Invalid section headers

        Example of valid syntax:

          [go]
          version = "1.21.5"

          [rust]
          version = "1.75.0"

        TOML specification: https://toml.io/

        Error from parser:
        ${builtins.toString parsed}
      '';

  # Helper function to validate toolchain specification
  validateToolchainSpec = declarationPath: name: spec:
    let
      checks = {
        isAttrs = builtins.isAttrs spec;
        hasVersion = spec ? version;
        versionIsString = builtins.isString (spec.version or "");
      };

      errors = lib.optional (!checks.isAttrs)
        "Toolchain '${name}' must be a table/section"
        ++ lib.optional (!checks.hasVersion)
        "Toolchain '${name}' is missing required 'version' field"
        ++ lib.optional (!checks.versionIsString)
        "Toolchain '${name}' version must be a string, got: ${builtins.typeOf spec.version}";
    in
    if errors == [] then
      spec
    else
      throw ''
        Invalid configuration for toolchain '${name}' in ${toString declarationPath}

        ${lib.concatStringsSep "\n" errors}

        Example of correct format:

          [${name}]
          version = "1.0.0"
      '';

  # Helper function to load registry with error handling
  loadRegistry = registryPath:
    if builtins.pathExists registryPath then
      import registryPath { inherit pkgs; }
    else
      throw ''
        Registry file not found: ${toString registryPath}

        To fix this:
        - Check the path is correct
        - Use default registry: remove firefly.toolchains.registry option
        - Create registry file at ${toString registryPath}

        See: docs/src/user-guide/custom-registry.md
      '';

  # Helper function to validate registry structure
  validateRegistry = registry:
    if !builtins.isAttrs registry then
      throw ''
        Invalid registry format: expected attribute set, got ${builtins.typeOf registry}

        Registry must be an attribute set like:

          { pkgs }: {
            go = {
              "1.21.5" = pkgs.go_1_21;
            };
          }
      ''
    else
      lib.mapAttrs (name: versions:
        if !builtins.isAttrs versions then
          throw "Invalid registry entry '${name}': versions must be an attribute set"
        else
          versions
      ) registry;

  # Load and parse toolchain declaration file
  declarationPath = cfg.declarationFile;

  toolchainDeclarations =
    if builtins.pathExists declarationPath then
      let
        parsed = parseToml declarationPath;
        validated = lib.mapAttrs (validateToolchainSpec declarationPath) parsed;
      in
      validated
    else
      throw ''
        Toolchain declaration file not found: ${toString declarationPath}

        To fix this, create a toolchain.toml file:

          cat > toolchain.toml <<EOF
          [go]
          version = "1.21.5"
          EOF

        Or specify a different path:

          firefly.toolchains.declarationFile = ./path/to/toolchain.toml;

        See: docs/src/user-guide/getting-started.md
      '';

  # Load and validate registry
  rawRegistry = loadRegistry cfg.registry;
  registry = validateRegistry rawRegistry;

  # Helper function to provide hints for common mistakes
  provideHints = declarations: registry:
    let
      hints = lib.flatten (lib.mapAttrsToList (name: spec:
        let
          version = spec.version or "";
          available = lib.attrNames (registry.${name} or {});

          # Check for close matches (e.g., "1.21" vs "1.21.5")
          similarVersions = lib.filter (v: lib.hasPrefix version v) available;
        in
        lib.optional (similarVersions != [] && !(lib.elem version available)) ''
          💡 Hint: '${name}' version '${version}' not found, but these similar versions exist:
            ${lib.concatStringsSep "\n  " similarVersions}
        ''
      ) declarations);
    in
    if hints != [] then
      builtins.trace (lib.concatStringsSep "\n\n" hints)
    else
      lib.id;

  # Helper function to resolve a single toolchain with comprehensive error handling
  resolveToolchain = name: spec:
    let
      version = spec.version or (throw
        "Toolchain '${name}' is missing required 'version' field in ${toString declarationPath}"
      );

      toolchainRegistry = registry.${name} or (throw ''
        Unknown toolchain '${name}' in ${toString declarationPath}

        Available toolchains in registry:
          ${lib.concatStringsSep "\n  " (lib.attrNames registry)}

        Either:
        - Fix the toolchain name in toolchain.toml
        - Add '${name}' to your custom registry
      '');

      derivation = toolchainRegistry.${version} or (throw ''
        Unknown version '${version}' for toolchain '${name}'

        Available versions for '${name}':
          ${lib.concatStringsSep "\n  " (lib.sort lib.lessThan (lib.attrNames toolchainRegistry))}

        Fix this by:
        - Using an available version in toolchain.toml
        - Adding '${version}' to your registry:

            ${name}."${version}" = pkgs.your-package;

        See: docs/src/user-guide/custom-registry.md
      '');

      # Try to evaluate the derivation to catch obvious errors early
      checked = builtins.tryEval derivation.outPath or derivation;
    in
    if checked.success then
      derivation
    else
      throw ''
        Failed to resolve toolchain '${name}' version '${version}'

        The derivation exists in the registry but cannot be built.
        This may indicate:
        - Incompatible system architecture
        - Missing dependencies
        - Broken package in nixpkgs

        Try:
        - Using a different version
        - Updating nixpkgs
        - Checking nixpkgs issues: https://github.com/NixOS/nixpkgs/issues

        Technical details:
        ${builtins.toString checked}
      '';

  # Resolve all toolchains with hints
  resolvedToolchains = provideHints toolchainDeclarations registry (
    lib.mapAttrs resolveToolchain toolchainDeclarations
  );

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
      default = ./toolchain.toml;
      description = "Path to toolchain.toml declaration file";
    };

    buck2 = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Buck2 config generation";
      };

      outputPath = lib.mkOption {
        type = lib.types.path;
        default = ./toolchains;
        description = "Path where Buck2 toolchain files will be generated";
      };
    };
  };

  config = lib.mkIf (cfg.declarationFile != null) {
    # Make resolved toolchains available for other parts of the config
    # This will be used by shell generation and Buck2 generation in future tasks
    _module.args.resolvedToolchains = resolvedToolchains;
  };
}

{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    {
      # Configure turnkey toolchain management
      turnkey.toolchains = {
        enable = true;
        tellerLib = inputs.teller.lib;
        tellerRegistry =
          let
            overlaidPkgs = import inputs.nixpkgs {
              inherit system;
              overlays = [
                inputs.teller.overlays.default
                inputs.toolbox.overlays.default
              ];
            };
          in
          overlaidPkgs.turnkeyRegistry;
        declarationFiles = {
          default = ../toolchain.toml;
        };
        registryExtensions = { };

        # Enable Buck2 toolchain generation
        buck2 = {
          enable = true;
          welcomeMessage = "Welcome to Firefly Engineering Monorepo";

          # Go dependencies
          go = {
            enable = true;
            depsFile = ../go-deps.toml;
          };

          # Rust dependencies
          rust = {
            enable = true;
            depsFile = ../rust-deps.toml;
          };

          # mdbook preprocessors (from toolbox's mdbook-toolchain, version-compatible)
          mdbook.preprocessors = let
            overlaidPkgs = import inputs.nixpkgs {
              inherit system;
              overlays = [
                inputs.teller.overlays.default
                inputs.toolbox.overlays.default
              ];
            };
            registry = overlaidPkgs.turnkeyRegistry;
            resolve = name: inputs.teller.lib.resolveTool registry name {};
          in [
            (resolve "mdbook-admonish")
            (resolve "mdbook-footnote")
            (resolve "mdbook-graphviz")
            (resolve "mdbook-mermaid")
          ];
        };
      };

      # Additional devenv shell configuration (agents, devcontainer)
      devenv.shells.default = {
        imports = [
          ./devenv/agents.nix
          ./devenv/devcontainer.nix
        ];
      };
    };
}

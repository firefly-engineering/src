{ ... }:
{
  perSystem = _: {
    # Configure turnkey toolchain management.
    # tellerLib + tellerRegistry default to turnkey's bundled teller + toolbox.
    turnkey.toolchains = {
      enable = true;
      declarationFiles.default = ../toolchain.toml;

      buck2 = {
        enable = true;
        welcomeMessage = "Welcome to Firefly Engineering Monorepo";

        go.enable = true;
        go.depsFile = ../go-deps.toml;

        rust.enable = true;
        rust.depsFile = ../rust-deps.toml;
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

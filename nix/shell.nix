{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      devenv.shells.default = {
        imports = [
          ./devenv/agents.nix
          ./devenv/devcontainer.nix
          ./devenv/languages.nix
          ./devenv/packages.nix
        ];

        enterShell = ''
          echo "🚀 Welcome to Firefly Engineering Monorepo"
        '';
      };
    };
}

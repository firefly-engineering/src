{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      devenv.shells.default = {
        imports = [
          ./devenv
        ];

        enterShell = ''
          echo "🚀 Welcome to Firefly Engineering Monorepo"
        '';
      };
    };
}

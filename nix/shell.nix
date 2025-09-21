{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      devenv.shells.default = {
        imports = [ ./devenv/agents.nix ];

        enterShell = ''
          echo "🚀 Welcome to Firefly Engineering Monorepo"
        '';

        claude.code = {
          enable = true;
        };

        languages = {
          cplusplus.enable = true;
          go.enable = true;
          jsonnet.enable = true;
          nix.enable = true;
          python.enable = true;
          rust.enable = true;
          shell.enable = true;
        };

        packages = with pkgs; [
          # build
          buck2
          nix
          # documentation
          mdbook
          # version control
          git
          jujutsu
        ];
      };
    };
}

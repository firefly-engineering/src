{
  description = "Firefly Engineering Monorepo";

  inputs = {
    nix-pins.url = "github:firefly-engineering/nix-pins";
    nixpkgs.follows = "nix-pins/nixpkgs";
    flake-parts.follows = "nix-pins/flake-parts";

    turnkey = {
      url = "github:firefly-engineering/turnkey";
      inputs.nix-pins.follows = "nix-pins";
    };

    devenv.follows = "turnkey/toolbox/devenv";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      imports = [
        inputs.devenv.flakeModule
        inputs.turnkey.flakeModules.turnkey
        ./nix
      ];
    };
}

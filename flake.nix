{
  description = "Firefly Engineering Monorepo";

  inputs = {
    nix-pins.url = "github:firefly-engineering/nix-pins";
    nixpkgs.follows = "nix-pins/nixpkgs";
    flake-parts.follows = "nix-pins/flake-parts";

    teller = {
      url = "github:firefly-engineering/teller";
      inputs.nix-pins.follows = "nix-pins";
    };

    toolbox = {
      url = "github:firefly-engineering/toolbox";
      inputs.nix-pins.follows = "nix-pins";
      inputs.teller.follows = "teller";
    };

    turnkey = {
      url = "github:firefly-engineering/turnkey";
      inputs.nix-pins.follows = "nix-pins";
      inputs.teller.follows = "teller";
      inputs.toolbox.follows = "toolbox";
    };

    devenv.follows = "toolbox/devenv";
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

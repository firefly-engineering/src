{
  description = "Firefly Engineering Monorepo";

  inputs = {
    # Pin nixpkgs to same rev as turnkey for compatibility
    nixpkgs.url = "github:NixOS/nixpkgs/e4bae1bd10c9c57b2cf517953ab70060a828ee6f";
    flake-parts.url = "github:hercules-ci/flake-parts/80daad04eddbbf5a4d883996a73f3f542fa437ac";
    devenv.url = "github:cachix/devenv/9bfc4a64c3a798ed8fa6cee3a519a9eac5e73cb5";
    nix2container = {
      url = "github:nlewo/nix2container/66f4b8a47e92aa744ec43acbb5e9185078983909";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Turnkey toolchain management
    turnkey = {
      url = "github:firefly-engineering/turnkey";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.devenv.follows = "devenv";
      inputs.nix2container.follows = "nix2container";
    };

    # Teller - versioned toolchain registry library
    teller = {
      url = "github:firefly-engineering/teller";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Toolbox - package registry (provides beads, jj, go, rust, etc.)
    toolbox = {
      url = "github:firefly-engineering/toolbox";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.teller.follows = "teller";
    };
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

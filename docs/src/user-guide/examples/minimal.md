# Example: Minimal Setup

Simplest possible configuration with just Go.

## flake.nix

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    firefly-toolchains.url = "github:firefly-engineering/src";
  };

  outputs = { self, nixpkgs, firefly-toolchains }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        imports = [ firefly-toolchains.flakeModules.toolchains ];
      };
    };
}
```

## toolchain.toml

```toml
[go]
version = "1.21.5"
```

## Test

```bash
nix develop
go version  # go version go1.21.5 linux/amd64
```

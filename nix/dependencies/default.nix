{ ... }:
{
  perSystem = { lib, pkgs, ... }: {
    packages = {
      # Go module dependencies in pkg/mod format
      goDependencies = import ./go-dependencies.nix { inherit lib pkgs; };

      # GOPROXY-compatible filesystem layout
      goProxyFilesystem = import ./go-proxy-filesystem.nix { inherit lib pkgs; };
    };
  };
}
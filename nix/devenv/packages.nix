{ pkgs, ... }:
{
  packages = with pkgs; [
    # build
    buck2
    nix

    # documentation
    mdbook

    # development
    fswatch

    # version control
    git
    jujutsu
  ];
}

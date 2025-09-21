{ pkgs, ... }:
{
  packages = with pkgs; [
    # build
    buck2
    nix

    # documentation
    mdbook
    mdbook-admonish
    mdbook-footnote
    mdbook-graphviz
    mdbook-linkcheck
    mdbook-mermaid

    # development
    fswatch

    # version control
    git
    jujutsu
  ];
}

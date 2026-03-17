{ pkgs, ... }:
{
  packages = with pkgs; [
    # build
    buck2
    nix

    # documentation
    graphviz
    mdbook
    mdbook-admonish
    mdbook-footnote
    mdbook-graphviz
    mdbook-linkcheck2
    mdbook-mermaid

    # development
    fswatch

    # version control
    git
    jujutsu
  ];
}

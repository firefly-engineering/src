{ config, lib, ... }:
{
  devcontainer.enable = true;

  devcontainer.settings.customizations.vscode.extensions = [
    "mkhl.direnv"
    "phgn.vscode-starlark"
    "tamasfe.even-better-toml"
    "redhat.vscode-yaml"
  ]
  ++ lib.optionals config.languages.go.enable [
    "golang.go"
  ]
  ++ lib.optionals config.languages.rust.enable [
    "rust-lang.rust-analyzer"
    "dustypomerleau.rust-syntax"
  ]
  ++ lib.optionals config.languages.jsonnet.enable [
    "Grafana.vscode-jsonnet"
  ]
  ++ lib.optionals config.languages.nix.enable [
    "jnoortheen.nix-ide"
  ];
}

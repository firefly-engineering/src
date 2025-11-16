{ pkgs }:

# Default toolchain registry
# This provides a curated set of toolchain versions for common languages
#
# Each toolchain maps version strings to Nix derivations:
#   toolchain-name = {
#     "version-string" = <derivation>;
#   };
#
# Derivations can be:
# - Direct package references: pkgs.go_1_21
# - Customized packages with patches: pkgs.go_1_21.overrideAttrs (...)
# - Custom builds with specific options
#
# This registry can be overridden by setting:
#   firefly.toolchains.registry = ./my-custom-registry.nix;

{
  # Go toolchains
  go = {
    "1.21.5" = pkgs.go_1_21;
    "1.22.0" = pkgs.go_1_22;
    "1.22.1" = pkgs.go_1_22;
  };

  # Rust toolchains
  rust = {
    "1.75.0" = pkgs.rustc;
    "1.76.0" = pkgs.rustc;
  };

  # Python toolchains
  python = {
    "3.11" = pkgs.python311;
    "3.12" = pkgs.python312;
  };

  # Node.js toolchains
  nodejs = {
    "18" = pkgs.nodejs_18;
    "20" = pkgs.nodejs_20;
    "21" = pkgs.nodejs_21;
  };
}

# Default Toolchain Registry
#
# This file maps toolchain names and versions to Nix derivations.
# It serves as the default registry when users don't provide a custom one.
#
# Structure:
#   { pkgs }: {
#     "<toolchain-name>"."<version>" = <derivation>;
#   }
#
# The registry is queried during toolchain resolution to convert
# declarative requirements (from toolchain.toml) into concrete
# Nix store paths for both shells and Buck2 builds.
#
# This is a stub that will be implemented in Phase 0.2.

{ pkgs }:

{
  # Stub registry - will be populated with actual toolchains in Phase 0.2
  # Example structure (to be implemented):
  #
  # rust = {
  #   "1.75.0" = pkgs.rust-bin.stable."1.75.0".default;
  # };
  #
  # go = {
  #   "1.21.0" = pkgs.go_1_21;
  # };
}

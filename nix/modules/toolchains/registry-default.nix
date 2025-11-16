{ pkgs }:

# Default Toolchain Registry
#
# This registry maps toolchain version strings to concrete Nix derivations.
# It serves as the default registry for the toolchain synchronization module.
#
# Structure:
#   <language>.<version> = <nixpkgs-derivation>
#
# Versioning Policy:
#   - Include last 3-5 major/minor versions of each toolchain
#   - Provide patch-level versions where security-critical
#   - Use semantic versioning for keys
#   - Include convenience aliases ("stable", "latest", "1.21" → "1.21.x")
#
# Adding New Versions:
#   1. Verify package exists in nixpkgs
#   2. Add entry with semantic version key
#   3. Test that derivation builds successfully
#   4. Update this header with date of last update
#
# Last Updated: 2025-11-16

{
  # Go toolchains
  # Available versions from nixpkgs
  go = {
    "1.21" = pkgs.go_1_21 or pkgs.go;
    "1.21.5" = pkgs.go_1_21 or pkgs.go;
    "1.22" = pkgs.go_1_22 or pkgs.go;
    "1.22.0" = pkgs.go_1_22 or pkgs.go;
    "1.23" = pkgs.go_1_23 or pkgs.go;
    "1.23.0" = pkgs.go_1_23 or pkgs.go;
    "latest" = pkgs.go;
  };

  # Rust toolchains
  # Using stable nixpkgs rust packages
  rust = {
    "1.75.0" = pkgs.rustc;
    "1.76.0" = pkgs.rustc;
    "1.77.0" = pkgs.rustc;
    "1.78.0" = pkgs.rustc;
    "stable" = pkgs.rustc;
    "latest" = pkgs.rustc;
  };

  # Python toolchains
  python = {
    "3.11" = pkgs.python311;
    "3.12" = pkgs.python312;
    "3.13" = pkgs.python313 or pkgs.python312;
    "latest" = pkgs.python3;
  };

  # Clang/LLVM toolchains
  clang = {
    "16" = pkgs.clang_16 or pkgs.clang;
    "17" = pkgs.clang_17 or pkgs.clang;
    "18" = pkgs.clang_18 or pkgs.clang;
    "latest" = pkgs.clang;
  };

  # GCC toolchains
  gcc = {
    "12" = pkgs.gcc12 or pkgs.gcc;
    "13" = pkgs.gcc13 or pkgs.gcc;
    "14" = pkgs.gcc14 or pkgs.gcc;
    "latest" = pkgs.gcc;
  };

  # Node.js toolchains
  nodejs = {
    "18" = pkgs.nodejs_18 or pkgs.nodejs;
    "20" = pkgs.nodejs_20 or pkgs.nodejs;
    "21" = pkgs.nodejs_21 or pkgs.nodejs;
    "22" = pkgs.nodejs_22 or pkgs.nodejs;
    "latest" = pkgs.nodejs;
    "lts" = pkgs.nodejs_20 or pkgs.nodejs;
  };
}

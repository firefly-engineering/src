{ pkgs }:

# Default Toolchain Registry
#
# This registry maps toolchain version strings to concrete Nix derivations.
# It serves as the default registry for the toolchain synchronization module.
#
# Purpose:
#   - Provide a mapping from semantic version strings to nixpkgs derivations
#   - Enable consistent toolchain usage across development shells and Buck2
#   - Allow downstream repositories to override or extend with custom versions
#
# Architecture:
#   toolchain.toml         registry.nix              Resolved Derivations
#   ─────────────          ────────────              ────────────────────
#   [go]                   "1.21.5" → pkgs.go_1_21   /nix/store/abc123-go-1.21.5
#   version = "1.21.5" ──→ "1.22.0" → pkgs.go_1_22   /nix/store/def456-go-1.22.0
#
#   Both the development shell and Buck2 use the SAME resolved derivation.
#
# Structure:
#   {
#     <language>.<version> = <nixpkgs-derivation>;
#   }
#
# Versioning Policy:
#   - Include last 3-5 major/minor versions of each toolchain
#   - Provide patch-level versions where security-critical
#   - Use semantic versioning for keys (e.g., "1.21.5", not "go_1_21")
#   - Include convenience aliases where helpful:
#     * "stable" → latest stable version
#     * "latest" → most recent version
#     * "1.21" → latest 1.21.x patch version
#
# Adding New Versions:
#   1. Verify package exists in nixpkgs (check nixpkgs documentation)
#   2. Add entry with semantic version string as key
#   3. Test that derivation builds successfully
#   4. Update "Last Updated" date below
#
# Overriding Registry:
#   Downstream repositories can override or extend this registry:
#
#   # Complete override
#   firefly.toolchains.registry = ./my-custom-registry.nix;
#
#   # Extend default registry
#   firefly.toolchains.registry = lib.attrsets.recursiveUpdate
#     (import firefly-toolchains.defaultRegistry { inherit pkgs; })
#     {
#       go."1.24.0" = pkgs.go_1_24;  # Add custom version
#     };
#
# Future:
#   This registry will be extracted to a separate repository
#   (firefly-engineering/toolchain-registry) for community maintenance.
#
# Last Updated: 2025-01-16

{
  # Go toolchains
  # Available in nixpkgs as pkgs.go_1_XX
  # https://nixos.org/manual/nixpkgs/stable/#sec-language-go
  go = {
    "1.21.5" = pkgs.go_1_21;
    "1.21" = pkgs.go_1_21;      # Alias for latest 1.21.x
    "1.22.0" = pkgs.go_1_22;
    "1.22" = pkgs.go_1_22;      # Alias for latest 1.22.x
    "1.23.0" = pkgs.go_1_23;
    "1.23" = pkgs.go_1_23;      # Alias for latest 1.23.x
    "latest" = pkgs.go;         # Latest stable Go
  };

  # Rust toolchains
  # Using stable nixpkgs Rust packages
  # NOTE: For specific version control, use fenix overlay or rust-overlay
  # Standard nixpkgs provides the latest stable Rust toolchain
  # https://nixos.org/manual/nixpkgs/stable/#rust
  rust = {
    # Standard nixpkgs Rust (latest stable)
    "stable" = pkgs.rustc;
    "latest" = pkgs.rustc;

    # Rust with additional components
    # These provide the complete Rust toolchain including cargo, rustfmt, etc.
    "stable-full" = pkgs.rust;

    # Note: For specific versions like "1.75.0", "1.76.0", etc.,
    # use fenix overlay or rust-overlay:
    #   inputs.fenix.packages.${system}.stable.toolchain
    # This will be added in future phases when overlay support is implemented.
  };

  # Python toolchains
  # Available as pkgs.python3XX
  # https://nixos.org/manual/nixpkgs/stable/#python
  python = {
    "3.11" = pkgs.python311;
    "3.12" = pkgs.python312;
    "3.13" = pkgs.python313;
    "latest" = pkgs.python3;    # Latest stable Python 3
  };

  # Clang/LLVM toolchains
  # Available as pkgs.clang_XX or pkgs.llvmPackages_XX.clang
  # https://nixos.org/manual/nixpkgs/stable/#sec-language-c
  clang = {
    "16" = pkgs.clang_16;
    "17" = pkgs.clang_17;
    "18" = pkgs.clang_18;
    "latest" = pkgs.clang;      # Latest stable Clang
  };

  # GCC toolchains
  # Available as pkgs.gccXX
  # https://nixos.org/manual/nixpkgs/stable/#sec-language-c
  gcc = {
    "12" = pkgs.gcc12;
    "13" = pkgs.gcc13;
    "14" = pkgs.gcc14;
    "latest" = pkgs.gcc;        # Latest stable GCC
  };
}

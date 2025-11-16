{ pkgs }:

{
  # Go toolchains
  # Maps version strings to nixpkgs Go derivations
  go = {
    "1.21" = pkgs.go_1_21;
    "1.21.5" = pkgs.go_1_21;
    "1.22" = pkgs.go_1_22;
    "1.22.0" = pkgs.go_1_22;
    "1.23" = pkgs.go_1_23;
    "1.23.0" = pkgs.go_1_23;
    "latest" = pkgs.go;
  };

  # Rust toolchains
  # Uses stable Rust from nixpkgs
  rust = {
    "1.75" = pkgs.rustc;
    "1.75.0" = pkgs.rustc;
    "1.76" = pkgs.rustc;
    "1.76.0" = pkgs.rustc;
    "1.77" = pkgs.rustc;
    "1.77.0" = pkgs.rustc;
    "1.78" = pkgs.rustc;
    "1.78.0" = pkgs.rustc;
    "1.79" = pkgs.rustc;
    "1.79.0" = pkgs.rustc;
    "1.80" = pkgs.rustc;
    "1.80.0" = pkgs.rustc;
    "1.81" = pkgs.rustc;
    "1.81.0" = pkgs.rustc;
    "stable" = pkgs.rustc;
    "latest" = pkgs.rustc;
  };

  # Python toolchains
  python = {
    "3.10" = pkgs.python310;
    "3.11" = pkgs.python311;
    "3.12" = pkgs.python312;
    "3.13" = pkgs.python313;
    "latest" = pkgs.python3;
  };

  # Clang/LLVM toolchains
  clang = {
    "16" = pkgs.clang_16;
    "17" = pkgs.clang_17;
    "18" = pkgs.clang_18;
    "19" = pkgs.clang_19;
    "latest" = pkgs.clang;
  };

  # GCC toolchains
  gcc = {
    "11" = pkgs.gcc11;
    "12" = pkgs.gcc12;
    "13" = pkgs.gcc13;
    "14" = pkgs.gcc14;
    "latest" = pkgs.gcc;
  };
}

{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          git
          jujutsu
          nix
          buck2
          go
          rustc
          cargo
          rust-analyzer
          rustfmt
          clippy
          python3
          llvm
        ];
      };
    };
}

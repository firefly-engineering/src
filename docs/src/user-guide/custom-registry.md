# Custom Toolchain Registry

## Registry Structure

A registry maps version strings to Nix derivations:

```nix
{ pkgs }:
{
  <toolchain-name> = {
    "<version-string>" = <nix-derivation>;
  };
}
```

## Creating a Custom Registry

### Option 1: From Scratch

```nix
# my-registry.nix
{ pkgs }:
{
  go = {
    "1.21.5" = pkgs.go_1_21;
    "1.24.0" = pkgs.go_1_24;  # Custom version
  };

  rust = {
    "custom" = pkgs.rust.override {
      # Custom Rust with specific configuration
    };
  };
}
```

Use it:
```nix
firefly.toolchains.registry = ./my-registry.nix;
```

### Option 2: Extend Default Registry

```nix
# additions.nix
{ pkgs, defaultRegistry }:

lib.recursiveUpdate defaultRegistry {
  go."1.24.0" = pkgs.go_1_24;  # Add new version

  myCustomTool."1.0.0" = pkgs.myTool;  # Add new toolchain
}
```

## Adding Patches

```nix
{ pkgs }:
{
  go = {
    "1.21.5-patched" = pkgs.go_1_21.overrideAttrs (old: {
      patches = (old.patches or []) ++ [
        ./patches/go-security-fix.patch
      ];
    });
  };
}
```

Use in `toolchain.toml`:
```toml
[go]
version = "1.21.5-patched"
```

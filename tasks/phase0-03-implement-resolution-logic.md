# Phase 0.3: Implement Toolchain Resolution Logic

## Overview

Implement the core resolution mechanism that reads `toolchain.toml`, queries the registry, and resolves version strings to concrete Nix derivations. This is the heart of the toolchain synchronization system.

## Context

The resolution logic connects three components:

1. **Input**: `toolchain.toml` (high-level declaration)
2. **Transform**: Registry lookup (version → derivation)
3. **Output**: Resolved derivations (for shell + Buck2)

### Resolution Flow

```
toolchain.toml                Registry                  Resolved Set
──────────────                ────────                  ────────────
[go]                          go."1.21.5" = ...         {
version = "1.21.5"    ──┐                                 go = /nix/store/abc-go-1.21.5;
                        ├──→  LOOKUP  ──────────────→     rust = /nix/store/xyz-rust-1.75.0;
[rust]                  │                                 python = /nix/store/def-python3.12;
version = "1.75.0"  ────┘                               }
```

This resolved set is used by **both** shell environment and Buck2 config generation.

## Prerequisites

- Phase 0.1: Flake module structure created
- Phase 0.2: Default registry implemented
- Understanding of TOML parsing in Nix
- Familiarity with Nix attribute sets

## Success Criteria

- [ ] Module reads `toolchain.toml` from configured path
- [ ] Module loads registry (default or custom)
- [ ] Module resolves each declared toolchain to derivation
- [ ] Graceful error handling for missing versions
- [ ] Helpful error messages with available versions
- [ ] Resolved derivations accessible to shell/Buck2 generators

## Implementation Guidance

### 1. TOML Parsing

Nix has built-in TOML support via `builtins.fromTOML`:

```nix
let
  tomlContent = builtins.readFile cfg.declarationFile;
  toolchainDeclarations = builtins.fromTOML tomlContent;
in
{
  # toolchainDeclarations = {
  #   go = { version = "1.21.5"; };
  #   rust = { version = "1.75.0"; };
  # }
}
```

### 2. Registry Loading

Load registry with pkgs context:

```nix
let
  registry = import cfg.registry { inherit pkgs; };
  # registry = {
  #   go = { "1.21.5" = <derivation>; ... };
  #   rust = { "1.75.0" = <derivation>; ... };
  # }
in
```

### 3. Resolution Function

Core resolution logic:

```nix
let
  # Resolve a single toolchain entry
  resolveToolchain = name: spec:
    let
      version = spec.version or (throw "Missing version for toolchain '${name}'");
      toolchainRegistry = registry.${name} or (throw "Unknown toolchain '${name}'");
      derivation = toolchainRegistry.${version} or (throw
        "Unknown version '${version}' for toolchain '${name}'. " +
        "Available versions: ${lib.concatStringsSep ", " (lib.attrNames toolchainRegistry)}"
      );
    in
    derivation;

  # Resolve all declared toolchains
  resolvedToolchains = lib.mapAttrs resolveToolchain toolchainDeclarations;
in
{
  # resolvedToolchains = {
  #   go = <derivation /nix/store/abc-go-1.21.5>;
  #   rust = <derivation /nix/store/xyz-rust-1.75.0>;
  # }
}
```

### 4. Error Handling

Provide helpful error messages:

```nix
let
  validateToolchain = name: spec:
    let
      checks = {
        hasVersion = spec ? version;
        toolchainExists = registry ? ${name};
        versionExists = (registry.${name} or {}) ? ${spec.version or ""};
      };
    in
    if !checks.hasVersion then
      throw "Toolchain '${name}' is missing required 'version' field in ${cfg.declarationFile}"
    else if !checks.toolchainExists then
      throw "Unknown toolchain '${name}' in ${cfg.declarationFile}. Available toolchains: ${lib.concatStringsSep ", " (lib.attrNames registry)}"
    else if !checks.versionExists then
      throw "Unknown version '${spec.version}' for toolchain '${name}'. Available versions: ${lib.concatStringsSep ", " (lib.attrNames registry.${name})}"
    else
      true;

  # Validate before resolving
  validated = lib.all (name: validateToolchain name toolchainDeclarations.${name})
    (lib.attrNames toolchainDeclarations);
in
```

### 5. Integration with Module

Update `nix/modules/toolchains/default.nix`:

```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.firefly.toolchains;

  # Load toolchain declarations
  tomlContent = builtins.readFile cfg.declarationFile;
  toolchainDeclarations = builtins.fromTOML tomlContent;

  # Load registry
  registry = import cfg.registry { inherit pkgs; };

  # Resolution logic
  resolveToolchain = name: spec:
    let
      version = spec.version;
      derivation = registry.${name}.${version} or (throw "...");
    in
    derivation;

  # Resolved set
  resolved = lib.mapAttrs resolveToolchain toolchainDeclarations;
in
{
  options.firefly.toolchains = {
    # ... (from Phase 0.1)

    resolved = lib.mkOption {
      type = lib.types.attrs;
      internal = true;
      description = "Resolved toolchain derivations (internal)";
      default = resolved;
    };
  };

  config = {
    # This will be used by shell and Buck2 generators
  };
}
```

### 6. Graceful Fallbacks

Handle missing `toolchain.toml`:

```nix
let
  toolchainDeclarations =
    if builtins.pathExists cfg.declarationFile then
      builtins.fromTOML (builtins.readFile cfg.declarationFile)
    else
      throw "Toolchain declaration file not found: ${cfg.declarationFile}\n" +
            "Create a toolchain.toml file with:\n" +
            "  [go]\n" +
            "  version = \"1.21.5\"\n";
in
```

### 7. Example toolchain.toml

Document expected format:

```toml
# toolchain.toml - Toolchain version declarations
#
# Syntax:
#   [<toolchain-name>]
#   version = "<version-string>"
#
# Version strings must match registry entries.
# See registry for available versions.

[go]
version = "1.21.5"

[rust]
version = "1.75.0"

[python]
version = "3.12"

[clang]
version = "17"
```

## Implementation Steps

1. Add TOML parsing logic to module
2. Add registry loading logic
3. Implement `resolveToolchain` function
4. Implement error handling with helpful messages
5. Add `resolved` internal option to module
6. Test with various toolchain.toml configurations
7. Test error cases (missing file, unknown version, etc.)
8. Create example toolchain.toml in repo root

## Testing

Create test `toolchain.toml`:

```toml
[go]
version = "1.21.5"

[rust]
version = "1.75.0"
```

Test resolution:

```bash
# Test that module resolves correctly
nix eval .#devShells.x86_64-linux.default.config.firefly.toolchains.resolved

# Should show attribute set with derivations
# Test error handling
echo '[go]' > test-toolchain.toml
echo 'version = "999.999.999"' >> test-toolchain.toml

# Should show helpful error with available versions
```

## Related Documentation

- Design: `docs/src/design/toolchain-synchronization.md` (section 2-3)
- Architecture: `docs/src/architecture.md` (section 4.2: "Registry Resolution")
- Tasks: `TASKS.md` (Phase 0.3)
- Nix Manual: `builtins.fromTOML`

## Next Steps

After completing this task:
- Phase 0.4: Implement shell generation (`phase0-04-implement-shell-generation.md`)
- Phase 0.5: Implement Buck2 config generation (`phase0-05-implement-buck2-generation.md`)

## Notes

- **Error messages are critical**: Users will encounter version mismatches frequently
- **Performance**: TOML parsing and resolution happen at eval time (fast)
- **Validation**: Consider schema validation for toolchain.toml
- **Extensibility**: Leave room for future toolchain-specific options beyond `version`
- **Testing**: Create comprehensive test suite for edge cases

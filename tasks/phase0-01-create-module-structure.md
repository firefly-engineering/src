# Phase 0.1: Create Flake Module Structure

## Overview

Create the foundational Nix flake module infrastructure that other repositories can import. This module will be the core mechanism for toolchain synchronization between Nix development shells and Buck2 builds.

## Context

The toolchain synchronization architecture requires a **reusable Nix flake module** that can be imported by downstream repositories. This module will:

- Provide a clean API for configuring toolchains
- Generate both development shell environments and Buck2 configurations
- Support custom or default toolchain registries
- Be designed for eventual extraction into a standalone `turnkey` repository

### Key Architecture Principles

1. **Single Source of Truth**: Both shell and Buck2 derive from same configuration
2. **Registry-Based Resolution**: `toolchain.toml` + registry → concrete Nix derivations
3. **Content-Addressed Binaries**: Nix store paths ensure automatic cache invalidation
4. **Modular Design**: Self-contained code ready for extraction (Phase 8)

## Prerequisites

- None (this is the first implementation task)
- Understanding of Nix flakes and modules system
- Familiarity with Buck2 configuration

## Success Criteria

- [ ] `nix/modules/toolchains/default.nix` exists and exports a valid Nix module
- [ ] Module defines clear configuration options (interface/API)
- [ ] Module is exported in root `flake.nix` as `flakeModules.toolchains`
- [ ] Module can be imported by test downstream repository
- [ ] Code is self-contained (no hard dependencies on this repo's structure)

## Implementation Guidance

### 1. Create Directory Structure

```bash
mkdir -p nix/modules/toolchains
```

### 2. Define Module Interface

Create `nix/modules/toolchains/default.nix` with options:

```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.firefly.toolchains;
in
{
  options.firefly.toolchains = {
    registry = lib.mkOption {
      type = lib.types.path;
      default = ./registry-default.nix;
      description = "Path to toolchain registry file";
    };

    declarationFile = lib.mkOption {
      type = lib.types.path;
      default = ./toolchain.toml;
      description = "Path to toolchain.toml declaration file";
    };

    buck2 = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Buck2 config generation";
      };
    };
  };

  config = {
    # Implementation will be added in subsequent tasks
  };
}
```

### 3. Export Module in Root Flake

Update `flake.nix`:

```nix
{
  outputs = { self, nixpkgs, ... }: {
    # Export as flake module for use with flake-parts or direct import
    flakeModules.toolchains = import ./nix/modules/toolchains;

    # Also export as nixosModule for compatibility
    nixosModules.toolchains = import ./nix/modules/toolchains;
  };
}
```

### 4. Design for Portability

**Important**: This module will eventually be extracted to `firefly-engineering/turnkey`. Design considerations:

- **No absolute paths** to this repository
- **No hardcoded assumptions** about repository structure
- **All paths relative** to module location or configurable
- **Clean separation** between module code and registry data

### 5. Module API Design

The module should expose these capabilities to downstream users:

```nix
# Downstream usage example (target state)
{
  imports = [ firefly-toolchains.flakeModules.toolchains ];

  firefly.toolchains = {
    registry = ./my-custom-registry.nix;  # Or use default
    declarationFile = ./toolchain.toml;
    buck2.enable = true;
  };
}
```

## Implementation Steps

1. Create `nix/modules/toolchains/` directory
2. Create `default.nix` with module options (no implementation yet)
3. Export module in root `flake.nix`
4. Create stub for `registry-default.nix` (will be implemented in next task)
5. Document module options in comments
6. Test that module can be imported without errors

## Testing

```bash
# Verify module exports correctly
nix flake show

# Should show:
# ├───flakeModules
# │   └───toolchains: NixOS module
```

## Related Documentation

- Design: `docs/src/design/toolchain-synchronization.md` (sections 1-3)
- Architecture: `docs/src/architecture.md` (section 4)
- Tasks: `TASKS.md` (Phase 0.1)

## Next Steps

After completing this task:
- Phase 0.2: Create default registry (`phase0-02-create-default-registry.md`)
- Phase 0.3: Implement resolution logic (`phase0-03-implement-resolution-logic.md`)

## Notes

- This task focuses on **structure and interface**, not implementation
- Implementation will be added in Phase 0.3-0.5
- Keep module code clean and well-documented for future extraction
- Consider using `lib.mkOption` with proper types and descriptions

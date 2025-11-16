# Phase 1.1: Implement Error Handling and Edge Cases

## Overview

Enhance the module with comprehensive error handling and graceful handling of edge cases. This ensures users get helpful, actionable error messages when something goes wrong.

## Context

After Phase 0, the module works for the "happy path." Phase 1 focuses on refinement, starting with robust error handling. Good error messages are critical for user experience and debugging.

### Common Error Scenarios

1. **Missing toolchain.toml** - User forgets to create configuration
2. **Unknown toolchain version** - Version not in registry
3. **Malformed TOML** - Syntax errors in toolchain.toml
4. **Missing registry file** - Custom registry path is invalid
5. **Invalid registry format** - Registry doesn't return expected structure
6. **Derivation build failures** - Nix can't build toolchain package

## Prerequisites

- Phase 0.1-0.6: Module implementation complete
- Module working for happy path
- Understanding of Nix error handling patterns

## Success Criteria

- [ ] All error scenarios have clear, helpful messages
- [ ] Error messages include actionable suggestions
- [ ] Error messages list available options when relevant
- [ ] No cryptic Nix evaluation errors exposed to users
- [ ] Error handling tested with all edge cases
- [ ] Documentation includes troubleshooting for each error

## Implementation Guidance

### 1. Missing toolchain.toml

**Current behavior**: Cryptic file not found error

**Improved behavior**:

```nix
let
  declarationPath = cfg.declarationFile;

  toolchainDeclarations =
    if builtins.pathExists declarationPath then
      builtins.fromTOML (builtins.readFile declarationPath)
    else
      throw ''
        Toolchain declaration file not found: ${toString declarationPath}

        To fix this, create a toolchain.toml file:

          cat > toolchain.toml <<EOF
          [go]
          version = "1.21.5"
          EOF

        Or specify a different path:

          firefly.toolchains.declarationFile = ./path/to/toolchain.toml;

        See: docs/src/user-guide/getting-started.md
      '';
in
```

### 2. Unknown Toolchain Version

**Current behavior**: Attribute error or "version not found"

**Improved behavior**:

```nix
let
  resolveToolchain = name: spec:
    let
      version = spec.version or (throw
        "Toolchain '${name}' is missing required 'version' field in ${toString declarationPath}"
      );

      toolchainRegistry = registry.${name} or (throw ''
        Unknown toolchain '${name}' in ${toString declarationPath}

        Available toolchains in registry:
          ${lib.concatStringsSep "\n  " (lib.attrNames registry)}

        Either:
        - Fix the toolchain name in toolchain.toml
        - Add '${name}' to your custom registry
      '');

      derivation = toolchainRegistry.${version} or (throw ''
        Unknown version '${version}' for toolchain '${name}'

        Available versions for '${name}':
          ${lib.concatStringsSep "\n  " (lib.sort lib.lessThan (lib.attrNames toolchainRegistry))}

        Fix this by:
        - Using an available version in toolchain.toml
        - Adding '${version}' to your registry:

            ${name}."${version}" = pkgs.your-package;

        See: docs/src/user-guide/custom-registry.md
      '');
    in
    derivation;
in
```

### 3. Malformed TOML

**Current behavior**: Nix evaluation error with line numbers (if lucky)

**Improved behavior**:

```nix
let
  parseToml = path:
    let
      content = builtins.readFile path;
      parsed = builtins.tryEval (builtins.fromTOML content);
    in
    if parsed.success then
      parsed.value
    else
      throw ''
        Failed to parse TOML file: ${toString path}

        The file contains syntax errors. Common issues:
        - Missing quotes around strings
        - Unclosed brackets
        - Invalid section headers

        Example of valid syntax:

          [go]
          version = "1.21.5"

          [rust]
          version = "1.75.0"

        TOML specification: https://toml.io/

        Error from parser:
        ${builtins.toString parsed}
      '';

  toolchainDeclarations = parseToml declarationPath;
in
```

### 4. Schema Validation

**Add validation** for toolchain.toml structure:

```nix
let
  validateToolchainSpec = name: spec:
    let
      checks = {
        isAttrs = builtins.isAttrs spec;
        hasVersion = spec ? version;
        versionIsString = builtins.isString (spec.version or "");
      };

      errors = lib.optional (!checks.isAttrs)
        "Toolchain '${name}' must be a table/section"
        ++ lib.optional (!checks.hasVersion)
        "Toolchain '${name}' is missing required 'version' field"
        ++ lib.optional (!checks.versionIsString)
        "Toolchain '${name}' version must be a string, got: ${builtins.typeOf spec.version}";
    in
    if errors == [] then
      spec
    else
      throw ''
        Invalid configuration for toolchain '${name}' in ${toString declarationPath}

        ${lib.concatStringsSep "\n" errors}

        Example of correct format:

          [${name}]
          version = "1.0.0"
      '';

  validatedDeclarations = lib.mapAttrs validateToolchainSpec toolchainDeclarations;
in
```

### 5. Missing Registry File

**Improved behavior**:

```nix
let
  loadRegistry = registryPath:
    if builtins.pathExists registryPath then
      import registryPath { inherit pkgs; }
    else
      throw ''
        Registry file not found: ${toString registryPath}

        To fix this:
        - Check the path is correct
        - Use default registry: remove firefly.toolchains.registry option
        - Create registry file at ${toString registryPath}

        See: docs/src/user-guide/custom-registry.md
      '';

  registry = loadRegistry cfg.registry;
in
```

### 6. Invalid Registry Format

**Validate registry structure**:

```nix
let
  validateRegistry = registry:
    if !builtins.isAttrs registry then
      throw ''
        Invalid registry format: expected attribute set, got ${builtins.typeOf registry}

        Registry must be an attribute set like:

          { pkgs }: {
            go = {
              "1.21.5" = pkgs.go_1_21;
            };
          }
      ''
    else
      lib.mapAttrs (name: versions:
        if !builtins.isAttrs versions then
          throw "Invalid registry entry '${name}': versions must be an attribute set"
        else
          versions
      ) registry;

  validatedRegistry = validateRegistry registry;
in
```

### 7. Derivation Build Failures

**Catch and explain**:

```nix
let
  resolveWithFallback = name: spec:
    let
      derivation = resolveToolchain name spec;

      # Try to evaluate the derivation to catch obvious errors early
      checked = builtins.tryEval derivation.outPath;
    in
    if checked.success then
      derivation
    else
      throw ''
        Failed to resolve toolchain '${name}' version '${spec.version}'

        The derivation exists in the registry but cannot be built.
        This may indicate:
        - Incompatible system architecture
        - Missing dependencies
        - Broken package in nixpkgs

        Try:
        - Using a different version
        - Updating nixpkgs
        - Checking nixpkgs issues: https://github.com/NixOS/nixpkgs/issues

        Technical details:
        ${builtins.toString checked}
      '';
in
```

### 8. Helpful Hints System

Add contextual hints:

```nix
let
  # Detect common mistakes and provide hints
  provideHints = declarations: registry:
    let
      # Example: User might have version format wrong
      hints = lib.flatten (lib.mapAttrsToList (name: spec:
        let
          version = spec.version or "";
          available = lib.attrNames (registry.${name} or {});

          # Check for close matches (e.g., "1.21" vs "1.21.5")
          similarVersions = lib.filter (v: lib.hasPrefix version v) available;
        in
        lib.optional (similarVersions != [] && !(lib.elem version available)) ''
          💡 Hint: '${name}' version '${version}' not found, but these similar versions exist:
            ${lib.concatStringsSep "\n  " similarVersions}
        ''
      ) declarations);
    in
    if hints != [] then
      builtins.trace (lib.concatStringsSep "\n\n" hints)
    else
      lib.id;
in
```

## Implementation Steps

1. Wrap TOML parsing with try-catch and helpful errors
2. Add schema validation for toolchain.toml
3. Improve registry loading errors
4. Validate registry format
5. Enhance toolchain resolution errors with available versions
6. Add derivation evaluation checks
7. Create hints system for common mistakes
8. Test all error scenarios
9. Update troubleshooting documentation with all errors

## Testing

Create test cases for each error:

```bash
# Test 1: Missing toolchain.toml
rm toolchain.toml
nix develop 2>&1 | grep "create a toolchain.toml"

# Test 2: Unknown version
echo '[go]\nversion = "999.999.999"' > toolchain.toml
nix develop 2>&1 | grep "Available versions"

# Test 3: Malformed TOML
echo '[go' > toolchain.toml
nix develop 2>&1 | grep "syntax error"

# Test 4: Unknown toolchain
echo '[nonexistent]\nversion = "1.0"' > toolchain.toml
nix develop 2>&1 | grep "Available toolchains"

# Test 5: Missing version field
echo '[go]' > toolchain.toml
nix develop 2>&1 | grep "missing required 'version'"
```

## Related Documentation

- Design: `docs/src/design/toolchain-synchronization.md`
- User Guide: `docs/src/user-guide/troubleshooting.md`
- Tasks: `TASKS.md` (Phase 1.1)

## Next Steps

After completing this task:
- Phase 1.2: Create validation tools (`phase1-02-create-validation-tools.md`)
- Update troubleshooting documentation with all error cases

## Notes

- **User empathy**: Error messages should be friendly and helpful, not accusatory
- **Actionable**: Every error should tell the user how to fix it
- **Examples**: Include examples in error messages
- **Links**: Reference documentation for more details
- **Progressive information**: Start with simple explanation, add details
- **Testing**: Error handling is only good if tested thoroughly
- **Future**: These error messages will be seen by community users in Phase 8+

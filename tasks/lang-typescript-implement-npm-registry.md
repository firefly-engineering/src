# Language: Implement TypeScript NPM Registry

## Overview

Implement local npm registry for TypeScript/JavaScript dependencies, enabling hermetic builds with synchronized dependencies between npm/pnpm/yarn and Buck2.

## Context

From `docs/src/design/typescript-dependency-management-roadmap.md`:
- Goal: NPM registry protocol implementation
- pnpm as primary package manager
- Scoped package support (@types/*, @company/*)
- Test case: Express API with popular packages
- Timeline: ~8 weeks

### Why a Local NPM Registry?

Node package managers need a registry for dependencies. Instead of hitting npmjs.com, we create a local registry that:
- Uses Nix to fetch and verify packages
- Provides npm-compatible protocol
- Works offline (hermetic builds)
- Synchronized with Buck2

## Prerequisites

- Phase 0: Toolchain synchronization working
- Understanding of npm registry protocol
- Understanding of package.json and lock files
- Experience with pnpm/npm/yarn

## Success Criteria

- [ ] JSON format for declaring npm packages
- [ ] Local npm registry generated from declarations
- [ ] Registry compatible with npm, pnpm, and yarn
- [ ] Scoped packages (@types/*, etc.) supported
- [ ] Environment variables configured automatically
- [ ] Example Express API builds successfully
- [ ] Lock file generation works
- [ ] Documentation complete

## Implementation Guidance

### 1. Dependency Declaration Format

`npm-deps.nix`:

```nix
{
  packages = [
    {
      name = "express";
      version = "4.18.2";
      sha512 = "...";
      scope = null;
    }
    {
      name = "types__express";  # Represents @types/express
      displayName = "@types/express";
      version = "4.17.21";
      sha512 = "...";
      scope = "types";
    }
    {
      name = "typescript";
      version = "5.3.3";
      sha512 = "...";
      scope = null;
    }
  ];
}
```

### 2. NPM Registry Structure

NPM registry protocol requires specific endpoints:

```
npm-registry/
├── express/
│   └── 4.18.2/
│       ├── package.json      # Package metadata
│       └── package.tgz       # Tarball
├── @types/
│   └── express/
│       └── 4.17.21/
│           ├── package.json
│           └── package.tgz
├── typescript/
│   └── 5.3.3/
│       ├── package.json
│       └── package.tgz
└── registry.json             # Registry metadata
```

### 3. Generate NPM Registry

```nix
let
  npmDeps = import ./npm-deps.nix;

  # Fetch a package tarball
  fetchNpmPackage = { name, version, sha512, scope ? null, ... }:
    let
      pkgName = if scope != null then "@${scope}/${name}" else name;
    in
    pkgs.fetchurl {
      url = "https://registry.npmjs.org/${pkgName}/-/${name}-${version}.tgz";
      hash = "sha512-${sha512}";
    };

  # Generate package.json metadata
  generatePackageMetadata = pkg:
    let
      pkgName = pkg.displayName or pkg.name;
    in
    builtins.toJSON {
      name = pkgName;
      version = pkg.version;
      dist = {
        tarball = "file://.../${pkg.name}-${pkg.version}.tgz";
        shasum = pkg.sha512;
      };
    };

  # Build complete NPM registry
  npmRegistry = pkgs.runCommand "npm-registry" {} ''
    mkdir -p $out

    # For each package:
    ${lib.concatMapStringsSep "\n" (pkg:
      let
        pkgPath = if pkg.scope != null
          then "$out/@${pkg.scope}/${pkg.name}"
          else "$out/${pkg.name}";
      in
      ''
        # Create package directory
        mkdir -p ${pkgPath}/${pkg.version}

        # Copy tarball
        cp ${fetchNpmPackage pkg} ${pkgPath}/${pkg.version}/${pkg.name}-${pkg.version}.tgz

        # Generate metadata
        cat > ${pkgPath}/${pkg.version}/package.json <<'EOF'
        ${generatePackageMetadata pkg}
        EOF

        # Create package-level index (all versions)
        cat > ${pkgPath}/index.json <<'EOF'
        {
          "versions": {
            "${pkg.version}": $(cat ${pkgPath}/${pkg.version}/package.json)
          }
        }
        EOF
      ''
    ) npmDeps.packages}

    # Create registry index
    cat > $out/registry.json <<'EOF'
    {
      "db_name": "registry",
      "doc_count": ${toString (builtins.length npmDeps.packages)}
    }
    EOF
  '';
in
```

### 4. HTTP Server for Registry

NPM needs HTTP access:

```nix
let
  npmRegistryServer = pkgs.writeScriptBin "npm-registry-server" ''
    #!/usr/bin/env bash
    set -euo pipefail

    PORT=''${NPM_REGISTRY_PORT:-4873}

    echo "Starting NPM registry server on port $PORT..."
    echo "Registry: ${npmRegistry}"

    # Use Verdaccio or simple HTTP server
    ${pkgs.nodejs}/bin/npx --yes http-server \
      ${npmRegistry} \
      --port $PORT \
      --cors \
      -d false &

    echo $! > /tmp/npm-registry-server.pid
    echo "NPM registry: http://localhost:$PORT"
  '';

  stopNpmRegistry = pkgs.writeScriptBin "stop-npm-registry" ''
    #!/usr/bin/env bash
    if [ -f /tmp/npm-registry-server.pid ]; then
      kill $(cat /tmp/npm-registry-server.pid) 2>/dev/null || true
      rm /tmp/npm-registry-server.pid
      echo "NPM registry server stopped"
    fi
  '';
in
```

### 5. Environment Configuration

```nix
let
  npmEnvHook = ''
    # Start NPM registry server
    npm-registry-server

    # Configure npm/pnpm to use local registry
    export NPM_CONFIG_REGISTRY="http://localhost:4873"

    # For pnpm
    export PNPM_REGISTRY="http://localhost:4873"

    # Create .npmrc
    cat > .npmrc <<'EOF'
    registry=http://localhost:4873
    save-exact=true
    EOF

    # Cleanup on exit
    trap stop-npm-registry EXIT

    echo "NPM registry configured:"
    echo "  Registry: http://localhost:4873"
  '';
in
{
  devShells.default = pkgs.mkShell {
    packages = [
      resolved.nodejs
      pkgs.pnpm
      npmRegistryServer
      stopNpmRegistry
    ];

    shellHook = npmEnvHook + existingShellHook;
  };
}
```

### 6. pnpm Configuration

Create `.pnpmfile.cjs` for advanced control:

```javascript
module.exports = {
  hooks: {
    readPackage(pkg) {
      // Redirect all packages to local registry
      return pkg;
    }
  }
};
```

### 7. Dependency Update Helper

```nix
let
  updateNpmDeps = pkgs.writeScriptBin "update-npm-deps" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Updating NPM dependencies..."

    if [ ! -f package.json ]; then
      echo "Error: package.json not found"
      exit 1
    fi

    # Generate lock file with upstream registry
    NPM_CONFIG_REGISTRY=https://registry.npmjs.org \
      pnpm install --lockfile-only

    # Extract dependencies from pnpm-lock.yaml
    ${pkgs.yq-go}/bin/yq eval '.packages' pnpm-lock.yaml | \
      ${pkgs.jq}/bin/jq '
        to_entries |
        map({
          name: (.key | split("/")[-1] | split("@")[0]),
          version: .value.version,
          sha512: .value.resolution.integrity | split("sha512-")[1],
          scope: (if (.key | startswith("/@")) then
            (.key | split("/")[1])
          else null end)
        })
      ' > npm-deps.json

    # Convert to Nix
    echo "{ packages = " > npm-deps.nix
    cat npm-deps.json >> npm-deps.nix
    echo "; }" >> npm-deps.nix

    echo "Updated npm-deps.nix"
    echo "Run 'nix develop' to regenerate local registry"
  '';
in
```

### 8. Scoped Package Handling

Handle @types/* and other scoped packages:

```nix
let
  # Parse scoped package name
  parseScopedName = fullName:
    let
      parts = lib.splitString "/" fullName;
    in
    if lib.hasPrefix "@" fullName then
      {
        scope = lib.removePrefix "@" (lib.head parts);
        name = lib.last parts;
        displayName = fullName;
      }
    else
      {
        scope = null;
        name = fullName;
        displayName = fullName;
      };

  # Use in registry generation
  processPackage = pkg:
    let
      parsed = parseScopedName pkg.name;
    in
    pkg // parsed;
in
```

### 9. Test Case: Express API

`experimental/typescript-api/`:

`package.json`:

```json
{
  "name": "typescript-api",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "tsx src/index.ts",
    "build": "tsc"
  },
  "dependencies": {
    "express": "^4.18.2"
  },
  "devDependencies": {
    "@types/express": "^4.17.21",
    "@types/node": "^20.10.6",
    "typescript": "^5.3.3",
    "tsx": "^4.7.0"
  }
}
```

`src/index.ts`:

```typescript
import express from 'express';

const app = express();
const port = 3000;

interface Message {
  text: string;
}

app.get('/', (req, res) => {
  const message: Message = {
    text: 'Hello from synchronized TypeScript dependencies!'
  };
  res.json(message);
});

app.listen(port, () => {
  console.log(`Server listening on http://localhost:${port}`);
});
```

`BUCK`:

```python
nodejs_binary(
    name = "api",
    main = "src/index.ts",
    deps = [
        "//ext/npm/express:pkg",
        "//ext/npm/@types/express:pkg",
        "//ext/npm/@types/node:pkg",
    ],
)
```

Test:

```bash
# Native pnpm
pnpm install
pnpm run dev

# Buck2
buck2 run //experimental/typescript-api:api
```

### 10. Advanced: Verdaccio Integration

For production-grade registry, use Verdaccio:

```nix
let
  verdaccioConfig = pkgs.writeText "verdaccio-config.yaml" ''
    storage: ${npmRegistry}

    uplinks:
      npmjs:
        url: https://registry.npmjs.org/
        max_fails: 0
        timeout: 10s

    packages:
      '**':
        access: $all
        publish: $all

    listen: 0.0.0.0:4873
  '';

  verdaccioServer = pkgs.writeScriptBin "verdaccio-server" ''
    #!/usr/bin/env bash
    ${pkgs.verdaccio}/bin/verdaccio \
      --config ${verdaccioConfig} \
      --listen 0.0.0.0:4873
  '';
in
```

## Implementation Steps

1. Design package declaration format
2. Implement package fetching from npmjs.org
3. Implement NPM registry structure
4. Set up HTTP server for registry
5. Configure npm/pnpm environment
6. Test with simple package (express)
7. Implement scoped package support
8. Test with @types/* packages
9. Create dependency update helper
10. Build example TypeScript API
11. Document approach and usage

## Testing

```bash
# Test registry generation
nix build .#npmRegistry
ls -R result/
# Should show proper structure

# Test with npm
cd experimental/typescript-api
nix develop --command bash -c "
  npm install
  npm run dev
"

# Test with pnpm
pnpm install
# Should use local registry

# Test scoped packages
npm info @types/express
# Should return from local registry

# Test Buck2
buck2 run //experimental/typescript-api:api

# Verify registry server
curl http://localhost:4873/express
# Should return package metadata
```

## Related Documentation

- Design: `docs/src/design/typescript-dependency-management-roadmap.md`
- NPM Registry API: https://github.com/npm/registry/blob/master/docs/REGISTRY-API.md
- Tasks: `TASKS.md`

## Next Steps

After completing this task:
- Consider Yarn compatibility
- Consider monorepo support (workspaces)
- Optimize for large dependency trees

## Notes

- **NPM protocol**: Follow npm registry API for compatibility
- **HTTP required**: File:// URLs don't work well with npm
- **Scoped packages**: Critical for @types/* and enterprise packages
- **pnpm preferred**: Faster, more efficient than npm
- **Lock files**: Use for reproducibility
- **Testing**: Test with all package managers (npm, pnpm, yarn)
- **Performance**: Local registry is very fast
- **Offline**: Enable fully offline Node.js development
- **Verdaccio**: Consider for production-grade registry

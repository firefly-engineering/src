# TypeScript Dependency Management Implementation Roadmap

## Overview

This document outlines the roadmap for implementing TypeScript/Node.js dependency management as described in the [Architecture document](../architecture.md). The implementation will demonstrate the Nix + Buck2 hybrid architecture with a concrete test case using popular npm packages while maintaining compatibility with standard pnpm, npm, and yarn tooling.

## Test Case: TypeScript Express API with Popular Packages

The implementation will focus on enabling a TypeScript application that uses common ecosystem packages:

```typescript
// src/server.ts
import express, { Request, Response } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { z } from 'zod';
import { rateLimit } from 'express-rate-limit';

const app = express();

// Middleware
app.use(helmet());
app.use(cors());
app.use(morgan('combined'));
app.use(express.json());

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // limit each IP to 100 requests per windowMs
});
app.use(limiter);

// Validation schemas
const GreetingSchema = z.object({
  name: z.string().min(1).max(100),
  language: z.enum(['en', 'es', 'fr', 'de']).default('en'),
});

const GreetingResponse = z.object({
  message: z.string(),
  reversed: z.string(),
  uppercase: z.string(),
  timestamp: z.string(),
});

type GreetingRequest = z.infer<typeof GreetingSchema>;
type GreetingResponseType = z.infer<typeof GreetingResponse>;

// Greeting templates
const GREETINGS: Record<string, string> = {
  en: "Hello, {name}!",
  es: "¡Hola, {name}!",
  fr: "Bonjour, {name}!",
  de: "Hallo, {name}!",
};

// Routes
app.post('/greet', (req: Request, res: Response) => {
  try {
    const data: GreetingRequest = GreetingSchema.parse(req.body);

    const template = GREETINGS[data.language];
    const message = template.replace('{name}', data.name);

    const response: GreetingResponseType = {
      message,
      reversed: message.split('').reverse().join(''),
      uppercase: message.toUpperCase(),
      timestamp: new Date().toISOString(),
    };

    res.json(response);
  } catch (error) {
    if (error instanceof z.ZodError) {
      res.status(400).json({ error: 'Invalid input', details: error.errors });
    } else {
      res.status(500).json({ error: 'Internal server error' });
    }
  }
});

app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`🚀 Server running on http://localhost:${PORT}`);
});
```

```json
// package.json
{
  "name": "@firefly/typescript-api-example",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "build": "tsc",
    "dev": "tsx watch src/server.ts",
    "start": "node dist/server.js",
    "test": "vitest",
    "lint": "eslint src --ext .ts",
    "type-check": "tsc --noEmit"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "helmet": "^7.1.0",
    "morgan": "^1.10.0",
    "zod": "^3.22.4",
    "express-rate-limit": "^7.1.5"
  },
  "devDependencies": {
    "@types/express": "^4.17.21",
    "@types/cors": "^2.8.17",
    "@types/morgan": "^1.9.9",
    "@types/node": "^20.10.0",
    "typescript": "^5.3.0",
    "tsx": "^4.6.0",
    "vitest": "^1.0.0",
    "eslint": "^8.55.0",
    "@typescript-eslint/parser": "^6.14.0",
    "@typescript-eslint/eslint-plugin": "^6.14.0"
  }
}
```

This serves as a practical demonstration of our dependency management system handling external npm packages with complex dependency graphs.

## Current State Analysis

### ✅ Existing Infrastructure

- **Nix Development Environment**: Working devenv setup with Node.js toolchain
- **Buck2 Integration**: System Node.js toolchains configured and functional
- **Basic TypeScript Building**: Simple TypeScript programs build successfully with Buck2
- **Directory Structure**: Well-organized monorepo structure in place

### 📋 Missing Components

- **Centralized Dependency Declaration**: No Nix-based npm package management
- **Local NPM Registry**: No local package registry serving from Nix store
- **Environment Variable Configuration**: Missing transparent pnpm/npm configuration
- **Dependency Bridge Layer**: No transparent access for both Buck2 and native tooling

## Implementation Phases

### Phase 1: Nix Dependency Declaration System

**Timeline**: 1-2 weeks
**Goal**: Establish centralized npm package dependency declarations in Nix

#### Deliverables

1. **JSON dependency declaration format**:
   ```json
   // nix/dependencies/npm-packages.json
   {
     "express": [
       {
         "version": "4.18.2",
         "hash": "sha256-xyz123...",
         "dependencies": {
           "accepts": "~1.3.8",
           "array-flatten": "1.1.1",
           "body-parser": "1.20.1",
           "content-disposition": "0.5.4",
           "cookie": "0.5.0",
           "cookie-signature": "1.0.6"
         },
         "peerDependencies": {},
         "optionalDependencies": {}
       }
     ],
     "@types/express": [
       {
         "version": "4.17.21",
         "hash": "sha256-abc456...",
         "dependencies": {
           "@types/body-parser": "*",
           "@types/express-serve-static-core": "^4.17.33",
           "@types/qs": "*",
           "@types/serve-static": "*"
         }
       }
     ],
     "zod": [
       {
         "version": "3.22.4",
         "hash": "sha256-def789...",
         "dependencies": {},
         "sideEffects": false
       }
     ]
   }
   ```

2. **Nix JSON parser and package fetching**:
   ```nix
   # nix/dependencies/npm-parser.nix
   { lib, fetchurl, runCommand, ... }:
   let
     npmPackagesJson = builtins.fromJSON (builtins.readFile ./npm-packages.json);

     # Construct npm registry URL
     registryUrl = "https://registry.npmjs.org";

     fetchNpmPackage = pkgSpec: fetchurl {
       url = "${registryUrl}/${pkgSpec.name}/-/${pkgSpec.name}-${pkgSpec.version}.tgz";
       sha256 = pkgSpec.hash;
     };

     processPackages = lib.mapAttrs (packageName: versions:
       lib.map (version: {
         name = packageName;
         inherit (version) version hash;
         src = fetchNpmPackage (version // { name = packageName; });
         dependencies = version.dependencies or {};
         peerDependencies = version.peerDependencies or {};
         optionalDependencies = version.optionalDependencies or {};
       }) versions
     ) npmPackagesJson;
   in
   processPackages
   ```

3. **Tooling for dependency management**:
   - Script to add new packages to JSON file
   - Hash calculation using `nix-prefetch-url` for npm packages
   - Dependency resolution and peer dependency handling
   - Support for scoped packages (@types/*, @company/*)

#### Technical Requirements

- JSON format must support peer and optional dependencies
- Support multiple versions per package for dependency resolution
- Use `fetchurl` for reliable package tarball fetching from npm registry
- Implement proper version pinning and hash verification
- Handle npm semver specifications and scoped packages

#### Acceptance Criteria

- [ ] npm packages declared in JSON format
- [ ] Nix successfully parses JSON and fetches packages
- [ ] Support for multiple versions per package
- [ ] Packages successfully fetched and stored in Nix store
- [ ] Hash verification prevents supply chain attacks
- [ ] Tooling available for adding new dependencies

### Phase 2: Local NPM Registry Implementation

**Timeline**: 2-3 weeks
**Goal**: Generate a local npm registry compatible with npm/pnpm registry protocol

#### Deliverables

1. **Nix function to generate npm registry structure**:
   ```nix
   # nix/dependencies/npm-registry.nix
   { lib, runCommand, nodejs, jq, ... }:

   let
     npmPackages = import ./npm-parser.nix { inherit lib fetchurl; };

     generateNpmRegistry = runCommand "npm-registry" {
       buildInputs = [ nodejs jq ];
     } ''
       mkdir -p $out

       ${lib.concatMapStringsSep "\n" (packageName:
         let packageVersions = npmPackages.${packageName};
         in ''
           # Create package directory structure
           PKG_PATH="${lib.replaceStrings ["@"] [""] packageName}"
           PKG_DIR=$(echo "$PKG_PATH" | sed 's|/|%2f|g')

           mkdir -p "$out/$PKG_DIR"

           # Generate package metadata
           cat > "$out/$PKG_DIR/index.json" << 'EOF'
           {
             "name": "${packageName}",
             "description": "Package managed by Firefly monorepo",
             "dist-tags": {
               "latest": "${(builtins.head packageVersions).version}"
             },
             "versions": {
               ${lib.concatMapStringsSep "," (pkgInfo: ''
                 "${pkgInfo.version}": {
                   "name": "${packageName}",
                   "version": "${pkgInfo.version}",
                   "description": "Package managed by Firefly monorepo",
                   "main": "index.js",
                   "dependencies": ${builtins.toJSON pkgInfo.dependencies},
                   "peerDependencies": ${builtins.toJSON pkgInfo.peerDependencies},
                   "optionalDependencies": ${builtins.toJSON pkgInfo.optionalDependencies},
                   "dist": {
                     "integrity": "${pkgInfo.hash}",
                     "shasum": "placeholder",
                     "tarball": "file://$out/tarballs/${packageName}-${pkgInfo.version}.tgz"
                   }
                 }'') packageVersions}
             }
           }
           EOF

           # Copy package tarballs
           mkdir -p "$out/tarballs"
           ${lib.concatMapStringsSep "\n" (pkgInfo: ''
             cp ${pkgInfo.src} "$out/tarballs/${packageName}-${pkgInfo.version}.tgz"
           '') packageVersions}
         ''
       ) (builtins.attrNames npmPackages)}

       # Create registry root metadata
       cat > "$out/-/v1/search" << 'EOF'
       {
         "objects": [
           ${lib.concatMapStringsSep "," (name: ''
             {
               "package": {
                 "name": "${name}",
                 "scope": "unscoped",
                 "version": "${(builtins.head npmPackages.${name}).version}",
                 "description": "Package managed by Firefly monorepo"
               }
             }'') (builtins.attrNames npmPackages)}
         ],
         "total": ${toString (builtins.length (builtins.attrNames npmPackages))},
         "time": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
       }
       EOF
     '';
   in
   generateNpmRegistry
   ```

2. **NPM registry protocol compliance**:
   - Generate package metadata following npm registry API
   - Handle scoped packages (encode @ and / characters)
   - Support dist-tags and version resolution
   - Provide tarball access via file:// URLs

3. **pnpm configuration integration**:
   ```toml
   # Generated .npmrc
   registry=file:///nix/store/.../npm-registry/
   # Or use pnpm-specific config
   @firefly:registry=file:///nix/store/.../npm-registry/
   ```

#### Technical Requirements

- Follow [npm registry API specification](https://github.com/npm/registry/blob/master/docs/REGISTRY-API.md)
- Handle scoped package name encoding correctly
- Generate proper package metadata with dependency specifications
- Support tarball serving via file:// URLs
- Compatible with pnpm, npm, and yarn

#### Acceptance Criteria

- [ ] Registry format matches npm registry API specification
- [ ] Can serve popular packages via local file-based registry
- [ ] Compatible with pnpm (`pnpm install`, `pnpm add`)
- [ ] Compatible with npm and yarn
- [ ] Integration tests pass with real TypeScript projects

### Phase 3: Environment Variable Configuration

**Timeline**: 1 week
**Goal**: Configure development environment to transparently use our local npm registry

#### Deliverables

1. **Enhanced devenv configuration**:
   ```nix
   # nix/devenv/languages.nix (enhanced)
   { ... }:
   let
     npmRegistry = import ../dependencies/npm-registry.nix {
       inherit lib runCommand nodejs jq;
     };
   in
   {
     languages = {
       # ... existing languages
       typescript = {
         enable = true;
       };
       javascript = {
         enable = true;
         package = pkgs.nodejs_20;
         pnpm.enable = true;
         yarn.enable = true;
       };
     };

     env = {
       NPM_CONFIG_REGISTRY = "file://${npmRegistry}/";
       PNPM_REGISTRY = "file://${npmRegistry}/";
       NODE_PATH = "$BUCK_OUT/node_modules";
       PNPM_HOME = "$BUCK_OUT/pnpm";
     };

     enterShell = ''
       echo "🟨 Welcome to Firefly Engineering TypeScript Environment"
       echo "Local npm registry available at: file://${npmRegistry}/"
       echo "Available packages:"
       ${lib.concatMapStringsSep "\n" (name:
         "echo '  - ${name}'"
       ) (builtins.attrNames (builtins.fromJSON (builtins.readFile ../dependencies/npm-packages.json)))}

       # Configure pnpm to use local registry
       mkdir -p .npmrc
       echo "registry=file://${npmRegistry}/" > .npmrc

       # Ensure pnpm uses local store
       export PNPM_STORE_DIR="$BUCK_OUT/pnpm/store"
       mkdir -p "$PNPM_STORE_DIR"
     '';
   }
   ```

2. **No process management needed**:
   - Remove all HTTP server and service management complexity
   - Direct filesystem access to registry via `file://` URL
   - Zero runtime dependencies or background processes

3. **Buck2 integration verification**:
   - Ensure Buck2 Node.js/TypeScript rules use the same package registry
   - Test that Buck2 builds use cached packages
   - Verify shared node_modules behavior

#### Technical Requirements

- Non-intrusive configuration (no modification of user's global npm config)
- No runtime processes or service management
- Filesystem-only approach with reproducible Nix store paths
- Fast package resolution (no network overhead)
- Compatible with TypeScript language servers (tsserver, typescript-language-server)

#### Acceptance Criteria

- [ ] NPM_CONFIG_REGISTRY configured automatically in development shell
- [ ] pnpm, npm, yarn commands use local filesystem registry transparently
- [ ] Buck2 builds use same package cache
- [ ] No background processes or service management required
- [ ] Package resolution works offline

### Phase 4: Test Implementation

**Timeline**: 1 week
**Goal**: Create working example with popular npm packages

#### Deliverables

1. **Test application implementation**:
   ```typescript
   // experimental/typescript-api/src/server.ts
   // (Full implementation as shown above)
   ```

2. **Buck2 build configuration**:
   ```python
   # experimental/typescript-api/BUCK
   typescript_library(
       name = "api_lib",
       srcs = glob(["src/**/*.ts"]),
       deps = [
           "//third-party/npm:express",
           "//third-party/npm:zod",
           "//third-party/npm:helmet",
           "//third-party/npm:cors",
           "//third-party/npm:morgan",
       ],
   )

   node_binary(
       name = "api",
       main = ":api_lib",
       visibility = ["PUBLIC"],
   )
   ```

3. **Standard package.json configuration**:
   ```json
   {
     "name": "@firefly/typescript-api-example",
     "version": "1.0.0",
     "type": "module",
     "dependencies": {
       "express": "^4.18.2",
       "cors": "^2.8.5",
       "helmet": "^7.1.0",
       "morgan": "^1.10.0",
       "zod": "^3.22.4",
       "express-rate-limit": "^7.1.5"
     },
     "devDependencies": {
       "@types/express": "^4.17.21",
       "@types/cors": "^2.8.17",
       "@types/morgan": "^1.9.9",
       "@types/node": "^20.10.0",
       "typescript": "^5.3.0"
     }
   }
   ```

4. **Comprehensive testing**:
   - Verify Buck2 build works: `buck2 build //experimental/typescript-api:api`
   - Verify pnpm works: `cd experimental/typescript-api && pnpm install && pnpm build`
   - Verify npm works: `cd experimental/typescript-api && npm install && npm run build`
   - Test IDE integration (tsserver, auto-completion)

#### Technical Requirements

- Both Buck2 and native Node.js builds must work identically
- Package resolution must be transparent
- IDE language server integration must function
- No Buck2-specific code in the TypeScript source

#### Acceptance Criteria

- [ ] Application builds and runs via Buck2
- [ ] Application builds and runs via native pnpm/npm tooling
- [ ] IDE integration works (auto-completion, go-to-definition)
- [ ] Package cache shared between build systems
- [ ] Output is identical from both build methods

### Phase 5: Documentation and Testing

**Timeline**: 1 week
**Goal**: Complete documentation and comprehensive testing

#### Deliverables

1. **Updated architecture documentation**:
   - Document implemented TypeScript dependency management
   - Include concrete examples and usage patterns
   - Update diagrams to reflect implemented components

2. **Developer guide**:
   - How to add new npm dependencies
   - Troubleshooting common issues
   - Best practices for TypeScript development in the monorepo

3. **Automated testing**:
   - CI/CD integration tests
   - Package resolution verification tests
   - Performance benchmarks for build times

4. **Migration guide**:
   - How to migrate existing TypeScript projects to use centralized dependencies
   - Extracting projects back to standalone npm packages

#### Technical Requirements

- Clear, actionable documentation
- Automated verification of examples
- Performance regression testing
- Backward compatibility considerations

#### Acceptance Criteria

- [ ] Documentation is complete and accurate
- [ ] All examples work as documented
- [ ] CI/CD pipeline includes TypeScript dependency tests
- [ ] Migration path is clear and tested

## Success Metrics

### Development Experience

- **Single Command Setup**: `nix develop` provides complete TypeScript development environment
- **Build Time Consistency**: Buck2 and native builds have similar performance
- **IDE Integration**: Full tsserver support without additional configuration
- **Transparent Package Resolution**: Developers don't need to think about the registry

### Technical Metrics

- **Package Caching**: Shared cache reduces redundant downloads
- **Build Reproducibility**: Identical builds across different environments
- **Dependency Security**: Centralized patching and version management
- **Extraction Simplicity**: Projects easily convertible to standalone npm packages

### Architecture Validation

- **Non-Contaminating**: Standard pnpm/npm tooling works without modification
- **Hermetic Builds**: All dependencies explicitly declared and versioned
- **Ecosystem Compatibility**: Projects remain compatible with standard Node.js ecosystem
- **Vendor Lock-in Avoidance**: No Buck2-specific code required in TypeScript sources

## Risk Mitigation

### Technical Risks

1. **NPM Registry Protocol Compliance**: Thorough testing against npm registry API specification
2. **Dependency Resolution Edge Cases**: Comprehensive test suite covering peer and optional dependencies
3. **Performance Overhead**: Benchmarking and optimization of registry implementation
4. **Nix Store Integration**: Proper handling of Nix garbage collection and package lifecycle

### Process Risks

1. **Developer Adoption**: Clear documentation and migration support
2. **CI/CD Integration**: Gradual rollout with fallback mechanisms
3. **Maintenance Burden**: Automation of dependency updates and security patches
4. **Complexity Management**: Keep implementation simple and well-documented

## Future Enhancements

### Advanced Features

- **Private Package Support**: Extension to support internal/private npm packages
- **Monorepo Package Linking**: Advanced workspace protocol integration
- **Build Optimization**: Advanced caching and incremental compilation
- **Security Scanning**: Automated vulnerability scanning with npm audit

### Ecosystem Integration

- **Language Server Protocol**: Enhanced tsserver integration with monorepo awareness
- **Testing Framework**: Advanced testing utilities for monorepo TypeScript projects
- **Deployment Tools**: Integration with deployment and packaging systems
- **Monitoring**: Metrics and observability for dependency usage

## Implementation Timeline

```
Week 1-2:  Phase 1 - Nix Dependency Declaration System
Week 3-5:  Phase 2 - Local NPM Registry Implementation
Week 6:    Phase 3 - Environment Variable Configuration
Week 7:    Phase 4 - Test Implementation
Week 8:    Phase 5 - Documentation and Testing
```

**Total Duration**: ~8 weeks
**Key Milestones**:
- Week 2: Dependencies managed in Nix
- Week 5: Working local npm registry
- Week 6: Transparent development environment
- Week 7: End-to-end working example
- Week 8: Production-ready with full documentation

---

This roadmap provides a structured approach to implementing TypeScript dependency management that aligns with our hybrid Nix + Buck2 architecture, maintaining our principles of non-contaminating ecosystem integration and transparent native tooling compatibility. The use of pnpm as the primary package manager provides excellent performance and monorepo support while maintaining full compatibility with the broader npm ecosystem.
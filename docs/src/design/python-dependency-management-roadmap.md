# Python Dependency Management Implementation Roadmap

## Overview

This document outlines the roadmap for implementing Python dependency management as described in the [Architecture document](../architecture.md). The implementation will demonstrate the Nix + Buck2 hybrid architecture with a concrete test case using popular Python packages while maintaining compatibility with standard pip, poetry, and uv tooling.

## Test Case: Python Web API with Popular Packages

The implementation will focus on enabling a Python application that uses common ecosystem packages:

```python
# src/main.py
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import uvicorn
import requests
import click


class GreetingRequest(BaseModel):
    name: str
    language: str = "en"


class GreetingResponse(BaseModel):
    message: str
    reversed: str
    uppercase: str


# Greeting templates
GREETINGS = {
    "en": "Hello, {name}!",
    "es": "¡Hola, {name}!",
    "fr": "Bonjour, {name}!",
    "de": "Hallo, {name}!",
}

app = FastAPI(title="Firefly Greeting Service", version="1.0.0")


@app.post("/greet", response_model=GreetingResponse)
async def greet(request: GreetingRequest):
    """Generate a greeting in the specified language."""
    if request.language not in GREETINGS:
        raise HTTPException(
            status_code=400,
            detail=f"Language '{request.language}' not supported. Available: {list(GREETINGS.keys())}"
        )

    message = GREETINGS[request.language].format(name=request.name)

    return GreetingResponse(
        message=message,
        reversed=message[::-1],
        uppercase=message.upper()
    )


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {"status": "healthy"}


@click.command()
@click.option("--host", default="127.0.0.1", help="Host to bind to")
@click.option("--port", default=8000, type=int, help="Port to bind to")
def main(host: str, port: int):
    """Run the greeting service."""
    uvicorn.run(app, host=host, port=port)


if __name__ == "__main__":
    main()
```

This serves as a practical demonstration of our dependency management system handling external Python packages with complex dependency trees.

## Current State Analysis

### ✅ Existing Infrastructure

- **Nix Development Environment**: Working devenv setup with Python toolchain
- **Buck2 Integration**: System Python toolchains configured and functional
- **Basic Python Building**: Simple Python programs build successfully with Buck2
- **Directory Structure**: Well-organized monorepo structure in place

### 📋 Missing Components

- **Centralized Dependency Declaration**: No Nix-based Python package management
- **PyPI Index Implementation**: No local package index serving from Nix store
- **Environment Variable Configuration**: Missing transparent pip/poetry configuration
- **Dependency Bridge Layer**: No transparent access for both Buck2 and native tooling

## Implementation Phases

### Phase 1: Nix Dependency Declaration System

**Timeline**: 1-2 weeks
**Goal**: Establish centralized Python package dependency declarations in Nix

#### Deliverables

1. **JSON dependency declaration format**:
   ```json
   // nix/dependencies/python-packages.json
   {
     "fastapi": [
       {
         "version": "0.104.1",
         "hash": "sha256-XvPFB4+2FdXjdyuFsA5jNmKpX8q6BPCKu3T9Y8fQvLs=",
         "dependencies": {
           "starlette": ">=0.37.2,<0.38.0",
           "pydantic": ">=1.7.4,!=1.8,!=1.8.1,!=2.0.0,!=2.0.1,!=2.1.0,<3.0.0",
           "typing-extensions": ">=4.8.0"
         },
         "extras": {
           "all": ["uvicorn[standard]", "jinja2", "python-multipart"]
         }
       }
     ],
     "pydantic": [
       {
         "version": "2.5.0",
         "hash": "sha256-abc123...",
         "dependencies": {
           "annotated-types": ">=0.4.0",
           "pydantic-core": "2.14.1",
           "typing-extensions": ">=4.6.1"
         }
       }
     ],
     "uvicorn": [
       {
         "version": "0.24.0",
         "hash": "sha256-def456...",
         "dependencies": {
           "click": ">=7.0",
           "h11": ">=0.8"
         },
         "extras": {
           "standard": ["websockets", "httptools", "uvloop", "watchfiles"]
         }
       }
     ]
   }
   ```

2. **Nix JSON parser and package fetching**:
   ```nix
   # nix/dependencies/python-parser.nix
   { lib, fetchPypi, python3Packages, ... }:
   let
     pythonPackagesJson = builtins.fromJSON (builtins.readFile ./python-packages.json);

     fetchPythonPackage = pkgSpec: fetchPypi {
       pname = pkgSpec.name;
       version = pkgSpec.version;
       sha256 = pkgSpec.hash;
     };

     processPackages = lib.mapAttrs (packageName: versions:
       lib.map (version: {
         name = packageName;
         inherit (version) version hash;
         src = fetchPythonPackage (version // { name = packageName; });
         dependencies = version.dependencies or {};
         extras = version.extras or {};
       }) versions
     ) pythonPackagesJson;
   in
   processPackages
   ```

3. **Tooling for dependency management**:
   - Script to add new packages to JSON file
   - Hash calculation using `nix-prefetch-url` for PyPI packages
   - Dependency resolution and conflict detection
   - Support for extras (optional dependencies)

#### Technical Requirements

- JSON format must support extras and optional dependencies
- Support multiple versions per package for dependency resolution
- Use `fetchPypi` for reliable package source fetching from PyPI
- Implement proper version pinning and hash verification
- Handle PEP 440 version specifications

#### Acceptance Criteria

- [ ] Python packages declared in JSON format
- [ ] Nix successfully parses JSON and fetches packages
- [ ] Support for multiple versions per package
- [ ] Packages successfully fetched and stored in Nix store
- [ ] Hash verification prevents supply chain attacks
- [ ] Tooling available for adding new dependencies

### Phase 2: Local PyPI Index Implementation

**Timeline**: 2-3 weeks
**Goal**: Generate a local PyPI-compatible index serving from Nix store

#### Deliverables

1. **Nix function to generate PyPI index**:
   ```nix
   # nix/dependencies/python-index.nix
   { lib, runCommand, python3, ... }:

   let
     pythonPackages = import ./python-parser.nix { inherit lib fetchPypi; };

     generatePyPIIndex = runCommand "python-index" {
       buildInputs = [ python3 ];
     } ''
       mkdir -p $out/simple

       ${lib.concatMapStringsSep "\n" (packageName:
         let packageVersions = pythonPackages.${packageName};
         in ''
           # Create package directory
           mkdir -p "$out/simple/${lib.toLower packageName}"

           # Generate index page for package
           cat > "$out/simple/${lib.toLower packageName}/index.html" << 'EOF'
           <!DOCTYPE html>
           <html>
             <head><title>Links for ${packageName}</title></head>
             <body>
               <h1>Links for ${packageName}</h1>
               ${lib.concatMapStringsSep "\n" (pkgInfo: ''
                 <a href="../../packages/${packageName}-${pkgInfo.version}.tar.gz">${packageName}-${pkgInfo.version}.tar.gz</a><br/>
               '') packageVersions}
             </body>
           </html>
           EOF

           # Copy package files
           ${lib.concatMapStringsSep "\n" (pkgInfo: ''
             mkdir -p "$out/packages"
             cp ${pkgInfo.src} "$out/packages/${packageName}-${pkgInfo.version}.tar.gz"
           '') packageVersions}
         ''
       ) (builtins.attrNames pythonPackages)}

       # Create root index
       cat > "$out/simple/index.html" << 'EOF'
       <!DOCTYPE html>
       <html>
         <head><title>Simple Index</title></head>
         <body>
           <h1>Simple Index</h1>
           ${lib.concatMapStringsSep "\n" (name: ''
             <a href="${lib.toLower name}/">${name}</a><br/>
           '') (builtins.attrNames pythonPackages)}
         </body>
       </html>
       EOF
     '';
   in
   generatePyPIIndex
   ```

2. **PyPI simple index format compliance**:
   - Generate HTML pages following PEP 503 simple repository API
   - Handle package name normalization (lowercase, underscores to hyphens)
   - Support for package links and metadata
   - Compatible with pip, poetry, and other Python package managers

3. **Integration with package management tools**:
   ```bash
   # Environment configuration
   export PIP_INDEX_URL="file:///nix/store/.../simple"
   export PIP_TRUSTED_HOST="localhost"
   export PIP_NO_CACHE_DIR="false"
   export PIP_CACHE_DIR="$BUCK_OUT/python/pip-cache"
   ```

#### Technical Requirements

- Follow [PEP 503 Simple Repository API](https://peps.python.org/pep-0503/) specification
- Handle package name normalization correctly
- Generate proper HTML structure for package discovery
- Support for wheel files and source distributions
- Compatible with pip, poetry, pipenv, and uv

#### Acceptance Criteria

- [ ] Index format matches PEP 503 specification
- [ ] Can serve popular packages via local file-based index
- [ ] Compatible with pip (`pip install`, `pip download`)
- [ ] Compatible with poetry and other package managers
- [ ] Integration tests pass with real Python projects

### Phase 3: Environment Variable Configuration

**Timeline**: 1 week
**Goal**: Configure development environment to transparently use our local PyPI index

#### Deliverables

1. **Enhanced devenv configuration**:
   ```nix
   # nix/devenv/languages.nix (enhanced)
   { ... }:
   let
     pythonIndex = import ../dependencies/python-index.nix {
       inherit lib runCommand python3;
     };
   in
   {
     languages = {
       # ... existing languages
       python = {
         enable = true;
         version = "3.11";
         poetry.enable = true;
         uv.enable = true;
       };
     };

     env = {
       PIP_INDEX_URL = "file://${pythonIndex}/simple";
       PIP_TRUSTED_HOST = "localhost";
       PIP_CACHE_DIR = "$BUCK_OUT/python/pip-cache";
       PYTHONPATH = "$BUCK_OUT/python/lib";
       VIRTUAL_ENV = "$BUCK_OUT/python/venv";
     };

     enterShell = ''
       echo "🐍 Welcome to Firefly Engineering Python Environment"
       echo "Local PyPI index available at: file://${pythonIndex}/simple"
       echo "Available packages:"
       ${lib.concatMapStringsSep "\n" (name:
         "echo '  - ${name}'"
       ) (builtins.attrNames (builtins.fromJSON (builtins.readFile ../dependencies/python-packages.json)))}

       # Create virtual environment in buck-out
       mkdir -p "$BUCK_OUT/python"
       if [ ! -d "$VIRTUAL_ENV" ]; then
         python -m venv "$VIRTUAL_ENV"
       fi
       source "$VIRTUAL_ENV/bin/activate"

       # Configure pip to use local index
       pip config set global.index-url "file://${pythonIndex}/simple"
     '';
   }
   ```

2. **No process management needed**:
   - Remove all HTTP server and service management complexity
   - Direct filesystem access to index via `file://` URL
   - Zero runtime dependencies or background processes

3. **Buck2 integration verification**:
   - Ensure Buck2 Python rules use the same package index
   - Test that Buck2 builds use cached packages
   - Verify shared site-packages behavior

#### Technical Requirements

- Non-intrusive configuration (no modification of user's global pip config)
- No runtime processes or service management
- Filesystem-only approach with reproducible Nix store paths
- Fast package resolution (no network overhead)
- Compatible with Python language servers (pyright, pylsp)

#### Acceptance Criteria

- [ ] PIP_INDEX_URL configured automatically in development shell
- [ ] pip, poetry, uv commands use local filesystem index transparently
- [ ] Buck2 builds use same package cache
- [ ] No background processes or service management required
- [ ] Package resolution works offline

### Phase 4: Test Implementation

**Timeline**: 1 week
**Goal**: Create working example with popular Python packages

#### Deliverables

1. **Test application implementation**:
   ```python
   # experimental/python-web-api/src/main.py
   # (Full implementation as shown above)
   ```

2. **Buck2 build configuration**:
   ```python
   # experimental/python-web-api/BUCK
   python_binary(
       name = "web-api",
       main = "src/main.py",
       srcs = glob(["src/**/*.py"]),
       deps = [
           "//third-party/python:fastapi",
           "//third-party/python:uvicorn",
           "//third-party/python:click",
       ],
       visibility = ["PUBLIC"],
   )
   ```

3. **Standard Python packaging**:
   ```toml
   # experimental/python-web-api/pyproject.toml
   [build-system]
   requires = ["hatchling"]
   build-backend = "hatchling.build"

   [project]
   name = "python-web-api"
   version = "0.1.0"
   description = "Example Python web API for Firefly monorepo"
   dependencies = [
       "fastapi>=0.104.1",
       "uvicorn>=0.24.0",
       "click>=8.1.0",
       "pydantic>=2.5.0",
       "requests>=2.31.0",
   ]

   [tool.poetry]
   name = "python-web-api"
   version = "0.1.0"
   description = ""
   authors = ["Firefly Engineering"]

   [tool.poetry.dependencies]
   python = "^3.11"
   fastapi = "^0.104.1"
   uvicorn = "^0.24.0"
   click = "^8.1.0"
   ```

4. **Comprehensive testing**:
   - Verify Buck2 build works: `buck2 build //experimental/python-web-api:web-api`
   - Verify pip install works: `cd experimental/python-web-api && pip install -e .`
   - Verify poetry works: `cd experimental/python-web-api && poetry install`
   - Test IDE integration (pyright, auto-completion)

#### Technical Requirements

- Both Buck2 and native Python builds must work identically
- Package resolution must be transparent
- IDE language server integration must function
- No Buck2-specific code in the Python source

#### Acceptance Criteria

- [ ] Application builds and runs via Buck2
- [ ] Application builds and runs via native Python tooling (pip, poetry)
- [ ] IDE integration works (auto-completion, go-to-definition)
- [ ] Package cache shared between build systems
- [ ] Output is identical from both build methods

### Phase 5: Documentation and Testing

**Timeline**: 1 week
**Goal**: Complete documentation and comprehensive testing

#### Deliverables

1. **Updated architecture documentation**:
   - Document implemented Python dependency management
   - Include concrete examples and usage patterns
   - Update diagrams to reflect implemented components

2. **Developer guide**:
   - How to add new Python dependencies
   - Troubleshooting common issues
   - Best practices for Python development in the monorepo

3. **Automated testing**:
   - CI/CD integration tests
   - Package resolution verification tests
   - Performance benchmarks for build times

4. **Migration guide**:
   - How to migrate existing Python projects to use centralized dependencies
   - Extracting projects back to standalone packages

#### Technical Requirements

- Clear, actionable documentation
- Automated verification of examples
- Performance regression testing
- Backward compatibility considerations

#### Acceptance Criteria

- [ ] Documentation is complete and accurate
- [ ] All examples work as documented
- [ ] CI/CD pipeline includes Python dependency tests
- [ ] Migration path is clear and tested

## Success Metrics

### Development Experience

- **Single Command Setup**: `nix develop` provides complete Python development environment
- **Build Time Consistency**: Buck2 and native builds have similar performance
- **IDE Integration**: Full pyright/pylsp support without additional configuration
- **Transparent Package Resolution**: Developers don't need to think about the index

### Technical Metrics

- **Package Caching**: Shared cache reduces redundant downloads
- **Build Reproducibility**: Identical builds across different environments
- **Dependency Security**: Centralized patching and version management
- **Extraction Simplicity**: Projects easily convertible to standalone packages

### Architecture Validation

- **Non-Contaminating**: Standard pip/poetry tooling works without modification
- **Hermetic Builds**: All dependencies explicitly declared and versioned
- **Ecosystem Compatibility**: Projects remain compatible with standard Python ecosystem
- **Vendor Lock-in Avoidance**: No Buck2-specific code required in Python sources

## Risk Mitigation

### Technical Risks

1. **PyPI Protocol Compliance**: Thorough testing against PEP 503 specification
2. **Dependency Resolution Edge Cases**: Comprehensive test suite covering extras and version conflicts
3. **Performance Overhead**: Benchmarking and optimization of index implementation
4. **Nix Store Integration**: Proper handling of Nix garbage collection and package lifecycle

### Process Risks

1. **Developer Adoption**: Clear documentation and migration support
2. **CI/CD Integration**: Gradual rollout with fallback mechanisms
3. **Maintenance Burden**: Automation of dependency updates and security patches
4. **Complexity Management**: Keep implementation simple and well-documented

## Future Enhancements

### Advanced Features

- **Private Package Support**: Extension to support internal/private Python packages
- **Conda Integration**: Support for conda packages alongside pip packages
- **Build Optimization**: Advanced caching and incremental compilation
- **Security Scanning**: Automated vulnerability scanning with safety or bandit

### Ecosystem Integration

- **Language Server Protocol**: Enhanced pyright integration with monorepo awareness
- **Testing Framework**: Advanced testing utilities for monorepo Python projects
- **Deployment Tools**: Integration with deployment and packaging systems
- **Monitoring**: Metrics and observability for dependency usage

## Implementation Timeline

```
Week 1-2:  Phase 1 - Nix Dependency Declaration System
Week 3-5:  Phase 2 - Local PyPI Index Implementation
Week 6:    Phase 3 - Environment Variable Configuration
Week 7:    Phase 4 - Test Implementation
Week 8:    Phase 5 - Documentation and Testing
```

**Total Duration**: ~8 weeks
**Key Milestones**:
- Week 2: Dependencies managed in Nix
- Week 5: Working local PyPI index
- Week 6: Transparent development environment
- Week 7: End-to-end working example
- Week 8: Production-ready with full documentation

---

This roadmap provides a structured approach to implementing Python dependency management that aligns with our hybrid Nix + Buck2 architecture, maintaining our principles of non-contaminating ecosystem integration and transparent native tooling compatibility.
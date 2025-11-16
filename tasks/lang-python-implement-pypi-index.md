# Language: Implement Python PyPI Index

## Overview

Implement local PEP 503-compliant PyPI index for Python dependencies, enabling hermetic Python builds with synchronized dependencies between pip/poetry/uv and Buck2.

## Context

From `docs/src/design/python-dependency-management-roadmap.md`:
- Goal: JSON-based package declaration with extras support
- PEP 503 compliant PyPI index
- Compatible with pip, poetry, uv
- Test case: FastAPI web service
- Timeline: ~8 weeks

### Why a Local PyPI Index?

Python package managers need a package index. Instead of hitting pypi.org, we create a local index that:
- Uses Nix to fetch and verify packages
- Provides PEP 503-compliant HTTP interface
- Works offline (hermetic builds)
- Synchronized with Buck2

## Prerequisites

- Phase 0: Toolchain synchronization working
- Understanding of PEP 503 (Simple Repository API)
- Understanding of Python packaging (wheels, sdists)
- Experience with pip/poetry/uv

## Success Criteria

- [ ] JSON format for declaring Python packages
- [ ] Local PyPI index generated from declarations
- [ ] Index compliant with PEP 503
- [ ] Works with pip, poetry, and uv
- [ ] Environment variables configured automatically
- [ ] Example FastAPI service builds successfully
- [ ] Extras (optional dependencies) supported
- [ ] Documentation complete

## Implementation Guidance

### 1. Dependency Declaration Format

`python-deps.nix`:

```nix
{
  packages = [
    {
      name = "fastapi";
      version = "0.109.0";
      sha256 = "...";
      extras = []; # or ["all"] for all extras
    }
    {
      name = "uvicorn";
      version = "0.27.0";
      sha256 = "...";
      extras = ["standard"];
    }
    {
      name = "pydantic";
      version = "2.5.3";
      sha256 = "...";
      extras = [];
    }
  ];
}
```

### 2. PEP 503 Index Structure

PEP 503 Simple Repository API requires:

```
pypi-index/
├── index.html                # Root index (lists all packages)
├── fastapi/
│   ├── index.html            # Package index (lists all versions)
│   └── fastapi-0.109.0-py3-none-any.whl
├── uvicorn/
│   ├── index.html
│   └── uvicorn-0.27.0-py3-none-any.whl
└── pydantic/
    ├── index.html
    └── pydantic-2.5.3-py3-none-any.whl
```

### 3. Generate PyPI Index

```nix
let
  pythonDeps = import ./python-deps.nix;

  # Fetch a package (wheel or sdist)
  fetchPackage = { name, version, sha256 }:
    pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/.../${name}-${version}-py3-none-any.whl";
      inherit sha256;
    };

  # Generate PEP 503 compliant index.html for a package
  generatePackageIndex = pkg:
    let
      filename = "${pkg.name}-${pkg.version}-py3-none-any.whl";
    in
    ''
      <!DOCTYPE html>
      <html>
      <head><title>Links for ${pkg.name}</title></head>
      <body>
        <h1>Links for ${pkg.name}</h1>
        <a href="${filename}">${filename}</a><br/>
      </body>
      </html>
    '';

  # Generate root index.html
  generateRootIndex = packages:
    ''
      <!DOCTYPE html>
      <html>
      <head><title>Simple Index</title></head>
      <body>
        <h1>Simple Index</h1>
        ${lib.concatMapStringsSep "\n" (pkg:
          ''<a href="${pkg.name}/">${pkg.name}</a><br/>''
        ) packages}
      </body>
      </html>
    '';

  # Build complete PyPI index
  pypiIndex = pkgs.runCommand "pypi-index" {} ''
    mkdir -p $out

    # Generate root index
    cat > $out/index.html <<'EOF'
    ${generateRootIndex pythonDeps.packages}
    EOF

    # For each package:
    ${lib.concatMapStringsSep "\n" (pkg: ''
      # Create package directory
      mkdir -p $out/${pkg.name}

      # Copy package file
      cp ${fetchPackage pkg} $out/${pkg.name}/${pkg.name}-${pkg.version}-py3-none-any.whl

      # Generate package index
      cat > $out/${pkg.name}/index.html <<'EOF'
      ${generatePackageIndex pkg}
      EOF
    '') pythonDeps.packages}
  '';
in
```

### 4. Environment Configuration

```nix
let
  # Serve PyPI index via HTTP (for development)
  servePyPI = pkgs.writeScriptBin "serve-pypi" ''
    #!/usr/bin/env bash
    cd ${pypiIndex}
    ${pkgs.python3}/bin/python -m http.server 8080
  '';

  pythonEnvHook = ''
    # Option 1: File-based (simpler but may not work with all tools)
    export PIP_INDEX_URL="file://${pypiIndex}/index.html"
    export PIP_NO_INDEX=false
    export PIP_TRUSTED_HOST=""

    # Option 2: HTTP server (more compatible)
    # Start background HTTP server for PyPI index
    # (In practice, would use more robust solution)

    echo "Python package index configured:"
    echo "  Index: ${pypiIndex}"
  '';
in
{
  devShells.default = pkgs.mkShell {
    packages = [ resolved.python servePyPI ];
    shellHook = pythonEnvHook + existingShellHook;
  };
}
```

### 5. pip Configuration

Create `pip.conf` automatically:

```ini
[global]
index-url = file://${pypiIndex}
trusted-host = localhost
no-cache-dir = true

[install]
no-deps = false
```

### 6. poetry Configuration

For poetry users:

```toml
# pyproject.toml
[[tool.poetry.source]]
name = "local"
url = "file://${pypiIndex}"
priority = "primary"
```

### 7. uv Configuration

For uv users:

```bash
export UV_INDEX_URL="file://${pypiIndex}"
export UV_NO_CACHE=1
```

### 8. Dependency Update Helper

```nix
let
  updatePythonDeps = pkgs.writeScriptBin "update-python-deps" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Updating Python dependencies..."

    # Method 1: From requirements.txt
    if [ -f requirements.txt ]; then
      cat requirements.txt | while read line; do
        # Parse package==version
        pkg=$(echo "$line" | cut -d'=' -f1)
        ver=$(echo "$line" | cut -d'=' -f3)

        # Fetch metadata from PyPI to get hash
        echo "  Fetching $pkg $ver..."
        # TODO: Fetch from PyPI API and extract SHA256
      done
    fi

    # Method 2: From poetry.lock
    if [ -f poetry.lock ]; then
      # Parse poetry.lock and extract packages
      # TODO: Implement
      echo "poetry.lock support TODO"
    fi

    echo "Update complete. Regenerate index with 'nix develop'"
  '';
in
```

### 9. Handle Extras (Optional Dependencies)

Extras require dependency resolution:

```nix
let
  # Resolve extras to additional packages
  resolveExtras = { name, version, extras }:
    if extras == [] then []
    else
      # Query package metadata to find extra dependencies
      # This is complex - may need to fetch metadata from PyPI
      [];

  # When generating index, include extra dependencies
  allPackages = pythonDeps.packages ++
    (lib.flatten (map resolveExtras pythonDeps.packages));
in
```

### 10. Test Case: FastAPI Service

`experimental/python-web-service/`:

`requirements.txt`:

```txt
fastapi==0.109.0
uvicorn[standard]==0.27.0
pydantic==2.5.3
```

`main.py`:

```python
from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI()

class Message(BaseModel):
    text: str

@app.get("/")
async def root() -> Message:
    return Message(text="Hello from synchronized Python dependencies!")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
```

`BUCK`:

```python
python_binary(
    name = "web-service",
    main = "main.py",
    deps = [
        "//ext/python/fastapi:pkg",
        "//ext/python/uvicorn:pkg",
        "//ext/python/pydantic:pkg",
    ],
)
```

Test:

```bash
# Native pip install + run
pip install -r requirements.txt
python main.py

# Buck2 build + run
buck2 run //experimental/python-web-service:web-service
```

### 11. Advanced: HTTP Server for Index

For better compatibility, serve via HTTP:

```nix
let
  pypiServer = pkgs.writeScriptBin "pypi-server" ''
    #!/usr/bin/env bash
    # Simple HTTP server for PyPI index
    ${pkgs.python3}/bin/python -m http.server \
      --directory ${pypiIndex} \
      --bind 127.0.0.1 \
      8080 &

    echo $! > /tmp/pypi-server.pid
    echo "PyPI index server started on http://127.0.0.1:8080"
  '';

  stopPypiServer = pkgs.writeScriptBin "stop-pypi-server" ''
    #!/usr/bin/env bash
    if [ -f /tmp/pypi-server.pid ]; then
      kill $(cat /tmp/pypi-server.pid)
      rm /tmp/pypi-server.pid
      echo "PyPI server stopped"
    fi
  '';
in
{
  devShells.default = pkgs.mkShell {
    packages = [ pypiServer stopPypiServer ];

    shellHook = ''
      # Auto-start server
      pypi-server

      # Configure pip
      export PIP_INDEX_URL="http://127.0.0.1:8080"

      # Cleanup on exit
      trap stop-pypi-server EXIT
    '';
  };
}
```

### 12. Challenges and Solutions

**Challenge 1**: Wheels vs source distributions

**Solution**: Prefer wheels, fetch sdists only if needed

**Challenge 2**: Platform-specific wheels

**Solution**: Fetch wheels for target platform

**Challenge 3**: Dependency resolution

**Solution**: Let pip/poetry resolve, extract from lock file

**Challenge 4**: Extras resolution

**Solution**: Pre-resolve extras or use metadata

## Implementation Steps

1. Design package declaration format
2. Implement package fetching from PyPI
3. Implement PEP 503 index generation
4. Test index compliance with pip
5. Configure pip environment
6. Test with poetry
7. Test with uv
8. Create dependency update helper
9. Handle extras support
10. Build example FastAPI service
11. Document approach and usage

## Testing

```bash
# Test index generation
nix build .#pypiIndex
ls -R result/
# Should show PEP 503 structure

# Test with pip
cd experimental/python-web-service
nix develop --command bash -c "
  pip install -r requirements.txt
  python main.py
"

# Test with poetry
poetry install
# Should use local index

# Test with uv
uv pip install -r requirements.txt
# Should use local index

# Test Buck2
buck2 run //experimental/python-web-service:web-service

# Verify PEP 503 compliance
python -m http.server &
pip install --index-url http://localhost:8000 fastapi
# Should work
```

## Related Documentation

- Design: `docs/src/design/python-dependency-management-roadmap.md`
- PEP 503: https://peps.python.org/pep-0503/
- Tasks: `TASKS.md`

## Next Steps

After completing this task:
- Implement TypeScript npm registry (`lang-typescript-implement-npm-registry.md`)
- Consider integration with poetry for better dependency resolution

## Notes

- **PEP 503 compliance**: Critical for tool compatibility
- **Wheels preferred**: Faster, no build required
- **Platform-specific**: May need multiple wheel variants
- **HTTP server**: More compatible than file:// URLs
- **Extras**: Complex but important for full compatibility
- **Testing**: Test with all major tools (pip, poetry, uv)
- **Performance**: Local index is very fast
- **Offline**: Enable fully offline Python development

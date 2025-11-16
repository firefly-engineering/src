# Language: Implement Rust Cargo Registry

## Overview

Implement local Cargo registry for Rust dependencies, enabling hermetic Rust builds with synchronized dependencies between Cargo and Buck2.

## Context

From `docs/src/design/rust-dependency-management-roadmap.md`:
- Goal: JSON-based crate declaration
- Local Cargo-compatible registry
- Environment: `CARGO_REGISTRY_DEFAULT`, `CARGO_NET_OFFLINE`
- Test case: Web service with serde, tokio, axum
- Timeline: ~8 weeks

### Why a Local Registry?

Cargo needs a source for dependencies. Instead of hitting crates.io, we create a local registry that:
- Uses Nix to fetch and verify crates
- Provides Cargo-compatible HTTP index
- Works offline (hermetic builds)
- Synchronized with Buck2

## Prerequisites

- Phase 0: Toolchain synchronization working
- Understanding of Cargo registry protocol
- Understanding of Rust build system
- Experience with Nix derivations

## Success Criteria

- [ ] JSON format for declaring Rust dependencies
- [ ] Local Cargo registry generated from declarations
- [ ] Registry compatible with Cargo (follows spec)
- [ ] Environment variables configured automatically
- [ ] `cargo build` works with local registry
- [ ] Buck2 builds work with same dependencies
- [ ] Example web service builds successfully
- [ ] Documentation complete

## Implementation Guidance

### 1. Dependency Declaration Format

`rust-deps.nix`:

```nix
{
  crates = [
    {
      name = "serde";
      version = "1.0.193";
      sha256 = "...";
      features = [ "derive" ];
    }
    {
      name = "tokio";
      version = "1.35.1";
      sha256 = "...";
      features = [ "full" ];
    }
    {
      name = "axum";
      version = "0.7.3";
      sha256 = "...";
      features = [];
    }
  ];
}
```

### 2. Registry Structure

Cargo expects specific directory structure:

```
cargo-registry/
├── index/
│   └── se/
│       └── rd/
│           └── serde        # JSON metadata
├── crates/
│   ├── serde-1.0.193.crate  # Tarball
│   ├── tokio-1.35.1.crate
│   └── axum-0.7.3.crate
└── config.json              # Registry config
```

### 3. Generate Registry

```nix
let
  rustDeps = import ./rust-deps.nix;

  # Fetch a single crate
  fetchCrate = { name, version, sha256 }:
    pkgs.fetchurl {
      url = "https://crates.io/api/v1/crates/${name}/${version}/download";
      inherit sha256;
      name = "${name}-${version}.crate";
    };

  # Generate index entry for a crate
  generateIndexEntry = { name, version, sha256, features ? [] }:
    let
      # Cargo index format
      entry = {
        inherit name version features;
        cksum = sha256;
        yanked = false;
        deps = [];  # Simplified - should resolve dependencies
      };
    in
    builtins.toJSON entry;

  # Build complete registry
  cargoRegistry = pkgs.runCommand "cargo-registry" {} ''
    mkdir -p $out/{index,crates}

    # Copy crates
    ${lib.concatMapStringsSep "\n" (crate: ''
      cp ${fetchCrate crate} $out/crates/${crate.name}-${crate.version}.crate
    '') rustDeps.crates}

    # Generate index entries
    ${lib.concatMapStringsSep "\n" (crate:
      let
        # Cargo index path based on name
        # See: https://doc.rust-lang.org/cargo/reference/registries.html#index-format
        prefix =
          if lib.stringLength crate.name == 1 then "1"
          else if lib.stringLength crate.name == 2 then "2"
          else if lib.stringLength crate.name == 3 then "3/${lib.substring 0 1 crate.name}"
          else "${lib.substring 0 2 crate.name}/${lib.substring 2 2 crate.name}";

        indexPath = "$out/index/${prefix}/${crate.name}";
      in
      ''
        mkdir -p $(dirname ${indexPath})
        echo '${generateIndexEntry crate}' >> ${indexPath}
      ''
    ) rustDeps.crates}

    # Create config.json
    cat > $out/config.json <<'EOF'
    {
      "dl": "file://$out/crates/{crate}-{version}.crate",
      "api": null
    }
    EOF
  '';
in
```

### 4. Environment Configuration

```nix
let
  rustEnvHook = ''
    # Point Cargo to local registry
    export CARGO_HOME="$(pwd)/.cargo"
    mkdir -p "$CARGO_HOME"

    # Configure to use local registry
    cat > "$CARGO_HOME/config.toml" <<'EOF'
    [source.crates-io]
    replace-with = "local-registry"

    [source.local-registry]
    local-registry = "${cargoRegistry}"
    EOF

    # Offline mode (prevent network access)
    export CARGO_NET_OFFLINE=true

    echo "Cargo registry configured:"
    echo "  Registry: ${cargoRegistry}"
    echo "  Offline: enabled"
  '';
in
{
  devShells.default = pkgs.mkShell {
    packages = [ resolved.rust ];
    shellHook = rustEnvHook + existingShellHook;
  };
}
```

### 5. Dependency Update Helper

```nix
let
  updateRustDeps = pkgs.writeScriptBin "update-rust-deps" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Updating Rust dependencies..."

    if [ ! -f Cargo.toml ]; then
      echo "Error: Cargo.toml not found"
      exit 1
    fi

    # Generate Cargo.lock if needed
    cargo generate-lockfile

    # Extract dependencies from Cargo.lock
    cat Cargo.lock | ${pkgs.yj}/bin/yj -tj | jq '
      .package |
      map(select(.source == "registry+https://github.com/rust-lang/crates.io-index")) |
      map({
        name: .name,
        version: .version,
        sha256: .checksum,
        features: []  # TODO: Extract features
      })
    ' > rust-deps.json

    # Convert to Nix
    echo "{ crates = " > rust-deps.nix
    cat rust-deps.json >> rust-deps.nix
    echo "; }" >> rust-deps.nix

    echo "Updated rust-deps.nix"
    echo "Run 'nix develop' to regenerate local registry"
  '';
in
```

### 6. Buck2 Integration

Generate Buck2 rules for Rust crates:

```python
# In generated BUCK file
rust_library(
    name = "serde",
    srcs = glob(["${cargoRegistry}/extracted/serde-1.0.193/**/*.rs"]),
    crate_root = "${cargoRegistry}/extracted/serde-1.0.193/src/lib.rs",
    visibility = ["PUBLIC"],
)
```

Or simpler: Use system Cargo with environment configured:

```ini
[rust]
rustc_bin = /nix/store/.../rustc
cargo_bin = /nix/store/.../cargo
# Cargo will use CARGO_HOME config from environment
```

### 7. Test Case: Web Service

`experimental/rust-web-service/`:

`Cargo.toml`:

```toml
[package]
name = "web-service"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1.35", features = ["full"] }
axum = "0.7"
serde = { version = "1.0", features = ["derive"] }
```

`src/main.rs`:

```rust
use axum::{
    routing::get,
    Router,
    Json,
};
use serde::Serialize;

#[derive(Serialize)]
struct Message {
    text: String,
}

async fn hello() -> Json<Message> {
    Json(Message {
        text: "Hello from synchronized Rust dependencies!".to_string(),
    })
}

#[tokio::main]
async fn main() {
    let app = Router::new().route("/", get(hello));

    let listener = tokio::net::TcpListener::bind("127.0.0.1:3000")
        .await
        .unwrap();

    println!("Listening on {}", listener.local_addr().unwrap());

    axum::serve(listener, app).await.unwrap();
}
```

Test:

```bash
# Native cargo build
cargo build
./target/debug/web-service

# Buck2 build
buck2 build //experimental/rust-web-service:web-service
buck2 run //experimental/rust-web-service:web-service
```

### 8. Challenges and Solutions

**Challenge 1**: Cargo index format is complex

**Solution**: Use reference implementation, test against real Cargo

**Challenge 2**: Dependency resolution

**Solution**: Let Cargo resolve, extract from Cargo.lock

**Challenge 3**: Build script dependencies

**Solution**: Handle build.rs dependencies separately if needed

## Implementation Steps

1. Design dependency declaration format
2. Implement crate fetching from crates.io
3. Implement registry structure generation
4. Implement index format (follow Cargo spec)
5. Configure Cargo environment variables
6. Create dependency update helper
7. Test with simple crate (serde)
8. Test with complex crate (tokio)
9. Build example web service
10. Document approach and usage

## Testing

```bash
# Test registry generation
nix build .#cargoRegistry
ls -R result/
# Should show proper structure

# Test with Cargo
cd experimental/rust-web-service
nix develop --command bash -c "
  cargo build
  # Should fetch from local registry only
"

# Verify offline mode
CARGO_NET_OFFLINE=true cargo build
# Should succeed

# Test Buck2 integration
buck2 build //experimental/rust-web-service:web-service

# Test web service
buck2 run //experimental/rust-web-service:web-service &
curl http://localhost:3000
# Should return JSON
```

## Related Documentation

- Design: `docs/src/design/rust-dependency-management-roadmap.md`
- Cargo Registry Spec: https://doc.rust-lang.org/cargo/reference/registries.html
- Tasks: `TASKS.md`

## Next Steps

After completing this task:
- Implement Python PyPI index (`lang-python-implement-pypi-index.md`)
- Consider reindeer integration for Buck2 rule generation

## Notes

- **Registry format**: Follow Cargo spec exactly for compatibility
- **Offline builds**: Critical for hermetic builds
- **Buck2**: May need custom rules or use system cargo
- **Build scripts**: May need special handling
- **Features**: Extract from Cargo.toml for accuracy
- **Updates**: Helper script makes dependency updates easy
- **Testing**: Test with real-world crates (tokio, serde, etc.)
- **Performance**: Local registry is fast

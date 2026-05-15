# Introduction

Welcome to the Firefly Engineering monorepo documentation. This documentation covers the architecture, security practices, and development workflows for our hybrid Nix + Buck2 monorepo.

## Overview

This monorepo employs a unique architecture that combines the best of both worlds:

- **[Nix + Flakes](./architecture.md#flake-inputs)** for reproducible development environments and toolchain management
- **[Buck2](./architecture.md#buck2-cells-turnkey-managed)** as a fast, hermetic build system
- **[Turnkey](https://github.com/firefly-engineering/turnkey)** ensuring native tools and Buck2 use identical binaries
- **[Supply Chain Security](./supply-chain-security.md)** through content-addressed dependencies and centralized auditing

## Key Benefits

### For Developers
- **Single Command Setup**: `nix develop` provides everything needed to start contributing
- **Guaranteed Consistency**: Native tools and Buck2 use identical toolchain binaries - no "works on my machine" issues
- **Familiar Tooling**: Standard language tools (cargo, go build, python) work seamlessly
- **Fast Builds**: Buck2 provides incremental builds with excellent caching
- **IDE Integration**: Full language server support for all supported languages

### For Security
- **Hermetic Builds**: All dependencies explicitly declared and cryptographically verified
- **Centralized Auditing**: All dependency updates go through a single review process
- **Supply Chain Protection**: Content-addressed storage prevents tampering
- **Incident Response**: Quick rollback to known-good states

### For the Organization
- **Reproducible Environments**: Identical development and CI environments
- **High-Performance CI**: Buck2 remote caching with automatic cache invalidation via content-addressed toolchains
- **Ecosystem Compatibility**: Projects remain extractable as standard language packages
- **Patch Management**: Apply security fixes without waiting for upstream releases
- **Compliance**: Complete audit trail of all dependencies

## Getting Started

### Prerequisites

- [Nix](https://nixos.org/download) with flakes enabled
- Optional: [direnv](https://direnv.net/) for automatic environment activation

### Setup

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd src
   ```

2. Enter the development environment:
   ```bash
   nix develop
   # or with direnv:
   direnv allow
   ```

3. Build and run examples:
   ```bash
   buck2 build //experimental/rs-hello-world:rs-hello-world
   buck2 run //experimental/rs-hello-world:rs-hello-world
   ```

### Supported Languages

- **Rust**: Full toolchain with cargo integration
- **Go**: Complete Go toolchain with module support
- **Python**: Python 3 with pip and common tools
- **C/C++**: GCC/Clang toolchains
- **Nix**: For infrastructure and build configuration
- **Jsonnet**: Configuration and templating

## Documentation Structure

- **[Architecture](./architecture.md)**: Detailed technical architecture and design decisions
- **[Supply Chain Security](./supply-chain-security.md)**: Security model and dependency management

## Contributing

This documentation is built with [mdbook](https://rust-lang.github.io/mdBook/). To build locally:

```bash
cd docs
mdbook serve
```

The documentation will be available at `http://localhost:3000` with live reload enabled.
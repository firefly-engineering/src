# Firefly Engineering Monorepo

This is a monorepo setup with Nix environment and Buck2 build system.

## Prerequisites

- [Nix](https://nixos.org/download.html) installed
- [direnv](https://direnv.net/) installed (for automatic environment activation)

## Getting Started

1. **Activate the Nix environment:**
   ```bash
   direnv allow
   ```
   This will automatically activate the Nix shell with all required tools.

2. **Available tools:**
   - `git` - Version control
   - `jujutsu` - Modern Git-compatible VCS
   - `nix` - Package manager
   - `buck2` - Build system
   - `go` - Go programming language
   - `rust` - Rust programming language (including `cargo`, `rust-analyzer`, `rustfmt`, `clippy`)
   - `python3` - Python programming language
   - `llvm` - LLVM toolchain (including `clang`, `clang++`)

## Building and Running

Build any target with:
```bash
buck2 build //path/to/target
```

Run any binary target with:
```bash
buck2 run //path/to/target
```

## Project Organization

Projects can be organized anywhere in the repository. Common patterns include:
- `//experimental/` - For experimental and proof-of-concept projects
- `//apps/` - For applications
- `//libs/` - For shared libraries
- `//tools/` - For development tools

## Adding New Projects

1. Create a directory for your project
2. Add a `BUCK` file with your target definitions
3. Add your source files
4. Build with `buck2 build //your-project-path`

## Environment

The Nix environment provides a consistent development environment across different machines. All dependencies are managed through the `flake.nix` file.

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

## Building and Running

**Build the hello-world Rust example:**
```bash
buck2 build //hello-world
```

**Run the hello-world Rust example:**
```bash
buck2 run //hello-world
```

## Project Structure

```
.
├── .envrc              # direnv configuration for Nix environment
├── flake.nix           # Minimal Nix flake using flake-parts
├── nix/                # Nix modules directory
│   ├── default.nix     # Main flake-parts module with imports
│   └── shell.nix       # Development shell flake-parts module
├── .buckconfig         # Buck2 configuration
├── BUCK                # Root Buck2 build file
└── hello-world/        # Rust hello-world example
    ├── BUCK            # Buck2 target definition
    ├── Cargo.toml      # Rust package configuration
    └── main.rs         # Rust source code
```

## Adding New Projects

To add a new Rust project:

1. Create a new directory with your project name
2. Add a `BUCK` file with your `rust_binary` or `rust_library` target
3. Add your Rust source files
4. Build with `buck2 build //your-project-name`

## Environment

The Nix environment provides a consistent development environment across different machines. All dependencies are managed through the `flake.nix` file.

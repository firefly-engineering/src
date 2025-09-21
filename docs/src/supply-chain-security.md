# Supply Chain Security

## Table of Contents

1. [Overview](#overview)
2. [Threat Model](#threat-model)
3. [Nix as a Security Foundation](#nix-as-a-security-foundation)
4. [Dependency Auditing Process](#dependency-auditing-process)
5. [Mirror Repository Strategy](#mirror-repository-strategy)
6. [Verification and Integrity](#verification-and-integrity)
7. [Incident Response](#incident-response)
8. [Implementation Guidelines](#implementation-guidelines)

## Overview

Supply chain attacks have become increasingly sophisticated and prevalent, targeting the dependencies that modern software relies upon. Our Nix-based architecture provides multiple layers of protection against these threats while maintaining developer productivity and ecosystem compatibility.

The key insight is that **Nix's content-addressed storage and explicit dependency pinning creates natural audit points** where security reviews can be concentrated, rather than being scattered across individual project dependency updates.

## Threat Model

### Attack Vectors We Address

1. **Malicious Package Injection**
   - Compromised upstream repositories (PyPI, crates.io, npm)
   - Typosquatting attacks
   - Dependency confusion attacks

2. **Package Compromise**
   - Legitimate packages compromised post-publication
   - Maintainer account takeovers
   - Build system compromises

3. **Version Rollback Attacks**
   - Forcing downgrades to vulnerable versions
   - Bypassing security patches

4. **Transitive Dependency Attacks**
   - Malicious code in deep dependency trees
   - Unexpected dependency additions

### Attack Vectors Outside Our Scope

- **Source Code Repository Compromise**: Mitigated by standard Git security practices
- **Developer Machine Compromise**: Requires additional endpoint security measures
- **Build System Infrastructure**: Addressed by separate CI/CD security measures

## Nix as a Security Foundation

### Content-Addressed Storage

Nix's content-addressed store provides several security benefits:

```nix
# Example dependency specification with hash
rustPlatform.buildRustPackage rec {
  pname = "serde";
  version = "1.0.193";

  src = fetchCrate {
    inherit pname version;
    # Cryptographic hash ensures integrity
    sha256 = "sha256-abc123def456...";
  };

  # All transitive dependencies also hashed
  cargoHash = "sha256-xyz789uvw012...";
}
```

**Security Properties:**
- **Immutable References**: Once built, packages cannot be modified
- **Cryptographic Verification**: Hash mismatches prevent execution
- **Reproducible Builds**: Identical inputs produce identical outputs

### Explicit Dependency Pinning

Unlike traditional package managers that resolve versions dynamically, Nix requires explicit specification of all dependencies:

```nix
# nix/dependencies/rust.nix
{
  serde = {
    version = "1.0.193";
    hash = "sha256-abc123def456...";
    # Explicit transitive dependencies
    dependencies = {
      serde_derive = "1.0.193";
    };
  };
}
```

This eliminates several attack vectors:
- **No Version Resolution Surprises**: Dependencies cannot change without explicit updates
- **Transitive Visibility**: All dependencies are explicitly declared
- **Rollback Protection**: Downgrades require intentional configuration changes

## Dependency Auditing Process

### Centralized Audit Points

The Nix-based architecture creates natural audit checkpoints where security reviews can be concentrated:

```
Upstream Update → Nix Expression → Security Review → Monorepo Integration
      ↓               ↓               ↓                    ↓
   New version    Hash update    Audit process      Developer access
```

### Audit Workflow

1. **Dependency Update Detection**
   ```bash
   # Automated monitoring for new versions
   nix flake update --commit-lock-file
   # Or manual updates for specific packages
   ```

2. **Security Assessment**
   ```bash
   # Review changes since last version
   git diff flake.lock
   # Analyze new dependencies
   nix show-derivation .#dependency-name
   ```

3. **Approval Process**
   - Security team reviews Nix expression changes
   - Dependency diff analysis
   - Known vulnerability checks
   - License compliance verification

4. **Integration**
   - Approved changes merged to main branch
   - All projects automatically use new versions
   - Rollback available via Git history

### Audit Checklist

For each dependency update:

- [ ] **Version Legitimacy**: Verify version exists on upstream registry
- [ ] **Hash Verification**: Confirm hash matches downloaded content
- [ ] **Changelog Review**: Analyze changes since previous version
- [ ] **Vulnerability Scan**: Check against known CVE databases
- [ ] **License Compliance**: Ensure license compatibility
- [ ] **Transitive Dependencies**: Review new or updated sub-dependencies
- [ ] **Maintainer Verification**: Confirm legitimate maintainer published update

## Mirror Repository Strategy

### Architecture Overview

To provide additional security layers and patch capability, we maintain mirror repositories for critical dependencies:

```
Upstream Registry → Security Review → Mirror Repository → Nix Store → Monorepo
     (PyPI,               │              (firefly-deps/*)       │
      crates.io,          ▼                     │               ▼
      npm, etc.)    Patch Application           │         Build Process
                          │                     ▼
                          └── Patched Version ──┘
```

### Mirror Repository Structure

```
firefly-deps/
├── rust-crates/
│   ├── serde/
│   │   ├── 1.0.193/           # Original version
│   │   ├── 1.0.193-ff.1/      # Firefly-patched version
│   │   └── patches/
│   │       └── security-fix.patch
│   └── tokio/
├── go-modules/
│   └── github.com/
│       └── gorilla/
│           └── mux/
└── python-packages/
    └── requests/
```

### Mirror Benefits

1. **Change Visibility**: All modifications tracked in Git history
2. **Patch Management**: Security fixes applied without waiting for upstream
3. **Availability**: Resilience against upstream registry outages
4. **Compliance**: Internal review of all code that enters the organization
5. **Forensics**: Complete audit trail of all dependency changes

### Mirror Maintenance Process

```nix
# Example: Mirroring with patches
rustPlatform.buildRustPackage rec {
  pname = "vulnerable-crate";
  version = "1.0.0-ff.1";  # Firefly-patched version

  src = fetchFromGitHub {
    owner = "firefly-deps";
    repo = "rust-crates";
    path = "vulnerable-crate/1.0.0-ff.1";
    sha256 = "sha256-patched-version-hash...";
  };

  # Applied patches tracked in Git
  patches = [
    ./patches/cve-2023-12345.patch
  ];
}
```

## Verification and Integrity

### Multi-Layer Hash Verification

Our architecture provides multiple verification checkpoints:

1. **Download Verification**: Nix verifies source hashes during fetch
2. **Build Verification**: Nix verifies build output hashes
3. **Runtime Verification**: Store paths include content hashes
4. **Mirror Verification**: Git commits provide additional integrity

### Hash Chain Example

```
Original Package Hash → Mirror Repository Hash → Nix Store Hash → Runtime Path
sha256-upstream...   → git-commit-abc123...  → sha256-build... → /nix/store/hash-name
```

### Verification Commands

```bash
# Verify package integrity
nix store verify /nix/store/path-to-package

# Check all store paths
nix store verify --all

# Compare with expected hashes
nix show-derivation .#package | jq '.outputs'
```

## Incident Response

### Compromise Detection

1. **Hash Mismatches**: Nix build failures indicate potential tampering
2. **Unexpected Versions**: Monitoring alerts for dependency changes
3. **Vulnerability Reports**: Integration with security advisory feeds

### Response Process

1. **Immediate Containment**
   ```bash
   # Revert to known-good state
   git revert commit-hash
   nix flake update
   ```

2. **Impact Assessment**
   ```bash
   # Find affected projects
   nix why-depends .#project /nix/store/compromised-package

   # Check deployment status
   grep -r "compromised-package" buck-out/
   ```

3. **Remediation**
   - Update to patched version in mirrors
   - Force rebuild of affected components
   - Update Nix expressions with new hashes

4. **Recovery Verification**
   ```bash
   # Verify clean state
   nix store verify --all
   buck2 clean && buck2 build //...
   ```

## Implementation Guidelines

### Nix Expression Security

```nix
# GOOD: Explicit hashes and sources
fetchCrate {
  pname = "serde";
  version = "1.0.193";
  sha256 = "sha256-explicit-hash-here";
}

# BAD: Version ranges or dynamic resolution
fetchCrate {
  pname = "serde";
  version = "^1.0";  # Don't use version ranges
}

# GOOD: Pinned Git revisions
fetchFromGitHub {
  owner = "serde-rs";
  repo = "serde";
  rev = "specific-commit-hash";
  sha256 = "sha256-explicit-hash";
}

# BAD: Branch or tag references
fetchFromGitHub {
  owner = "serde-rs";
  repo = "serde";
  rev = "main";  # Branches can change
}
```

### Mirror Repository Setup

1. **Repository Creation**
   ```bash
   # Create mirror for each language ecosystem
   mkdir -p firefly-deps/{rust-crates,go-modules,python-packages}
   git init firefly-deps/
   ```

2. **Automated Mirroring**
   ```nix
   # Nix expression for automated mirroring
   let
     mirrorCrate = name: version: fetchCrate {
       inherit name version;
     } // {
       # Additional security metadata
       security-review = "2023-11-15";
       reviewer = "security-team";
     };
   in {
     serde = mirrorCrate "serde" "1.0.193";
   }
   ```

3. **Review Automation**
   ```bash
   #!/bin/bash
   # review-dependency.sh
   PACKAGE=$1
   VERSION=$2

   # Fetch and analyze
   nix build .#$PACKAGE
   nix run nixpkgs#vulnix -- /result

   # Generate review report
   echo "Security review for $PACKAGE $VERSION" > review-$PACKAGE-$VERSION.md
   ```

### Integration with Buck2

Buck2 toolchains should be configured to use only Nix-managed dependencies:

```python
# toolchains/rust.bzl
def firefly_rust_toolchain():
    return system_rust_toolchain(
        # Ensure toolchain uses Nix-provided rustc
        rustc = "rustc",  # From Nix environment
        # Environment variables set by Nix shell configure registry
        # No need for .cargo/config.toml modification
    )
```

**Registry Configuration via Environment Variables (set by Nix shell):**
```bash
# Non-intrusive configuration - no user file modification
export CARGO_HOME=$BUCK_OUT/cargo
export CARGO_REGISTRY_DEFAULT=firefly-crates
export CARGO_REGISTRIES_FIREFLY_CRATES_INDEX=file:///nix/store/.../registry-index
export CARGO_NET_OFFLINE=true
```

---

This security architecture transforms dependency management from a distributed, hard-to-audit process into a centralized, reviewable system. By leveraging Nix's cryptographic foundations and adding organizational mirror repositories, we create multiple security layers while maintaining developer productivity and ecosystem compatibility.

The key insight is that **security and usability are not opposing forces** when the architecture is designed correctly. Our approach provides stronger security guarantees than traditional approaches while actually simplifying the developer experience through consistent, reproducible environments.
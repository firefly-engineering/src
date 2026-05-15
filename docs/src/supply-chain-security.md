# Supply Chain Security

## Overview

Supply chain attacks target the dependencies modern software relies on. Nix's content-addressed storage and explicit pinning give us natural audit points where security review can be concentrated, rather than being scattered across individual project dependency updates.

## Threat Model

### In scope

1. **Malicious package injection** — compromised upstream repositories (PyPI, crates.io, npm), typosquatting, dependency confusion.
2. **Package compromise** — legitimate packages compromised post-publication, maintainer account takeovers, build system compromises.
3. **Version rollback attacks** — forced downgrades to vulnerable versions, bypassing security patches.
4. **Transitive dependency attacks** — malicious code in deep dependency trees, unexpected dependency additions.

### Out of scope

- **Source repository compromise** — mitigated by standard Git practices and branch protection.
- **Developer machine compromise** — requires endpoint security.
- **Build infrastructure compromise** — addressed by CI/CD security.

## Nix as a Security Foundation

### Content-addressed storage

Every derivation in `/nix/store/` is named by the hash of its build inputs. Once built, a path is immutable; any tampering changes the hash and the artifact is rejected.

- **Immutable references.** Built packages cannot be modified in place.
- **Cryptographic verification.** Hash mismatches prevent execution.
- **Reproducible builds.** Identical inputs produce identical outputs.

### Explicit pinning

`flake.lock` records the exact revision and hash of every input. Updates only happen through explicit `nix flake update`, which produces a reviewable diff. There is no dynamic version resolution at build time.

- **No surprise version changes** — dependencies cannot change without an explicit lock update.
- **Transitive visibility** — every dependency is captured in the lock graph.
- **Auditable rollbacks** — git history of `flake.lock` is the complete dependency timeline.

### Toolchain registry

Toolchain versions resolve through `toolchain.toml` → teller → toolbox. Each entry in toolbox's registry pins an SRI hash for the source archive (and `vendorHash` for Go modules). The registry repository itself is the single review surface for toolchain updates.

## Dependency Auditing

### Audit checkpoints

```
Upstream update → flake.lock / deps.toml change → review → merge
     ↓                       ↓                       ↓        ↓
 New version            Hash update            Audit       Developer access
```

### Workflow

1. **Detect.** `nix flake update` (or per-input `nix flake update <name>`) produces a `flake.lock` diff.
2. **Assess.** Read the diff in `flake.lock` / `go-deps.toml` / `rust-deps.toml`. Check upstream release notes, CVE databases, and the diff between old and new revisions.
3. **Approve.** Reviewer signs off on lock changes the same way they would code changes.
4. **Integrate.** Merge to main; all projects automatically pick up the new versions on their next pull.

### Checklist

For each update:

- [ ] Version exists on the upstream registry and matches the expected publisher.
- [ ] Hash in the lock / deps file matches downloaded content (`nix flake check` verifies this on build).
- [ ] Changelog reviewed for unexpected behavior.
- [ ] Known vulnerabilities checked (e.g. `vulnix`, `cargo-audit`, language-specific scanners).
- [ ] License is compatible.
- [ ] Transitive dependencies in the lock diff are reviewed.

## Verification and Integrity

Multiple verification points cover the lifecycle:

1. **Download verification** — Nix verifies source hashes during fetch.
2. **Build verification** — Nix verifies fixed-output derivation hashes.
3. **Runtime verification** — Store paths embed content hashes; tampering changes the path.

```bash
# Verify a specific store path
nix store verify /nix/store/<hash>-name

# Verify the entire store
nix store verify --all

# Inspect derivation outputs and inputs
nix show-derivation .#<package>
```

## Incident Response

### Detection signals

- **Hash mismatches** — Nix build failures during fetch/build indicate that an upstream artifact no longer matches its locked hash.
- **Unexpected lock changes** — review tools flagging changes to `flake.lock` / `*-deps.toml` outside an explicit update PR.
- **Vulnerability feeds** — advisories matching a pinned version.

### Response

1. **Contain.** Revert the lock to a known-good revision: `git revert <commit>`.
2. **Assess impact.** Use `nix why-depends .#<target> /nix/store/<compromised>` to find what depends on the affected derivation.
3. **Remediate.** Update to a patched upstream version, or apply a local patch in toolbox/teller until upstream ships a fix.
4. **Recover.** Rebuild and re-verify: `nix store verify --all && buck2 clean && buck2 build //...`.

## Implementation Guidelines

### Locking

```nix
# GOOD: explicit hashes via flake inputs
inputs.foo = { url = "github:owner/repo/<rev>"; flake = false; };

# AVOID: floating branches without a lock
inputs.foo.url = "github:owner/repo";  # OK only because flake.lock pins the rev
inputs.foo.url = "github:owner/repo/main";  # never pin a branch
```

### Patching

When upstream is slow to fix a CVE, apply a local patch via toolbox's `patches[]` mechanism (see `toolbox/AGENTS.md`). Patches are vendored in the repo with origin metadata for reproducibility and traceability.

### Buck2 hermiticity

Buck2 targets in this repo declare dependencies through the generated `godeps//` and `rustdeps//` cells, never through `~/.cargo` or `$GOPATH`. The cells are content-addressed Nix derivations, so a build is reproducible from the lock files alone — no network access needed at build time.

---

The architecture trades dynamic dependency resolution for explicit, auditable pins. The result is stronger security guarantees with **simpler** operations: every change to the dependency graph is a reviewable diff, and every artifact is content-addressed.

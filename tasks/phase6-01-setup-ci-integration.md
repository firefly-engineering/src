# Phase 6.1: CI/CD Integration Setup

## Overview

Configure CI/CD pipelines to use the toolchain synchronization system, ensuring CI builds use the same toolchains as local development and benefit from caching.

## Context

CI/CD should:
1. Use same toolchains as developers (via Nix)
2. Benefit from Buck2 caching (via remote cache)
3. Verify toolchain synchronization automatically
4. Monitor cache performance
5. Fail if generated configs are stale

### Key Goals

- **Reproducibility**: CI and local dev use identical toolchains
- **Speed**: Remote cache makes CI builds fast
- **Validation**: Catch configuration drift
- **Visibility**: Monitor cache effectiveness

## Prerequisites

- Phase 0: Toolchain module working
- Phase 1.2: Validation tools created
- Phase 2: Buck2 caching understood
- Access to CI/CD platform (GitHub Actions, GitLab CI, etc.)
- Understanding of CI/CD best practices

## Success Criteria

- [ ] CI installs and uses Nix
- [ ] CI enters Nix devShell for builds
- [ ] CI uses same toolchain paths as local dev
- [ ] CI validates toolchain synchronization
- [ ] CI checks generated configs are up-to-date
- [ ] Remote cache configured (optional but recommended)
- [ ] Cache hit rates monitored in CI
- [ ] Documentation for CI setup

## Implementation Guidance

### 1. GitHub Actions Configuration

Create `.github/workflows/build.yml`:

```yaml
name: Build and Test

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install Nix
        uses: cachix/install-nix-action@v24
        with:
          nix_path: nixpkgs=channel:nixos-unstable
          extra_nix_config: |
            experimental-features = nix-command flakes
            access-tokens = github.com=${{ secrets.GITHUB_TOKEN }}

      - name: Setup Nix Cache
        uses: cachix/cachix-action@v13
        with:
          name: my-cache
          authToken: '${{ secrets.CACHIX_AUTH_TOKEN }}'

      - name: Verify toolchain synchronization
        run: |
          nix develop --command ci-verify-toolchains

      - name: Check generated configs are up-to-date
        run: |
          nix develop --command bash -c "
            # Regenerate configs
            generate-buck2-configs

            # Check if anything changed
            if ! git diff --quiet .buckconfig.toolchains toolchains/; then
              echo '❌ Generated configs are stale!'
              echo 'Run generate-buck2-configs locally and commit changes'
              git diff .buckconfig.toolchains toolchains/
              exit 1
            else
              echo '✅ Generated configs are up-to-date'
            fi
          "

      - name: Build all targets
        run: |
          nix develop --command bash -c "
            buck2 build //...
          "

      - name: Run tests
        run: |
          nix develop --command bash -c "
            buck2 test //...
          "

      - name: Cache statistics
        run: |
          nix develop --command bash -c "
            buck2-cache-stats
            cache-health
          "
```

### 2. GitLab CI Configuration

Create `.gitlab-ci.yml`:

```yaml
variables:
  NIX_PATH: nixpkgs=channel:nixos-unstable

stages:
  - verify
  - build
  - test

before_script:
  # Install Nix
  - curl -L https://nixos.org/nix/install | sh
  - . ~/.nix-profile/etc/profile.d/nix.sh
  - echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf

verify:
  stage: verify
  script:
    - nix develop --command ci-verify-toolchains
    - nix develop --command bash -c "
        generate-buck2-configs
        git diff --exit-code .buckconfig.toolchains toolchains/
      "

build:
  stage: build
  script:
    - nix develop --command buck2 build //...
  artifacts:
    paths:
      - buck-out/
    expire_in: 1 day

test:
  stage: test
  dependencies:
    - build
  script:
    - nix develop --command buck2 test //...
```

### 3. CI Validation Script

Enhance `ci-verify-toolchains` for comprehensive checks:

```nix
let
  ciVerifyScript = pkgs.writeScriptBin "ci-verify-toolchains" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "::group::Environment Information"
    echo "CI Platform: ''${CI:-unknown}"
    echo "OS: $(uname -a)"
    echo "Nix version: $(nix --version)"
    echo "Buck2 version: $(buck2 --version)"
    echo "::endgroup::"

    echo "::group::Toolchain Paths"
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: deriv: ''
      echo "${name}: ${deriv}"
    '') resolved)}
    echo "::endgroup::"

    echo "::group::Toolchain Synchronization Check"
    ERRORS=()

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: deriv:
      if name == "go" then ''
        SHELL_GO=$(which go 2>/dev/null || echo "")
        BUCK2_GO=$(buck2 audit config go.go_bin 2>/dev/null || echo "")
        EXPECTED_GO="${deriv}/bin/go"

        if [ -z "$SHELL_GO" ]; then
          ERRORS+=("Go not found in PATH")
        elif [ "$SHELL_GO" != "$EXPECTED_GO" ]; then
          ERRORS+=("Go PATH mismatch: got $SHELL_GO, expected $EXPECTED_GO")
        fi

        if [ -z "$BUCK2_GO" ]; then
          ERRORS+=("Go not configured in Buck2")
        elif [ "$BUCK2_GO" != "$EXPECTED_GO" ]; then
          ERRORS+=("Buck2 Go mismatch: got $BUCK2_GO, expected $EXPECTED_GO")
        fi

        if [ "$SHELL_GO" = "$BUCK2_GO" ] && [ "$SHELL_GO" = "$EXPECTED_GO" ]; then
          echo "✅ Go: $SHELL_GO"
        fi
      ''
      else ""
    ) resolved)}

    echo "::endgroup::"

    if [ ''${#ERRORS[@]} -gt 0 ]; then
      echo "::group::Errors"
      for err in "''${ERRORS[@]}"; do
        echo "::error::$err"
      done
      echo "::endgroup::"
      exit 1
    else
      echo "::notice::All toolchains synchronized successfully"
      exit 0
    fi
  '';
in
```

### 4. Remote Cache Configuration (Optional)

**Using Cachix** (for Nix artifacts):

```yaml
# In GitHub Actions
- name: Setup Nix Cache
  uses: cachix/cachix-action@v13
  with:
    name: my-project
    authToken: '${{ secrets.CACHIX_AUTH_TOKEN }}'
```

**Using Buck2 Remote Cache**:

```ini
# .buckconfig.ci
[buck2_re_client]
enabled = true
engine_address = your-remote-cache.example.com:443
cas_address = your-remote-cache.example.com:443
action_cache_address = your-remote-cache.example.com:443
```

CI workflow:

```yaml
- name: Configure remote cache
  run: |
    cat >> .buckconfig <<EOF
    <file:.buckconfig.ci>
    EOF

- name: Build with remote cache
  env:
    BUCK2_RE_CLIENT_AUTH_TOKEN: ${{ secrets.BUCK2_CACHE_TOKEN }}
  run: |
    nix develop --command buck2 build //...
```

### 5. Config Staleness Check

Prevent stale generated configs:

```bash
#!/usr/bin/env bash
# check-configs-fresh.sh

set -euo pipefail

echo "Checking if generated configs are up-to-date..."

# Save current configs
cp .buckconfig.toolchains .buckconfig.toolchains.old
cp -r toolchains toolchains.old

# Regenerate
generate-buck2-configs

# Compare
if ! diff -r .buckconfig.toolchains .buckconfig.toolchains.old; then
  echo "❌ ERROR: .buckconfig.toolchains is stale!"
  echo ""
  echo "The committed config differs from what would be generated."
  echo "This usually means:"
  echo "  1. toolchain.toml changed but configs weren't regenerated"
  echo "  2. Registry changed but configs weren't updated"
  echo ""
  echo "Fix by running locally:"
  echo "  nix develop"
  echo "  generate-buck2-configs"
  echo "  git add .buckconfig.toolchains toolchains/"
  echo "  git commit -m 'chore: regenerate Buck2 configs'"
  exit 1
fi

if ! diff -r toolchains toolchains.old; then
  echo "❌ ERROR: toolchains/ directory is stale!"
  exit 1
fi

echo "✅ Generated configs are up-to-date"

# Cleanup
rm .buckconfig.toolchains.old
rm -rf toolchains.old
```

Add to CI:

```yaml
- name: Verify configs are fresh
  run: |
    nix develop --command ./check-configs-fresh.sh
```

### 6. Cache Performance Monitoring

Track cache effectiveness in CI:

```yaml
- name: Cache performance report
  run: |
    nix develop --command bash -c "
      # Build and capture metrics
      buck2 build //... 2>&1 | tee build.log

      # Extract cache stats (if Buck2 provides them)
      echo '::group::Cache Statistics'
      buck2-cache-stats
      echo '::endgroup::'

      # Log for analysis
      echo 'build_timestamp=$(date -Iseconds)' >> ci-metrics.log
      echo 'cache_entries=$(find .buck-cache -type f | wc -l)' >> ci-metrics.log
      echo 'cache_size=$(du -sb .buck-cache | cut -f1)' >> ci-metrics.log
    "

- name: Upload metrics
  uses: actions/upload-artifact@v3
  with:
    name: ci-metrics
    path: ci-metrics.log
```

### 7. Nix Store Caching in CI

Cache Nix store between CI runs:

**GitHub Actions**:

```yaml
- name: Cache Nix store
  uses: actions/cache@v3
  with:
    path: |
      /nix/store
      /nix/var/nix/db
    key: nix-${{ hashFiles('flake.lock') }}
    restore-keys: |
      nix-
```

**Note**: This can be large. Consider using Cachix instead.

### 8. Multi-Platform CI

Test on multiple platforms:

```yaml
jobs:
  build:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}

    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v24

      - name: Build
        run: nix develop --command buck2 build //...

      - name: Verify toolchains
        run: nix develop --command verify-toolchains
```

### 9. Documentation for CI Users

Create `docs/src/ci-cd.md`:

```markdown
# CI/CD Integration

## Overview

Our CI/CD pipelines use the same Nix-based toolchain synchronization
as local development, ensuring identical build environments.

## Setup for New Projects

### 1. Add GitHub Actions Workflow

Copy `.github/workflows/build.yml` from this repository.

### 2. Configure Secrets

Required secrets:
- `CACHIX_AUTH_TOKEN` - For Nix binary cache
- `BUCK2_CACHE_TOKEN` - For Buck2 remote cache (optional)

### 3. Test Locally

Before pushing:

```bash
# Ensure configs are up-to-date
nix develop
generate-buck2-configs
git add .buckconfig.toolchains toolchains/

# Test verification
nix develop --command ci-verify-toolchains
```

## Monitoring

### Cache Hit Rates

Check CI logs for cache statistics:

```
Cache entries: 1234
Cache size: 500MB
```

Low cache hit rate indicates:
- First build after toolchain change (expected)
- Remote cache not configured
- Cache key mismatch

### Build Performance

Track build times over time to ensure cache is effective.

## Troubleshooting

### "Generated configs are stale"

**Cause**: Committed configs don't match what CI generates

**Fix**:
```bash
nix develop
generate-buck2-configs
git commit -am "chore: update generated configs"
```

### "Toolchain synchronization failed"

**Cause**: Mismatch between shell and Buck2 toolchains in CI

**Fix**:
- Check that `generate-buck2-configs` runs before builds
- Verify `.buckconfig` includes `.buckconfig.toolchains`
```

## Implementation Steps

1. Create CI workflow file (GitHub Actions or GitLab CI)
2. Configure Nix installation in CI
3. Add toolchain verification step
4. Add config staleness check
5. Configure remote caching (optional)
6. Add cache monitoring
7. Test CI workflow
8. Document CI setup
9. Add multi-platform testing (optional)

## Testing

```bash
# Test CI workflow locally (GitHub Actions)
act -j build

# Or use Nix to simulate CI environment
nix develop --command bash -c "
  ci-verify-toolchains
  ./check-configs-fresh.sh
  buck2 build //...
  buck2 test //...
"

# Verify configs freshness
./check-configs-fresh.sh
```

## Related Documentation

- Tasks: `TASKS.md` (Phase 6)
- Phase 1.2: Validation tools
- Phase 2: Caching
- User Guide: CI/CD integration

## Next Steps

After completing this task:
- Phase 7: Alternative backend exploration
- Phase 8: Repository extraction

## Notes

- **Reproducibility**: CI must match local dev exactly
- **Speed**: Remote cache is crucial for CI performance
- **Validation**: Catch drift early with automated checks
- **Monitoring**: Track cache effectiveness over time
- **Documentation**: Clear CI setup instructions critical
- **Security**: Protect cache tokens and credentials
- **Cost**: Monitor CI minutes usage, optimize build times
- **Multi-platform**: Test on all supported platforms

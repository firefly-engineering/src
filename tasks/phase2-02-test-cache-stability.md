# Phase 2.2: Test Buck2 Cache Stability

## Overview

Verify that Buck2 cache remains stable and effective across shell re-entries and across different machines (when using the same `flake.lock`).

## Context

For the cache to be truly useful, it must be:

1. **Stable across shell sessions**: Re-entering `nix develop` shouldn't invalidate cache
2. **Reproducible across machines**: Same `flake.lock` = same toolchain paths = shareable cache (in principle)
3. **Deterministic**: Same inputs always produce same outputs

This phase validates these stability properties.

### Why This Matters

**Across shell sessions**:
```bash
# Session 1
nix develop
buck2 build //...  # Creates cache

# Session 2
exit
nix develop
buck2 build //...  # Should use cache from session 1 ✅
```

**Across machines**:
```bash
# Machine A
buck2 build //...
# Produces: /nix/store/abc-go-1.21.5

# Machine B (same flake.lock)
which go
# /nix/store/abc-go-1.21.5  ← Same path!
# → Cache entries from Machine A could work on Machine B
```

## Prerequisites

- Phase 2.1: Local caching validated
- Multiple test environments available (or VM/container)
- Understanding of Nix flake locking mechanism
- Access to multiple machines or Docker for testing

## Success Criteria

- [ ] Cache persists across shell re-entries
- [ ] Cache hit rate >90% after re-entering shell
- [ ] Same `flake.lock` produces identical toolchain paths on different machines
- [ ] Cache is deterministic (repeated builds identical)
- [ ] Documentation explains cache stability expectations

## Implementation Guidance

### 1. Test Cache Across Shell Re-Entries

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Testing Cache Stability Across Shell Sessions"
echo "=============================================="

# Session 1: Build and cache
echo ""
echo "Session 1: Initial build"
nix develop --command bash -c "
  buck2 clean
  buck2 build //...
  echo 'Cache created'
"

# Session 2: Rebuild
echo ""
echo "Session 2: Rebuild in new shell"
nix develop --command bash -c "
  echo 'Re-entered shell'
  which go  # Verify toolchain still available

  # Time the rebuild
  time buck2 build //...
  echo 'Should be instant (cache hit)'
"

# Verify cache was used
echo ""
echo "Verification:"
nix develop --command bash -c "
  # Check if Buck2 reports cache hits
  buck2 build //... --verbose 2>&1 | grep -i 'cache' || true
"

echo ""
echo "✅ Cache stability test complete"
```

### 2. Test Determinism

Verify builds are deterministic:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Testing Build Determinism"
echo "========================="

nix develop --command bash -c "
  # Build 1
  buck2 clean
  buck2 build //src:app
  cp buck-out/v2/gen/src/app/app build1

  # Build 2 (clean rebuild)
  buck2 clean
  buck2 build //src:app
  cp buck-out/v2/gen/src/app/app build2

  # Compare
  if cmp -s build1 build2; then
    echo '✅ Builds are deterministic'
    sha256sum build1 build2
  else
    echo '❌ Builds are non-deterministic!'
    exit 1
  fi
"
```

### 3. Test Cross-Machine Consistency

Test that same flake.lock produces same paths:

**On Machine A**:

```bash
#!/usr/bin/env bash
# save-toolchain-paths.sh

echo "Saving toolchain paths from Machine A..."

nix develop --command bash -c "
  cat > toolchain-paths-machineA.txt <<EOF
SYSTEM: $(uname -sm)
FLAKE_LOCK_HASH: $(sha256sum flake.lock | cut -d' ' -f1)
GO_PATH: $(which go)
GO_VERSION: $(go version)
RUST_PATH: $(which rustc)
BUCK2_GO: $(buck2 audit config go.go_bin)
BUCK2_RUST: $(buck2 audit config rust.rustc_bin)
EOF

  cat toolchain-paths-machineA.txt
"

# Save this file and flake.lock for comparison on Machine B
```

**On Machine B**:

```bash
#!/usr/bin/env bash
# compare-toolchain-paths.sh

echo "Comparing toolchain paths on Machine B..."

# Prerequisites:
# 1. Copy flake.lock from Machine A
# 2. Copy toolchain-paths-machineA.txt from Machine A

# Verify flake.lock is identical
LOCK_A=$(cat toolchain-paths-machineA.txt | grep FLAKE_LOCK_HASH | cut -d' ' -f2)
LOCK_B=$(sha256sum flake.lock | cut -d' ' -f1)

if [ "$LOCK_A" != "$LOCK_B" ]; then
  echo "❌ flake.lock files don't match!"
  echo "   Machine A: $LOCK_A"
  echo "   Machine B: $LOCK_B"
  exit 1
fi

echo "✅ flake.lock files match"

# Compare toolchain paths
nix develop --command bash -c "
  GO_A=$(cat toolchain-paths-machineA.txt | grep 'GO_PATH:' | cut -d' ' -f2)
  GO_B=$(which go)

  RUST_A=$(cat toolchain-paths-machineA.txt | grep 'RUST_PATH:' | cut -d' ' -f2)
  RUST_B=$(which rustc)

  echo ''
  echo 'Toolchain Path Comparison:'
  echo '=========================='
  echo \"Go:\"
  echo \"  Machine A: \$GO_A\"
  echo \"  Machine B: \$GO_B\"

  if [ \"\$GO_A\" = \"\$GO_B\" ]; then
    echo \"  ✅ Paths match\"
  else
    echo \"  ⚠️  Paths differ (may be due to different architectures)\"
  fi

  echo \"\"
  echo \"Rust:\"
  echo \"  Machine A: \$RUST_A\"
  echo \"  Machine B: \$RUST_B\"

  if [ \"\$RUST_A\" = \"\$RUST_B\" ]; then
    echo \"  ✅ Paths match\"
  else
    echo \"  ⚠️  Paths differ (may be due to different architectures)\"
  fi
"
```

### 4. Test Cache After Flake Update

Verify behavior when nixpkgs updates:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Testing Cache After Flake Update"
echo "================================="

# Save current state
cp flake.lock flake.lock.backup

# Build with current flake.lock
echo ""
echo "1. Build with current flake.lock..."
nix develop --command bash -c "
  buck2 clean
  buck2 build //...
  GO_BEFORE=$(which go)
  echo \"Go path: \$GO_BEFORE\"
  echo \"\$GO_BEFORE\" > go-path-before.txt
"

# Update flake
echo ""
echo "2. Updating flake..."
nix flake update

# Rebuild
echo ""
echo "3. Rebuild after flake update..."
nix develop --command bash -c "
  GO_AFTER=$(which go)
  echo \"Go path: \$GO_AFTER\"

  GO_BEFORE=$(cat go-path-before.txt)

  if [ \"\$GO_BEFORE\" != \"\$GO_AFTER\" ]; then
    echo \"\"
    echo \"⚠️  Flake update changed Go path:\"
    echo \"   Before: \$GO_BEFORE\"
    echo \"   After:  \$GO_AFTER\"
    echo \"\"
    echo \"This is expected if nixpkgs updated the Go package.\"
    echo \"Cache will be invalidated (different path = different hash).\"
  else
    echo \"\"
    echo \"✅ Flake update did not change Go path\"
    echo \"Cache remains valid.\"
  fi

  # Rebuild to test cache behavior
  echo \"\"
  echo \"Building with potentially updated toolchain...\"
  buck2 build //...
"

# Restore original flake.lock
mv flake.lock.backup flake.lock
```

### 5. Test Container/Docker Reproducibility

Use Docker to test cross-environment consistency:

```dockerfile
# Dockerfile for testing
FROM nixos/nix:latest

# Enable flakes
RUN echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

WORKDIR /workspace

# Copy project
COPY . .

# Test build
RUN nix develop --command bash -c " \
    buck2 build //... && \
    which go > /tmp/go-path.txt && \
    buck2 audit config go.go_bin >> /tmp/go-path.txt \
    "

# Print paths for comparison
CMD cat /tmp/go-path.txt
```

Test:

```bash
# Build on host
nix develop --command bash -c "which go" > host-go-path.txt

# Build in Docker
docker build -t test-toolchain-stability .
docker run test-toolchain-stability > docker-go-path.txt

# Compare
diff host-go-path.txt docker-go-path.txt
# May differ due to architecture, but structure should be identical
```

### 6. Monitor Cache Statistics

Track cache behavior over time:

```bash
#!/usr/bin/env bash
# cache-stability-monitor.sh

STATS_FILE=".cache-stats.log"

log_cache_stats() {
  local event="$1"

  TIMESTAMP=$(date -Iseconds)
  CACHE_ENTRIES=$(find .buck-cache -type f 2>/dev/null | wc -l || echo 0)
  CACHE_SIZE=$(du -sh .buck-cache 2>/dev/null | cut -f1 || echo "0")

  echo "$TIMESTAMP | $event | Entries: $CACHE_ENTRIES | Size: $CACHE_SIZE" >> "$STATS_FILE"
}

# Usage:
# log_cache_stats "After build"
# log_cache_stats "After shell re-entry"
# log_cache_stats "After toolchain change"
```

## Implementation Steps

1. Create test script for shell re-entry stability
2. Create test script for build determinism
3. Set up cross-machine testing (2+ machines or containers)
4. Test cross-machine path consistency
5. Test flake update behavior
6. Create Docker-based reproducibility test
7. Create cache monitoring tools
8. Document findings and expected behaviors
9. Update user documentation with cache stability guarantees

## Testing

```bash
# Test 1: Shell re-entry
./test-shell-reentry.sh
# Expected: Cache persists, instant rebuild

# Test 2: Determinism
./test-determinism.sh
# Expected: Identical binaries

# Test 3: Cross-machine (requires 2 machines)
# Machine A:
./save-toolchain-paths.sh
# → Copy flake.lock and paths file to Machine B

# Machine B:
./compare-toolchain-paths.sh
# Expected: Paths match (same architecture)

# Test 4: Flake update
./test-flake-update.sh
# Expected: May invalidate cache if package changed

# Test 5: Docker
docker build -t test-stability .
docker run test-stability
# Expected: Deterministic paths
```

## Related Documentation

- Design: `docs/src/design/toolchain-synchronization.md`
- Tasks: `TASKS.md` (Phase 2.2)
- Nix Manual: Flake lock files
- Buck2 Docs: Caching mechanism

## Next Steps

After completing this task:
- Phase 2.3: Create monitoring and debugging tools (`phase2-03-create-monitoring-tools.md`)

## Notes

- **Flake locking**: `flake.lock` ensures reproducibility across machines
- **Architecture differences**: x86_64 vs aarch64 will have different paths (expected)
- **Same arch = same path**: Crucial property for cache sharing
- **Remote cache**: Would enable actual cache sharing (Phase 2.3 optional)
- **Documentation**: Users need to understand when cache invalidates vs. when it persists
- **Determinism**: Critical for reproducible builds and cache effectiveness
- **Monitoring**: Track cache stability over weeks/months

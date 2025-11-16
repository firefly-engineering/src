# Phase 2.1: Validate Buck2 Local Caching

## Overview

Verify that Buck2's local caching works correctly with Nix-based toolchains and that toolchain changes properly trigger cache invalidation.

## Context

Buck2's caching is based on **input hashes**. When we change toolchains:
- Nix store path changes (content-addressed)
- Buck2 sees different path = different input hash
- Buck2 cache automatically invalidates (cache miss expected)
- New cache entries created with new toolchain

This phase validates that this automatic cache invalidation works correctly.

### Key Insight

The Nix store path **IS** the cache key. No manual invalidation needed:

```
Go 1.21.5: /nix/store/abc123-go-1.21.5/bin/go  → Cache key: abc123...
Go 1.22.0: /nix/store/def456-go-1.22.0/bin/go  → Cache key: def456...

Different path = Different cache key = Automatic invalidation ✅
```

## Prerequisites

- Phase 0: Module implementation complete
- Phase 1: Validation tools created
- Working project with Buck2 builds
- Understanding of Buck2 caching mechanism

## Success Criteria

- [ ] Local Buck2 cache configured and working
- [ ] Initial build creates cache entries
- [ ] Toolchain change triggers cache invalidation (rebuild)
- [ ] Unchanged toolchain uses cache (no rebuild)
- [ ] Cache hit rate measurable and >80% for incremental builds
- [ ] Patch application invalidates cache correctly

## Implementation Guidance

### 1. Configure Local Buck2 Cache

Update `.buckconfig`:

```ini
[buck2]
# Enable local caching
cache_dir = .buck-cache

[buck2_re_client]
# Enable local execution cache
enabled = true
```

### 2. Create Test Project

Need a project substantial enough to show cache benefit:

```
test-project/
├── toolchain.toml
├── .buckconfig
├── src/
│   ├── BUCK
│   ├── main.go
│   ├── utils.go
│   └── helpers.go
└── tests/
    ├── BUCK
    └── main_test.go
```

`src/BUCK`:

```python
go_library(
    name = "lib",
    srcs = glob(["*.go"], exclude = ["*_test.go"]),
)

go_binary(
    name = "app",
    deps = [":lib"],
)
```

### 3. Test Script for Cache Validation

Create comprehensive test:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "═══════════════════════════════════════"
echo "Buck2 Cache Validation Test"
echo "═══════════════════════════════════════"
echo ""

# Clean everything
echo "1. Clean build..."
buck2 clean
rm -rf .buck-cache
rm -f .toolchain-versions.cache

# Initial build
echo ""
echo "2. Initial build (cache cold)..."
time buck2 build //src:app
echo "   → Cache should be empty, full build expected"

# Rebuild without changes
echo ""
echo "3. Rebuild without changes (cache warm)..."
time buck2 build //src:app
echo "   → Cache should be hit, instant build expected"

# Get cache stats
echo ""
echo "4. Cache stats..."
buck2 status | grep -i cache || echo "   (Cache stats not available)"

# Change toolchain
echo ""
echo "5. Changing Go version..."
echo "   Current: $(grep version toolchain.toml)"
sed -i.bak 's/version = "1.21.5"/version = "1.22.0"/' toolchain.toml
echo "   New: $(grep version toolchain.toml)"

# Exit and re-enter shell to pick up new toolchain
echo ""
echo "6. Regenerating Buck2 config with new toolchain..."
nix develop --command generate-buck2-configs

echo "   Old Go: $(cat .toolchain.toml.bak | grep go)"
echo "   New Go: $(buck2 audit config go.go_bin)"

# Rebuild with new toolchain
echo ""
echo "7. Build with new toolchain (cache miss expected)..."
time buck2 build //src:app
echo "   → Different toolchain = cache miss = rebuild expected"

# Rebuild again with same (new) toolchain
echo ""
echo "8. Rebuild with same toolchain (cache hit expected)..."
time buck2 build //src:app
echo "   → Same toolchain = cache hit = instant expected"

# Restore original
mv toolchain.toml.bak toolchain.toml

echo ""
echo "═══════════════════════════════════════"
echo "✅ Cache validation complete"
echo "═══════════════════════════════════════"
```

### 4. Measure Cache Hit Rate

Create monitoring tool:

```bash
#!/usr/bin/env bash
# cache-stats.sh

echo "Buck2 Cache Statistics"
echo "======================"

# Count cache entries
if [ -d .buck-cache ]; then
  ENTRIES=$(find .buck-cache -type f | wc -l)
  SIZE=$(du -sh .buck-cache | cut -f1)
  echo "Cache entries: $ENTRIES"
  echo "Cache size: $SIZE"
else
  echo "No cache directory found"
fi

# Parse build logs for cache hits/misses if available
# (Buck2 may expose this via API or logs)

echo ""
echo "Recent builds:"
buck2 log what-ran | tail -20
```

### 5. Test Patch Application

Verify that applying patches invalidates cache:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Testing cache invalidation with patches..."

# Build with unpatched toolchain
echo ""
echo "1. Build with Go 1.21.5 (unpatched)..."
cat > toolchain.toml <<EOF
[go]
version = "1.21.5"
EOF

nix develop --command bash -c "
  generate-buck2-configs
  buck2 clean
  buck2 build //src:app
"

GO_PATH_BEFORE=$(buck2 audit config go.go_bin)
echo "   Go path: $GO_PATH_BEFORE"

# Create registry with patched Go
echo ""
echo "2. Create custom registry with patched Go..."
cat > custom-registry.nix <<'EOF'
{ pkgs }:
{
  go = {
    "1.21.5" = pkgs.go_1_21;  # Unpatched

    "1.21.5-patched" = pkgs.go_1_21.overrideAttrs (old: {
      pname = "go-patched";
      patches = (old.patches or []) ++ [
        (pkgs.writeText "example.patch" ''
          # Example patch (does nothing, just for testing)
        '')
      ];
    });
  };
}
EOF

# Update flake to use custom registry
# (User would do this in their flake.nix)

# Update toolchain.toml to use patched version
cat > toolchain.toml <<EOF
[go]
version = "1.21.5-patched"
EOF

echo ""
echo "3. Build with patched Go..."
nix develop --command bash -c "
  generate-buck2-configs
  buck2 build //src:app
"

GO_PATH_AFTER=$(buck2 audit config go.go_bin)
echo "   Go path: $GO_PATH_AFTER"

# Verify paths are different
if [ "$GO_PATH_BEFORE" != "$GO_PATH_AFTER" ]; then
  echo ""
  echo "✅ Patch changed Nix store path"
  echo "   Before: $GO_PATH_BEFORE"
  echo "   After:  $GO_PATH_AFTER"
  echo "   → Cache invalidated automatically"
else
  echo ""
  echo "❌ ERROR: Patch did not change Nix store path!"
  echo "   Cache invalidation may not work correctly"
  exit 1
fi
```

### 6. Benchmark Cache Performance

Measure actual impact:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Buck2 Cache Performance Benchmark"
echo "=================================="

# Warm up
buck2 build //...

# Benchmark: Clean build
echo ""
echo "Test 1: Clean build (no cache)"
buck2 clean
rm -rf .buck-cache
time buck2 build //... 2>&1 | tee build-clean.log
CLEAN_TIME=$(grep real build-clean.log | awk '{print $2}')

# Benchmark: Cached build
echo ""
echo "Test 2: Rebuild (with cache)"
time buck2 build //... 2>&1 | tee build-cached.log
CACHED_TIME=$(grep real build-cached.log | awk '{print $2}')

# Calculate speedup
echo ""
echo "Results:"
echo "--------"
echo "Clean build:  $CLEAN_TIME"
echo "Cached build: $CACHED_TIME"
echo ""
# (Would calculate speedup ratio here)

# Benchmark: After toolchain change
echo ""
echo "Test 3: After toolchain change"
# Change toolchain
sed -i.bak 's/version = "1.21.5"/version = "1.22.0"/' toolchain.toml
nix develop --command generate-buck2-configs
time buck2 build //... 2>&1 | tee build-new-toolchain.log
NEW_TOOLCHAIN_TIME=$(grep real build-new-toolchain.log | awk '{print $2}')

echo ""
echo "After toolchain change: $NEW_TOOLCHAIN_TIME"
echo "(Should be similar to clean build)"
```

### 7. Add Cache Monitoring to devShell

```nix
let
  cacheStatsScript = pkgs.writeScriptBin "buck2-cache-stats" ''
    #!/usr/bin/env bash
    echo "Buck2 Cache Status"
    echo "=================="

    if [ -d .buck-cache ]; then
      echo "Entries: $(find .buck-cache -type f | wc -l)"
      echo "Size:    $(du -sh .buck-cache | cut -f1)"
    else
      echo "No cache found (run 'buck2 build' first)"
    fi
  '';
in
{
  devShells.default = pkgs.mkShell {
    packages = toolchainPackages ++ [ cacheStatsScript ];
  };
}
```

## Implementation Steps

1. Configure Buck2 local cache in `.buckconfig`
2. Create test project with multiple targets
3. Create cache validation test script
4. Run tests: cold cache, warm cache, toolchain change
5. Measure and document cache hit rates
6. Test patch application and cache invalidation
7. Benchmark cache performance impact
8. Add cache monitoring tools
9. Document findings and best practices

## Testing

```bash
# Run comprehensive cache validation
./test-buck2-cache.sh

# Expected results:
# - Cold build: Slow, creates cache
# - Warm build: Fast, uses cache
# - After toolchain change: Slow (cache miss), creates new cache
# - After second build: Fast (cache hit with new toolchain)

# Measure cache hit rate
buck2 build //...  # First build
buck2 build //...  # Should be instant
# Ideal: >95% cache hit rate on rebuild

# Test with real project
cd experimental/go-hello-world
buck2 clean && buck2 build //...  # Time this
buck2 build //...                  # Should be instant
```

## Related Documentation

- Design: `docs/src/design/toolchain-synchronization.md` (section 6: "Buck2 Caching")
- Architecture: `docs/src/architecture.md`
- Tasks: `TASKS.md` (Phase 2.1)
- Buck2 Docs: https://buck2.build/docs/concepts/build_rule/

## Next Steps

After completing this task:
- Phase 2.2: Test cache stability across machines (`phase2-02-test-cache-stability.md`)
- Phase 2.3: Create monitoring tools (`phase2-03-create-monitoring-tools.md`)

## Notes

- **Automatic invalidation**: The key insight is that we get automatic cache invalidation for free
- **Performance**: Cache hit should be near-instant (milliseconds)
- **Size**: Monitor cache growth over time
- **CI**: Local cache works well for development; remote cache needed for CI (optional)
- **Metrics**: Track cache hit rate to ensure system is working
- **Debugging**: If cache doesn't invalidate, verify Nix store paths changed
- **Documentation**: Document expected cache behavior for users

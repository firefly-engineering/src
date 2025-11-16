# Phase 2.3: Create Cache Monitoring and Debugging Tools

## Overview

Create tools to monitor Buck2 cache performance, debug cache misses, and help users optimize their cache hit rates. These tools provide visibility into the caching system.

## Context

Even with automatic cache invalidation working correctly, users need tools to:

1. **Monitor**: Track cache hit rates over time
2. **Debug**: Understand why cache missed when expected to hit
3. **Optimize**: Identify opportunities to improve cache effectiveness
4. **Troubleshoot**: Diagnose cache-related problems

### Key Metrics

- **Cache hit rate**: Percentage of actions served from cache
- **Cache size**: Disk space used by cache
- **Cache entry count**: Number of cached artifacts
- **Build speedup**: Cached vs. uncached build time
- **Toolchain fingerprints**: Track toolchain changes

## Prerequisites

- Phase 2.1: Local caching validated
- Phase 2.2: Cache stability tested
- Understanding of Buck2 logging and audit commands
- Familiarity with cache behavior

## Success Criteria

- [ ] Tool to display current cache hit rate
- [ ] Tool to show cache growth over time
- [ ] Tool to compare toolchain fingerprints (detect changes)
- [ ] Tool to debug individual cache misses
- [ ] Dashboard or report showing cache health
- [ ] CI integration for monitoring cache in builds
- [ ] Documentation on using monitoring tools

## Implementation Guidance

### 1. Cache Hit Rate Monitor

Create tool to extract and display cache statistics:

```nix
let
  cacheStatsScript = pkgs.writeScriptBin "buck2-cache-stats" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "╔════════════════════════════════════════╗"
    echo "║     Buck2 Cache Statistics             ║"
    echo "╚════════════════════════════════════════╝"
    echo ""

    # Cache directory stats
    if [ -d .buck-cache ]; then
      ENTRIES=$(find .buck-cache -type f | wc -l)
      SIZE=$(du -sh .buck-cache | cut -f1)
      OLDEST=$(find .buck-cache -type f -printf '%T+ %p\n' | sort | head -1 | cut -d' ' -f1)
      NEWEST=$(find .buck-cache -type f -printf '%T+ %p\n' | sort | tail -1 | cut -d' ' -f1)

      echo "📁 Cache Directory: .buck-cache"
      echo "   Entries: $ENTRIES"
      echo "   Size:    $SIZE"
      echo "   Oldest:  $OLDEST"
      echo "   Newest:  $NEWEST"
    else
      echo "❌ No cache directory found"
      echo "   Run 'buck2 build' to create cache"
      exit 0
    fi

    # Recent build statistics
    echo ""
    echo "📊 Recent Build Stats:"

    # Parse Buck2 logs for cache metrics
    # Note: Buck2 may expose this via API or logs
    if command -v buck2 &> /dev/null; then
      echo "   (Analyzing Buck2 logs...)"

      # Example: Extract from build logs
      # This is illustrative - actual implementation depends on Buck2 log format
      LAST_BUILD=$(buck2 log last 2>/dev/null || echo "")

      if [ -n "$LAST_BUILD" ]; then
        # Parse for cache hits/misses
        # (Format depends on Buck2 version)
        echo "   Last build: $LAST_BUILD"
      else
        echo "   No recent build logs found"
      fi
    fi

    echo ""
  '';
in
```

### 2. Toolchain Fingerprint Tracker

Track toolchain changes and predict cache invalidation:

```nix
let
  toolchainFingerprintScript = pkgs.writeScriptBin "toolchain-fingerprint" ''
    #!/usr/bin/env bash
    set -euo pipefail

    FINGERPRINT_FILE=".toolchain-fingerprint"

    # Generate current fingerprint
    generate_fingerprint() {
      cat <<EOF
# Toolchain Fingerprint
# Generated: $(date -Iseconds)

${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: deriv: ''
${name}_path=${deriv}
${name}_hash=$(echo "${deriv}" | cut -d'-' -f1 | cut -d'/' -f4)
'') resolved)}

# toolchain.toml hash
toml_hash=$(sha256sum toolchain.toml | cut -d' ' -f1)

# flake.lock hash
lock_hash=$(sha256sum flake.lock | cut -d' ' -f1)
EOF
    }

    # Show current fingerprint
    if [ "$1" = "show" ]; then
      generate_fingerprint

    # Compare with previous
    elif [ "$1" = "compare" ]; then
      if [ ! -f "$FINGERPRINT_FILE" ]; then
        echo "No previous fingerprint found"
        echo "Run 'toolchain-fingerprint save' after building"
        exit 1
      fi

      echo "Comparing fingerprints..."
      echo ""

      CURRENT=$(generate_fingerprint)
      PREVIOUS=$(cat "$FINGERPRINT_FILE")

      if [ "$CURRENT" = "$PREVIOUS" ]; then
        echo "✅ Fingerprints match - cache should be valid"
      else
        echo "⚠️  Fingerprints differ - cache will invalidate"
        echo ""
        echo "Differences:"
        diff <(echo "$PREVIOUS") <(echo "$CURRENT") || true
        echo ""
        echo "Expected behavior: Buck2 cache miss on next build"
      fi

    # Save current fingerprint
    elif [ "$1" = "save" ]; then
      generate_fingerprint > "$FINGERPRINT_FILE"
      echo "✅ Fingerprint saved to $FINGERPRINT_FILE"

    else
      echo "Usage: toolchain-fingerprint {show|compare|save}"
      echo ""
      echo "Commands:"
      echo "  show    - Display current toolchain fingerprint"
      echo "  compare - Compare current vs saved fingerprint"
      echo "  save    - Save current fingerprint for later comparison"
    fi
  '';
in
```

### 3. Cache Miss Debugger

Tool to understand why cache missed:

```nix
let
  cacheMissDebugScript = pkgs.writeScriptBin "debug-cache-miss" ''
    #!/usr/bin/env bash
    set -euo pipefail

    TARGET="$1"

    if [ -z "$TARGET" ]; then
      echo "Usage: debug-cache-miss <target>"
      echo "Example: debug-cache-miss //src:app"
      exit 1
    fi

    echo "Debugging cache miss for: $TARGET"
    echo "=================================="
    echo ""

    # Show target's dependencies
    echo "📦 Dependencies:"
    buck2 uquery "deps($TARGET)" --output-attribute=name

    echo ""
    echo "🔧 Toolchain Configuration:"
    buck2 audit config go rust python cxx

    echo ""
    echo "📋 Target Rule:"
    buck2 uquery "$TARGET" --output-attribute='*'

    echo ""
    echo "🔍 Action Analysis:"
    buck2 audit actions "$TARGET" | head -20

    echo ""
    echo "💡 Common causes of cache miss:"
    echo "   • Toolchain version changed (check: toolchain-fingerprint compare)"
    echo "   • Source file modified (check: git status)"
    echo "   • Dependency changed (check: buck2 uquery deps)"
    echo "   • Build rule changed (check: git diff BUCK)"
    echo "   • Environment variable changed"
  '';
in
```

### 4. Cache Health Dashboard

Comprehensive cache health report:

```nix
let
  cacheHealthScript = pkgs.writeScriptBin "cache-health" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "╔══════════════════════════════════════════════╗"
    echo "║        Buck2 Cache Health Report             ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""

    # 1. Cache Size Health
    echo "📊 Cache Size:"
    if [ -d .buck-cache ]; then
      SIZE_BYTES=$(du -sb .buck-cache | cut -f1)
      SIZE_HUMAN=$(du -sh .buck-cache | cut -f1)
      ENTRIES=$(find .buck-cache -type f | wc -l)

      echo "   Size: $SIZE_HUMAN ($SIZE_BYTES bytes)"
      echo "   Entries: $ENTRIES"

      # Warn if cache is very large
      if [ "$SIZE_BYTES" -gt 10000000000 ]; then  # 10GB
        echo "   ⚠️  Cache is large (>10GB) - consider cleaning old entries"
      else
        echo "   ✅ Cache size is healthy"
      fi
    else
      echo "   ❌ No cache found"
    fi

    # 2. Toolchain Synchronization
    echo ""
    echo "🔧 Toolchain Synchronization:"
    if verify-toolchains --quiet 2>/dev/null; then
      echo "   ✅ All toolchains synchronized"
    else
      echo "   ❌ Toolchain mismatch detected"
      echo "      Run: verify-toolchains"
    fi

    # 3. Fingerprint Status
    echo ""
    echo "🔐 Fingerprint Status:"
    if [ -f .toolchain-fingerprint ]; then
      if toolchain-fingerprint compare --quiet 2>/dev/null; then
        echo "   ✅ Fingerprint unchanged since last save"
      else
        echo "   ⚠️  Fingerprint changed - cache may invalidate"
        echo "      Run: toolchain-fingerprint compare"
      fi
    else
      echo "   ℹ️  No baseline fingerprint"
      echo "      Run: toolchain-fingerprint save"
    fi

    # 4. Recent Build Performance
    echo ""
    echo "⚡ Build Performance:"
    if [ -f .cache-stats.log ]; then
      echo "   Recent cache stats:"
      tail -5 .cache-stats.log | sed 's/^/   /'
    else
      echo "   No performance data available"
      echo "   Run builds and use log_cache_stats"
    fi

    # 5. Recommendations
    echo ""
    echo "💡 Recommendations:"

    # Check if cache is disabled
    if ! grep -q "cache_dir" .buckconfig; then
      echo "   • Enable local caching in .buckconfig"
    fi

    # Check if cache is very small
    if [ -d .buck-cache ]; then
      if [ "$ENTRIES" -lt 10 ]; then
        echo "   • Cache has few entries - run more builds to populate"
      fi
    fi

    echo ""
  '';
in
```

### 5. CI Cache Monitoring

Script for CI environments:

```nix
let
  ciCacheMonitorScript = pkgs.writeScriptBin "ci-cache-monitor" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # CI-friendly output with GitHub Actions annotations

    echo "::group::Cache Statistics"

    if [ -d .buck-cache ]; then
      ENTRIES=$(find .buck-cache -type f | wc -l)
      SIZE=$(du -sh .buck-cache | cut -f1)

      echo "Cache entries: $ENTRIES"
      echo "Cache size: $SIZE"

      # Export as GitHub Actions output
      echo "cache_entries=$ENTRIES" >> $GITHUB_OUTPUT
      echo "cache_size=$SIZE" >> $GITHUB_OUTPUT

      # Warn if cache is unexpectedly small (possible cache miss)
      if [ "$ENTRIES" -lt 5 ]; then
        echo "::warning::Cache has very few entries ($ENTRIES) - possible cache miss"
      fi
    else
      echo "::warning::No cache directory found"
    fi

    echo "::endgroup::"

    # Verify toolchain synchronization
    echo "::group::Toolchain Verification"
    if verify-toolchains; then
      echo "::notice::All toolchains synchronized"
    else
      echo "::error::Toolchain synchronization failed"
      exit 1
    fi
    echo "::endgroup::"
  '';
in
```

### 6. Cache Cleanup Tool

Tool to manage cache size:

```nix
let
  cacheCleanupScript = pkgs.writeScriptBin "clean-buck-cache" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Buck2 Cache Cleanup"
    echo "==================="

    if [ ! -d .buck-cache ]; then
      echo "No cache directory found"
      exit 0
    fi

    # Show current size
    echo ""
    echo "Current cache size: $(du -sh .buck-cache | cut -f1)"
    ENTRIES_BEFORE=$(find .buck-cache -type f | wc -l)
    echo "Current entries: $ENTRIES_BEFORE"

    # Clean old entries (older than 30 days)
    echo ""
    echo "Removing entries older than 30 days..."
    find .buck-cache -type f -mtime +30 -delete

    # Show new size
    ENTRIES_AFTER=$(find .buck-cache -type f | wc -l)
    REMOVED=$((ENTRIES_BEFORE - ENTRIES_AFTER))

    echo ""
    echo "New cache size: $(du -sh .buck-cache | cut -f1)"
    echo "New entries: $ENTRIES_AFTER"
    echo "Removed: $REMOVED entries"
  '';
in
```

### 7. Integration with devShell

Add all monitoring tools to development shell:

```nix
{
  devShells.default = pkgs.mkShell {
    packages = toolchainPackages ++ [
      cacheStatsScript
      toolchainFingerprintScript
      cacheMissDebugScript
      cacheHealthScript
      ciCacheMonitorScript
      cacheCleanupScript
    ];

    shellHook = ''
      ${existingShellHook}

      # Optional: Show cache health on shell entry
      ${lib.optionalString cfg.shell.showCacheHealth ''
        cache-health
      ''}
    '';
  };
}
```

## Implementation Steps

1. Create cache statistics monitoring script
2. Create toolchain fingerprint tracking script
3. Create cache miss debugging script
4. Create comprehensive health dashboard
5. Create CI monitoring script
6. Create cache cleanup utility
7. Add all tools to devShell
8. Create documentation for each tool
9. Test tools with various cache scenarios
10. Add usage examples to user guide

## Testing

```bash
# Monitor cache growth
buck2 build //...
buck2-cache-stats

# Track fingerprints
toolchain-fingerprint save
# ... change toolchain ...
toolchain-fingerprint compare
# Should show differences

# Debug cache miss
buck2 build //src:app
debug-cache-miss //src:app

# Health check
cache-health
# Should show comprehensive status

# Cleanup
clean-buck-cache
# Should remove old entries

# CI monitoring (in CI environment)
ci-cache-monitor
```

## Related Documentation

- Tasks: `TASKS.md` (Phase 2.3)
- Phase 2.1: Local caching validation
- Phase 2.2: Cache stability testing
- Buck2 Docs: Logging and debugging

## Next Steps

After completing this task:
- Phase 3: Buck2 prelude customization
- Phase 6: CI/CD integration (will use these monitoring tools)

## Notes

- **Visibility**: Users need visibility into cache behavior to trust it
- **Debugging**: When cache doesn't work as expected, tools help diagnose quickly
- **CI integration**: Monitoring in CI helps catch regressions
- **Performance tracking**: Track cache effectiveness over time
- **Documentation**: Each tool needs clear usage documentation
- **Automation**: Consider automatic health checks in CI
- **Metrics**: Export metrics for long-term analysis
- **Alerts**: Consider alerting on low cache hit rates

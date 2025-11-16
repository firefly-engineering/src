# Phase 8.5: Publish and Announce Repositories

## Overview

Publish the `turnkey` and `toolchain-registry` repositories, create releases, write announcements, and promote adoption in the Nix and Buck2 communities.

## Context

After extraction and migration:
- `turnkey` is ready for public use
- `toolchain-registry` has curated versions
- This repo demonstrates usage
- Documentation is complete
- Time to share with the community!

### Goals

1. **Launch**: Make repos discoverable and usable
2. **Educate**: Help people understand the value
3. **Support**: Provide channels for questions and contributions
4. **Grow**: Build community around the solution

## Prerequisites

- Phase 8.2: Turnkey repository complete
- Phase 8.3: Toolchain registry complete
- Phase 8.4: Migration complete and tested
- All documentation reviewed
- All examples tested
- CI/CD working

## Success Criteria

- [ ] Both repos public on GitHub
- [ ] v1.0.0 releases tagged
- [ ] GitHub Releases created with notes
- [ ] README badges added
- [ ] Documentation sites live
- [ ] Announcement blog post published
- [ ] Posted to Nix Discourse
- [ ] Posted to Buck2 community
- [ ] Posted to relevant subreddits
- [ ] Example repos created
- [ ] Support channels established

## Implementation Guidance

### 1. Pre-Launch Checklist

**Turnkey**:
- [ ] All documentation complete
- [ ] README polished
- [ ] Examples work
- [ ] CI passing
- [ ] License files present
- [ ] CONTRIBUTING.md exists
- [ ] CODE_OF_CONDUCT.md exists

**Toolchain Registry**:
- [ ] All versions tested
- [ ] README with version table
- [ ] Contribution guide
- [ ] CI passing
- [ ] License files
- [ ] CHANGELOG.md initialized

**Both**:
- [ ] Security policy (SECURITY.md)
- [ ] Issue templates
- [ ] PR templates
- [ ] Dependabot configured

### 2. Create GitHub Releases

**Turnkey v1.0.0**:

```markdown
# Turnkey v1.0.0

First stable release of Turnkey - toolchain synchronization for Nix + Buck2!

## What is Turnkey?

Turnkey ensures your development shell and Buck2 builds use **identical toolchain binaries**, eliminating the "works on my machine" problem.

```nix
# flake.nix
{
  inputs.turnkey.url = "github:firefly-engineering/turnkey";
  inputs.toolchain-registry.url = "github:firefly-engineering/toolchain-registry";

  outputs = { turnkey, toolchain-registry, ... }: {
    devShells.default = pkgs.mkShell {
      imports = [ turnkey.flakeModules.default ];
      turnkey.toolchains.registry = toolchain-registry.registry;
    };
  };
}
```

```toml
# toolchain.toml
[go]
version = "1.21.5"
```

Result: `which go` and `buck2 audit config go_bin` return **identical paths** ✅

## Features

- ✅ Synchronized toolchains (Shell + Buck2)
- ✅ Automatic cache invalidation
- ✅ Custom registries supported
- ✅ Multi-language (Go, Rust, Python, C/C++)
- ✅ Security patch support
- ✅ Zero network dependencies (offline builds)

## Documentation

- 📚 [Getting Started](https://turnkey.dev/docs/getting-started)
- 📖 [API Reference](https://turnkey.dev/docs/api-reference)
- 🎨 [Custom Registry Guide](https://turnkey.dev/docs/custom-registry)
- 💡 [Examples](https://github.com/firefly-engineering/turnkey/tree/main/examples)

## What's Included

- Core toolchain resolution module
- Shell environment generation
- Buck2 config generation
- Validation tools (`verify-toolchains`)
- Registry interface (stable v1.0 API)

## Compatibility

- **Nix**: Requires flakes (Nix 2.4+)
- **Buck2**: Any recent version
- **Platforms**: Linux (x86_64, aarch64), macOS (x86_64, aarch64)

## Links

- 🏠 [Website](https://turnkey.dev)
- 📦 [Toolchain Registry](https://github.com/firefly-engineering/toolchain-registry)
- 📖 [Documentation](https://turnkey.dev/docs)
- 💬 [Discussions](https://github.com/firefly-engineering/turnkey/discussions)
- 🐛 [Issues](https://github.com/firefly-engineering/turnkey/issues)

## Thanks

Thanks to the Nix and Buck2 communities for inspiration and support!
```

**Toolchain Registry v1.0.0**:

```markdown
# Toolchain Registry v1.0.0

First release of the community toolchain registry for [Turnkey](https://github.com/firefly-engineering/turnkey)!

## Included Versions

### Go
- 1.21, 1.21.0, 1.21.5, 1.21.6
- 1.22, 1.22.0, 1.22.1
- 1.23, 1.23.0
- stable, latest

### Rust
- 1.75, 1.75.0
- 1.76, 1.76.0
- 1.77, 1.77.0
- stable, latest

### Python
- 3.11, 3.12, 3.13
- latest

### C/C++
- Clang: 16, 17, 18, latest
- GCC: 12, 13, 14, latest

[Full version list](https://github.com/firefly-engineering/toolchain-registry#available-toolchains)

## Usage

```nix
{
  inputs.toolchain-registry.url = "github:firefly-engineering/toolchain-registry";

  outputs = { toolchain-registry, ... }: {
    # Use with Turnkey
    turnkey.toolchains.registry = toolchain-registry.registry;
  };
}
```

## Contributing

We welcome version additions! See [CONTRIBUTING.md](https://github.com/firefly-engineering/toolchain-registry/blob/main/CONTRIBUTING.md)

## Links

- 🏠 [Turnkey](https://github.com/firefly-engineering/turnkey)
- 📖 [Documentation](https://github.com/firefly-engineering/toolchain-registry#readme)
- 💬 [Discussions](https://github.com/firefly-engineering/toolchain-registry/discussions)
```

### 3. Add Repository Badges

Add to both READMEs:

```markdown
[![Nix Flakes](https://img.shields.io/badge/Nix-Flakes-blue?logo=nixos)](https://nixos.wiki/wiki/Flakes)
[![License](https://img.shields.io/github/license/firefly-engineering/turnkey)](LICENSE)
[![CI](https://github.com/firefly-engineering/turnkey/workflows/CI/badge.svg)](https://github.com/firefly-engineering/turnkey/actions)
[![Documentation](https://img.shields.io/badge/docs-turnkey.dev-blue)](https://turnkey.dev/docs)
```

### 4. Create Announcement Blog Post

`blog/announcing-turnkey.md`:

```markdown
# Announcing Turnkey: Toolchain Synchronization for Nix + Buck2

**TL;DR**: [Turnkey](https://github.com/firefly-engineering/turnkey) ensures your Nix development shell and Buck2 builds use **identical toolchain binaries**, eliminating discrepancies between environments.

## The Problem

You've carefully configured your development environment:
- Nix provides Go 1.21 in your shell
- Buck2... downloads its own Go 1.20?
- Your `go build` works, but `buck2 build` fails

**Sound familiar?**

This happens because most build systems manage toolchains independently from your development environment. Different versions = different behaviors = debugging nightmares.

## The Solution: Turnkey

Turnkey synchronizes toolchains between Nix and Buck2 using a simple principle:

> **If both use the exact same binary from the Nix store, they MUST behave identically.**

Here's how:

```nix
# flake.nix - Configure once
{
  inputs = {
    turnkey.url = "github:firefly-engineering/turnkey";
    toolchain-registry.url = "github:firefly-engineering/toolchain-registry";
  };

  outputs = { turnkey, toolchain-registry, ... }: {
    devShells.default = pkgs.mkShell {
      imports = [ turnkey.flakeModules.default ];
      turnkey.toolchains.registry = toolchain-registry.registry;
    };
  };
}
```

```toml
# toolchain.toml - Declare your versions
[go]
version = "1.21.5"

[rust]
version = "1.76"
```

```bash
# Result - Perfect synchronization
$ nix develop

$ which go
/nix/store/abc123.../go-1.21.5/bin/go

$ buck2 audit config go_bin
/nix/store/abc123.../go-1.21.5/bin/go  # ✅ Same path!

$ go build     # Works
$ buck2 build  # Works identically
```

## How It Works

1. **Single source of truth**: `toolchain.toml` declares needed versions
2. **Registry resolution**: Versions resolve to Nix derivations
3. **Dual integration**: Same derivation goes to shell AND Buck2 config
4. **Automatic caching**: Nix store paths = Buck2 cache keys

When you change toolchains:
- Nix store path changes (content-addressed)
- Buck2 config regenerates
- Buck2 cache automatically invalidates
- No manual cache clearing needed!

## Features

- **Synchronized environments**: Guaranteed identical binaries
- **Custom registries**: Use your own toolchain versions
- **Multi-language**: Go, Rust, Python, C/C++, extensible
- **Security patches**: Apply patches transparently
- **Offline-first**: No network downloads during builds
- **Community-maintained**: Open registry of versions

## Architecture

Turnkey is split into two repositories:

1. **[turnkey](https://github.com/firefly-engineering/turnkey)**: Core mechanism (registry resolution, config generation)
2. **[toolchain-registry](https://github.com/firefly-engineering/toolchain-registry)**: Curated versions (Go, Rust, Python, etc.)

This separation allows:
- Organizations to use turnkey with their own registries
- Registry updates without mechanism changes
- Community contribution to version catalog

## Getting Started

Full tutorial: https://turnkey.dev/docs/getting-started

Quick start:

```bash
# Add to your flake.nix
inputs.turnkey.url = "github:firefly-engineering/turnkey";
inputs.toolchain-registry.url = "github:firefly-engineering/toolchain-registry";

# Create toolchain.toml
echo '[go]\nversion = "1.21.5"' > toolchain.toml

# Enter shell
nix develop

# Verify
verify-toolchains  # ✅
```

## Who's Using It?

We've been using this at Firefly for [X months] in production. It's enabled:
- Consistent builds across 50+ developers
- Zero "works on my machine" issues
- Rapid security patching (35min from CVE to production)
- Hermetic CI/CD builds

## Future Plans

- Support for more build systems (Bazel, Please)
- Extended language support
- Registry UI for browsing versions
- Automatic security advisory notifications

## Get Involved

- ⭐ [Star on GitHub](https://github.com/firefly-engineering/turnkey)
- 📖 [Read the docs](https://turnkey.dev/docs)
- 💬 [Join discussions](https://github.com/firefly-engineering/turnkey/discussions)
- 🐛 [Report issues](https://github.com/firefly-engineering/turnkey/issues)
- 🤝 [Contribute](https://github.com/firefly-engineering/turnkey/blob/main/CONTRIBUTING.md)

## Thanks

Special thanks to the Nix and Buck2 communities for building amazing tools that make this possible!

---

*Happy building! 🚀*
```

### 5. Community Announcements

**Nix Discourse** post:

```markdown
Title: [Announce] Turnkey - Toolchain synchronization for Nix + Buck2

I'm excited to announce Turnkey, a Nix flake module that synchronizes toolchains between your development shell and Buck2 builds.

**Problem**: Development shells and build systems often use different toolchain versions, causing "works on my machine" issues.

**Solution**: Turnkey ensures both use the exact same toolchain binaries from the Nix store.

Key features:
- Synchronized toolchains (Shell + Buck2 use identical binaries)
- Custom registry support
- Multi-language (Go, Rust, Python, C/C++)
- Automatic Buck2 cache invalidation

Links:
- GitHub: https://github.com/firefly-engineering/turnkey
- Docs: https://turnkey.dev/docs
- Registry: https://github.com/firefly-engineering/toolchain-registry

Feedback and contributions welcome!
```

**Reddit** (r/NixOS):

```markdown
Title: Turnkey - Synchronize Nix toolchains with Buck2 builds

Built a Nix flake module that ensures your dev shell and Buck2 use identical toolchain binaries.

[Similar content to Discourse announcement, more casual tone]

Would love feedback from the community!
```

**Buck2 Community**:

Post similar announcement to Buck2 Discord/Slack/mailing list.

### 6. Create Example Repositories

Create standalone example repos:

**`turnkey-example-go`**:
- Simple Go project
- Uses turnkey + registry
- README with step-by-step tutorial
- GitHub template repository

**`turnkey-example-multi`**:
- Multi-language (Go + Rust)
- Shows registry extension
- More complex example

### 7. Set Up Support Channels

**GitHub Discussions**:
- Enable on both repos
- Create categories: General, Q&A, Ideas, Show and Tell

**Discord** (optional):
- Create community Discord server
- Channels: #general, #support, #development

**Issue Templates**:

`.github/ISSUE_TEMPLATE/bug_report.md`:
```markdown
---
name: Bug report
about: Report a problem with Turnkey
---

**Describe the bug**
Clear description of what's wrong.

**To Reproduce**
Steps to reproduce:
1. ...

**Expected behavior**
What should happen.

**Environment**
- OS: [e.g., NixOS 23.11]
- Nix version: [e.g., 2.18.0]
- Buck2 version: [e.g., 2024-01-01]
- Turnkey version: [e.g., v1.0.0]

**Additional context**
Any other information.
```

### 8. Submit to Nix Flake Registries

If applicable, submit to community flake indexes.

### 9. Monitor and Respond

**First week after launch**:
- Monitor GitHub issues/discussions daily
- Respond to questions quickly
- Fix critical bugs immediately
- Gather feedback

**Ongoing**:
- Weekly check of issues/PRs
- Monthly community updates
- Quarterly roadmap reviews

### 10. Success Metrics

Track:
- ⭐ GitHub stars
- 🍴 Forks
- 📥 Unique cloners
- 💬 Discussions/issues
- 🔗 Mentions/references
- 👥 Contributors

## Implementation Steps

1. Complete pre-launch checklist
2. Create GitHub releases (v1.0.0 for both)
3. Add badges to READMEs
4. Write announcement blog post
5. Post to Nix Discourse
6. Post to Reddit
7. Post to Buck2 community
8. Create example repositories
9. Set up support channels
10. Monitor and respond to feedback

## Testing

```bash
# Verify releases
curl -s https://api.github.com/repos/firefly-engineering/turnkey/releases/latest | jq .tag_name
# Should show: "v1.0.0"

# Test that users can fetch
nix flake show github:firefly-engineering/turnkey
nix flake show github:firefly-engineering/toolchain-registry

# Test examples
git clone https://github.com/firefly-engineering/turnkey-example-go
cd turnkey-example-go
nix develop --command verify-toolchains
```

## Related Documentation

- Tasks: `TASKS.md` (Phase 8.5)
- All previous Phase 8 tasks

## Next Steps

After completing this task:
- Monitor community response
- Iterate based on feedback
- Plan next features
- Build community

## Notes

- **Communication**: Clear, friendly communication critical
- **Support**: Be responsive to early adopters
- **Patience**: Community growth takes time
- **Iteration**: Improve based on feedback
- **Recognition**: Thank contributors publicly
- **Documentation**: Keep improving based on questions
- **Marketing**: Gentle, helpful, not pushy
- **Community**: Foster welcoming environment

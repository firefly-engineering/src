# Troubleshooting

## Path Mismatch: Shell vs Buck2

**Symptom**: `which go` and `buck2 audit config go_bin` return different paths.

**Cause**: Buck2 configs not regenerated after toolchain change.

**Solution**:
```bash
# Regenerate Buck2 configs
generate-buck2-configs

# Or exit and re-enter shell
exit
nix develop
```

## Unknown Version Error

**Symptom**: `Unknown version '1.99.99' for toolchain 'go'`

**Cause**: Version not in registry.

**Solution**:
- Check available versions: error message lists them
- Use available version in `toolchain.toml`
- Or add custom version to registry

## toolchain.toml Not Found

**Symptom**: `Toolchain declaration file not found`

**Cause**: Missing `toolchain.toml` file.

**Solution**:
```bash
# Create toolchain.toml
cat > toolchain.toml <<EOF
[go]
version = "1.21.5"
EOF
```

## Builds Work in Shell But Fail in Buck2

**Symptom**: `go build` succeeds, `buck2 build` fails with toolchain error.

**Solution**:
1. Verify synchronization: `verify-toolchains`
2. Regenerate Buck2 configs: `generate-buck2-configs`
3. Check `.buckconfig` includes `.buckconfig.toolchains`

## Slow Shell Entry

**Symptom**: `nix develop` takes a long time.

**Cause**: Nix is building toolchains from source.

**Solution**:
- Use binary cache if available
- Check that nixpkgs version has prebuilt binaries
- Consider using `nix-direnv` for faster activation

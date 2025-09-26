{ lib, pkgs }:

let
  utils = import ./utils.nix { inherit lib pkgs; };
  inherit (utils) goModulesJson fetchModule;

in
# Create GOPROXY-compatible filesystem layout
pkgs.runCommand "go-proxy-filesystem" {
  buildInputs = [ pkgs.zip ];
} ''
  mkdir -p "$out"

  ${lib.concatMapStringsSep "\n" (moduleName:
    let moduleVersions = goModulesJson.${moduleName};
    in lib.concatMapStringsSep "\n" (version:
      let
        # Escape module path for GOPROXY (/ becomes !, uppercase becomes !lowercase)
        escapedModuleName = lib.replaceStrings
          ["/"]
          ["!"]
          moduleName;
        moduleSource = fetchModule version;
        versionString = version.version;
      in ''
        # Create directory structure for ${moduleName}@${versionString}
        mkdir -p "$out/${escapedModuleName}/@v"

        # Add version to list file
        echo "${versionString}" >> "$out/${escapedModuleName}/@v/list"

        # Create .info file with version metadata
        cat > "$out/${escapedModuleName}/@v/${versionString}.info" << 'EOF'
        {
          "Version": "${versionString}",
          "Time": "${version.time}"
        }
        EOF

        # Copy go.mod file or create minimal one
        if [ -f "${moduleSource}/go.mod" ]; then
          cp "${moduleSource}/go.mod" "$out/${escapedModuleName}/@v/${versionString}.mod"
        else
          echo "module ${moduleName}" > "$out/${escapedModuleName}/@v/${versionString}.mod"
          echo "" >> "$out/${escapedModuleName}/@v/${versionString}.mod"
          echo "go 1.21" >> "$out/${escapedModuleName}/@v/${versionString}.mod"
        fi

        # Create .zip file with module contents
        cd "${moduleSource}"
        zip -r "$out/${escapedModuleName}/@v/${versionString}.zip" . \
          -x "*.git*" "*/.DS_Store*" "*/.*" \
          || echo "Warning: zip creation failed for ${moduleName}@${versionString}"
      ''
    ) moduleVersions
  ) (builtins.attrNames goModulesJson)}

  # Sort version lists
  find "$out" -name "list" -exec sort -V -o {} {} \;

  # Create a summary of available modules
  echo "Available modules in GOPROXY filesystem:" > "$out/README.txt"
  find "$out" -name "list" | while read -r listfile; do
    module_path=$(dirname $(dirname "$listfile"))
    module_name=$(basename "$module_path" | tr '!' '/')
    echo "  $module_name:" >> "$out/README.txt"
    while read -r version; do
      echo "    - $version" >> "$out/README.txt"
    done < "$listfile"
  done
''
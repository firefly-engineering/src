{ ... }:
{
  perSystem = { lib, pkgs, ... }: {
    packages =
      let
        # Load the JSON file containing Go module dependencies
        goModulesJson = builtins.fromJSON (builtins.readFile ./go-modules.json);

        # Function to extract revision from version string
        extractRevision = version:
          if lib.hasPrefix "v0.0.0-" version then
            # Pseudo-version format: v0.0.0-YYYYMMDDHHMMSS-COMMITHASH
            let versionParts = lib.splitString "-" version;
            in builtins.elemAt versionParts 2
          else
            # Proper tag version: use as-is
            version;

        # Function to fetch a single module version based on its repository URL
        fetchModule = moduleSpec:
          let
            repoUrl = moduleSpec.repo;
            rev = extractRevision moduleSpec.version;
            rawSource = if lib.hasPrefix "https://github.com/" repoUrl then
              let
                # Parse GitHub URL: https://github.com/owner/repo
                urlParts = lib.splitString "/" (lib.removePrefix "https://github.com/" repoUrl);
                owner = builtins.elemAt urlParts 0;
                repo = builtins.elemAt urlParts 1;
              in
              pkgs.fetchFromGitHub {
                inherit owner repo rev;
                sha256 = moduleSpec.hash;
              }
            else
              # Fallback to generic git fetching for other repositories
              pkgs.fetchgit {
                url = repoUrl;
                inherit rev;
                sha256 = moduleSpec.hash;
              };
            # Handle subpath extraction if specified
            subpath = moduleSpec.subpath or null;
          in
          if subpath != null then
            pkgs.runCommand "module-source" {} ''
              mkdir -p "$out"
              if [ -d "${rawSource}/${subpath}" ]; then
                cp -r "${rawSource}/${subpath}"/* "$out/"
                chmod -R u+w "$out"
              else
                echo "Error: subpath '${subpath}' not found in source"
                exit 1
              fi
            ''
          else
            rawSource;

        # Create individual module directories with proper GOPROXY structure
        moduleDirectories = lib.flatten (
          lib.mapAttrsToList (moduleName: versions:
            lib.map (version:
              let
                # Escape module path for filesystem (/ becomes !)
                escapedModuleName = lib.replaceStrings ["/"] ["!"] moduleName;
                moduleSource = fetchModule version;
              in
              pkgs.runCommand "${escapedModuleName}-${version.version}" {} ''
                mkdir -p "$out/pkg/mod/${moduleName}@${version.version}"
                cp -r ${moduleSource}/* "$out/pkg/mod/${moduleName}@${version.version}/"
                # Make files writable (Go expects this)
                chmod -R u+w "$out/pkg/mod/${moduleName}@${version.version}"
              ''
            ) versions
          ) goModulesJson
        );

        # Create the merged source directory with proper structure
        goDependencies = pkgs.symlinkJoin {
          name = "go-dependencies";
          paths = moduleDirectories;
        };

        # Create GOPROXY-compatible filesystem layout
        goProxyFilesystem = pkgs.runCommand "go-proxy-filesystem" {
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
        '';

      in
      {
        inherit goDependencies goProxyFilesystem;
      };
  };
}
{ lib, pkgs }:

let
  utils = import ./utils.nix { inherit lib pkgs; };
  inherit (utils) goModulesJson fetchModule;

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

in
# Create the merged source directory with proper structure
pkgs.symlinkJoin {
  name = "go-dependencies";
  paths = moduleDirectories;
}
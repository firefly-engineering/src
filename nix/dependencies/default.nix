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
          in
          if lib.hasPrefix "https://github.com/" repoUrl then
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

      in
      {
        inherit goDependencies;
      };
  };
}
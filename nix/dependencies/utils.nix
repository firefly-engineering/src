{ lib, pkgs }:

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

in
{
  inherit goModulesJson extractRevision fetchModule;
}
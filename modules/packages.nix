# red-tape/packages — Discover and build packages
let
  inherit (import ../lib/internal.nix) buildAll filterPlatforms scanEntries;
in
{
  name = "packages";
  inputs = {
    project = {
      path = "../project";
    };
    scope = {
      path = "../scope";
    };
  };
  impl =
    { results, ... }:
    let
      s = results.scope;
      src = results.project.resolvedSrc;
      found = scanEntries {
        dir = src + "/packages";
        single = src + "/package.nix";
      };
    in
    {
      packages = filterPlatforms s.system (buildAll s.scope found);
    };
}

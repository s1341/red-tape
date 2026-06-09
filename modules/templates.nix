# red-tape/templates — Discover template directories
let
  inherit (import ../lib/internal.nix) scanDirsWithFile;
  inherit (builtins) mapAttrs pathExists;
in
{
  name = "templates";
  inputs = {
    project = {
      path = "../project";
    };
  };
  impl =
    { results, ... }:
    let
      src = results.project.resolvedSrc;
      found = scanDirsWithFile (src + "/templates") "flake.nix" (path: {
        inherit path;
      });
      buildTemplates =
        tree:
        mapAttrs (
          name: e:
          if e ? path then
            let
              f = e.path + "/flake.nix";
            in
            {
              inherit (e) path;
              description = if pathExists f then (import f).description or name else name;
            }
          else
            buildTemplates e
        ) tree;
      templates = buildTemplates found;
    in
    if found != { } then { inherit templates; } else { };
}

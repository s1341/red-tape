# Template tests
let
  prelude = import ./prelude.nix;
  inherit (prelude) discover fixtures;
  inherit (builtins) mapAttrs pathExists;
  inherit (discover) scanDirsWithFile;

  scanTemplates =
    src:
    scanDirsWithFile (src + "/templates") "flake.nix" (path: {
      inherit path;
    });

  mkTemplates =
    src:
    let
      build =
        tree:
        mapAttrs (
          name: entry:
          if entry ? path then
            let
              f = entry.path + "/flake.nix";
            in
            {
              inherit (entry) path;
              description = if pathExists f then (import f).description or name else name;
            }
          else
            build entry
        ) tree;
    in
    build (scanTemplates src);
in
{
  testTemplateNames = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames (mkTemplates (fixtures + "/full")));
    expected = [
      "default"
      "group"
      "minimal"
    ];
  };

  testTemplateDescription = {
    expr = (mkTemplates (fixtures + "/full")).default.description;
    expected = "A default template";
  };

  testNestedTemplateDescription = {
    expr = (mkTemplates (fixtures + "/full")).group.app.description;
    expected = "A nested template";
  };

  testEmptyTemplates = {
    expr = mkTemplates (fixtures + "/empty");
    expected = { };
  };
}

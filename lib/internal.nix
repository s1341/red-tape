# Internal scanning and builder primitives used by red-tape modules
let
  inherit (builtins)
    addErrorContext
    attrNames
    elem
    filter
    foldl'
    functionArgs
    head
    intersectAttrs
    listToAttrs
    map
    mapAttrs
    match
    pathExists
    readDir
    ;

  # ── Scanning primitives ────────────────────────────────────────────

  # Scan a directory for .nix files and subdirectories with default.nix.
  # Returns { name = { path; type = "file"|"directory"; }; ... }
  # .nix files take precedence over directories with the same stem.
  scanDir =
    path:
    let
      scan =
        currentPath:
        if !pathExists currentPath then
          { }
        else
          let
            entries = readDir currentPath;

            processEntry =
              name:
              let
                type = entries.${name};
                subPath = currentPath + "/${name}";
              in
              if type == "directory" then
                let
                  # 1. Check if this directory is a module/host itself (contains default.nix)
                  currentDirAttr =
                    if pathExists (subPath + "/default.nix") then
                      {
                        "${name}" = {
                          path = subPath;
                          type = "directory";
                        };
                      }
                    else
                      { };

                  # 2. Recursively scan deeper inside this directory
                  innerResults = scan subPath;
                in
                currentDirAttr // innerResults

              else if type == "regular" then
                let
                  m = builtins.match "(.+)\\.nix$" name;
                in
                # 3. Match regular .nix files (excluding default.nix)
                if m != null && name != "default.nix" then
                  {
                    "${head m}" = {
                      path = subPath;
                      type = "file";
                    };
                  }
                else
                  { }
              else
                { };

            listOfAttrs = map processEntry (builtins.attrNames entries);
          in
          builtins.foldl' (a: b: a // b) { } listOfAttrs;
    in
    scan path;

  # Like scanDir but for hosts: walks subdirs looking for sentinel files
  # (e.g. configuration.nix) to determine host type.
  # Returns { name = { type; configPath; hostPath; }; ... }.
  scanHosts =
    path: hostTypes:
    let
      scan =
        currentPath:
        if !pathExists currentPath then
          { }
        else
          let
            entries = readDir currentPath;

            processEntry =
              name:
              let
                type = entries.${name};
                subPath = currentPath + "/${name}";
              in
              if type != "directory" then
                { }
              else
                let
                  hits = filter (t: pathExists (subPath + "/${t.file}")) hostTypes;

                  currentHost =
                    if hits == [ ] then
                      { }
                    else
                      {
                        "${name}" = {
                          type = (head hits).type;
                          configPath = subPath + "/${(head hits).file}";
                          hostPath = subPath;
                        };
                      };

                  innerHosts = scan subPath;
                in
                currentHost // innerHosts;

            listOfAttrs = map processEntry (builtins.attrNames entries);
          in
          builtins.foldl' (a: b: a // b) { } listOfAttrs;
    in
    scan path;

  # Scan subdirectories of a path, applying f to each.
  # Returns { name = f (path + "/${name}"); ... } or {} if path is missing.
  scanSubdirs =
    path: f:
    let
      scan =
        currentPath:
        if !pathExists currentPath then
          { }
        else
          let
            entries = readDir currentPath;

            processEntry =
              name:
              let
                type = entries.${name};
                subPath = currentPath + "/${name}";
              in
              if type != "directory" then
                { }
              else
                let
                  # Apply the function 'f' to the current directory
                  currentDirAttr = {
                    "${name}" = f subPath;
                  };

                  # Recursively scan inside this directory
                  innerDirs = scan subPath;
                in
                # Merge the current directory result with any nested results
                currentDirAttr // innerDirs;

            listOfAttrs = map processEntry (builtins.attrNames entries);
          in
          builtins.foldl' (a: b: a // b) { } listOfAttrs;
    in
    scan path;

  # Scan a directory for entries, with optional single-file fallback.
  #   scanEntries { dir = src + "/packages"; single = src + "/package.nix"; }
  scanEntries =
    {
      dir ? null,
      single ? null,
      singleName ? "default",
    }:
    let
      optionalDefault =
        path:
        if pathExists (path + "/default.nix") then
          {
            default = {
              path = path + "/default.nix";
              type = "file";
            };
          }
        else
          { };
      optionalSingle =
        path: name:
        if pathExists path then
          {
            ${name} = {
              inherit path;
              type = "file";
            };
          }
        else
          { };
    in
    (if dir != null then optionalDefault dir // scanDir dir else { })
    // (if single != null then optionalSingle single singleName else { });

  # ── Builder helpers ────────────────────────────────────────────────

  entryPath = e: if e.type == "directory" then e.path + "/default.nix" else e.path;

  callFile =
    scope: path: extra:
    addErrorContext "while evaluating '${toString path}'" (
      let
        fn = import path;
      in
      fn (intersectAttrs (functionArgs fn) (scope // extra))
    );

  buildAll = scope: mapAttrs (pname: e: callFile scope (entryPath e) { inherit pname; });

  filterPlatforms =
    system: a:
    listToAttrs (
      filter (x: x != null) (
        map (
          n:
          let
            p = a.${n}.meta.platforms or [ ];
          in
          if p == [ ] || elem system p then
            {
              name = n;
              value = a.${n};
            }
          else
            null
        ) (attrNames a)
      )
    );

  withPrefix =
    pre: a:
    listToAttrs (
      map (n: {
        name = "${pre}${n}";
        value = a.${n};
      }) (attrNames a)
    );
in
{
  inherit
    scanDir
    scanHosts
    scanSubdirs
    scanEntries
    entryPath
    callFile
    buildAll
    filterPlatforms
    withPrefix
    ;
}

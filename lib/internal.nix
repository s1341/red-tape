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
    hasAttr
    intersectAttrs
    isAttrs
    listToAttrs
    map
    mapAttrs
    match
    pathExists
    readDir
    ;

  isEntry = x: isAttrs x && x ? path && x ? type;

  # ── Scanning primitives ────────────────────────────────────────────

  # Scan a directory for .nix files and subdirectories with default.nix.
  # Returns { name = { path; type = "file"|"directory"; }; ... }
  # .nix files take precedence over directories with the same stem.
  scanDir =
    path:
    let
      recursiveMerge =
        a: b:
        listToAttrs (
          map (
            name:
            let
              inA = hasAttr name a;
              inB = hasAttr name b;
            in
            {
              inherit name;
              value =
                if
                  inA && inB && isAttrs a.${name} && isAttrs b.${name} && !isEntry a.${name} && !isEntry b.${name}
                then
                  recursiveMerge a.${name} b.${name}
                else if inB then
                  b.${name}
                else
                  a.${name};
            }
          ) (attrNames (a // b))
        );

      mergeAll = foldl' recursiveMerge { };

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
                if pathExists (subPath + "/default.nix") then
                  {
                    "${name}" = {
                      path = subPath;
                      type = "directory";
                    };
                  }
                else
                  let
                    innerResults = scan subPath;
                  in
                  if innerResults == { } then { } else { "${name}" = innerResults; }

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
          mergeAll listOfAttrs;
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
                if currentHost != { } then
                  currentHost
                else if innerHosts == { } then
                  { }
                else
                  { "${name}" = innerHosts; };

            listOfAttrs = map processEntry (builtins.attrNames entries);
          in
          builtins.foldl' (a: b: a // b) { } listOfAttrs;
    in
    scan path;

  # Scan subdirectories of a path, applying f to each.
  # Returns { name = f (path + "/${name}"); ... } or {} if path is missing.
  scanSubdirs =
    path: f:
    if !pathExists path then
      { }
    else
      let
        entries = readDir path;
        dirs = filter (name: entries.${name} == "directory") (attrNames entries);
      in
      listToAttrs (
        map (name: {
          inherit name;
          value = f (path + "/${name}");
        }) dirs
      );

  # Recursively scan directories that contain a sentinel file.
  # Used for templates, where flake.nix marks a leaf.
  scanDirsWithFile =
    path: file: f:
    let
      scan =
        currentPath:
        if !pathExists currentPath then
          { }
        else
          let
            entries = readDir currentPath;
            dirs = filter (name: entries.${name} == "directory") (attrNames entries);

            processDir =
              name:
              let
                subPath = currentPath + "/${name}";
                children = scan subPath;
              in
              if pathExists (subPath + "/${file}") then
                { "${name}" = f subPath; }
              else if children == { } then
                { }
              else
                { "${name}" = children; };
          in
          foldl' (a: b: a // b) { } (map processDir dirs);
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

  mapEntryTree =
    f: tree: mapAttrs (name: value: if isEntry value then f name value else mapEntryTree f value) tree;

  buildAll = scope: mapEntryTree (pname: e: callFile scope (entryPath e) { inherit pname; });

  filterPlatforms =
    system: a:
    listToAttrs (
      filter (x: x != null) (
        map (
          n:
          let
            value = a.${n};
            p = value.meta.platforms or [ ];
          in
          if isAttrs value && !(value ? type) && !(value ? outPath) then
            let
              filtered = filterPlatforms system value;
            in
            if filtered == { } then
              null
            else
              {
                name = n;
                value = filtered;
              }
          else if p == [ ] || elem system p then
            {
              name = n;
              inherit value;
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
    scanDirsWithFile
    scanEntries
    entryPath
    callFile
    buildAll
    filterPlatforms
    withPrefix
    ;
}

# Internal scanning and builder primitives used by red-tape modules
let
  inherit (builtins)
    addErrorContext
    attrNames
    elem
    filter
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
    if !pathExists path then
      { }
    else
      let
        entries = readDir path;
        dirs = listToAttrs (
          filter (x: x != null) (
            map (
              name:
              if entries.${name} == "directory" && pathExists (path + "/${name}/default.nix") then
                {
                  inherit name;
                  value = {
                    path = path + "/${name}";
                    type = "directory";
                  };
                }
              else
                null
            ) (attrNames entries)
          )
        );
        files = listToAttrs (
          filter (x: x != null) (
            map (
              name:
              let
                m = match "(.+)\\.nix$" name;
              in
              if entries.${name} == "regular" && m != null && name != "default.nix" then
                {
                  name = head m;
                  value = {
                    path = path + "/${name}";
                    type = "file";
                  };
                }
              else
                null
            ) (attrNames entries)
          )
        );
      in
      dirs // files;

  # Like scanDir but for hosts: walks subdirs looking for sentinel files
  # (e.g. configuration.nix) to determine host type.
  # Returns { name = { type; configPath; hostPath; }; ... }.
  scanHosts =
    path: hostTypes:
    if !pathExists path then
      { }
    else
      let
        entries = readDir path;

        # Process a single entry in the directory
        processEntry =
          name: type:
          let
            subPath = path + "/${name}";
          in
          if type != "directory" then
            { } # Skip files
          else
            let
              # 1. Check if this specific directory is a host
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

              # 2. Recursively scan inside this directory for deeper hosts
              innerHosts = scanHosts subPath hostTypes;
            in
            # Merge the host found at this level (if any) with deeper hosts
            currentHost // innerHosts;

        # Map over all entries and get a list of attribute sets
        listOfAttrs = builtins.mapAttrsToList processEntry entries;
      in
      # Merge all the collected attribute sets together into one flat result
      builtins.foldl' (a: b: a // b) { } listOfAttrs;

  # Scan subdirectories of a path, applying f to each.
  # Returns { name = f (path + "/${name}"); ... } or {} if path is missing.
  scanSubdirs =
    path: f:
    if !pathExists path then
      { }
    else
      let
        entries = readDir path;
      in
      listToAttrs (
        map (name: {
          inherit name;
          value = f (path + "/${name}");
        }) (filter (name: entries.${name} == "directory") (attrNames entries))
      );

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

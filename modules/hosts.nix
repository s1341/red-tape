# red-tape/hosts — Discover and build host configurations
let
  inherit (import ../lib/internal.nix) scanHosts;

  # Host type sentinels — checked in order, first match wins.
  coreHostTypes = [
    {
      type = "custom";
      file = "default.nix";
    }
    {
      type = "nixos";
      file = "configuration.nix";
    }
  ];
  inherit (builtins)
    addErrorContext
    attrNames
    concatStringsSep
    filter
    foldl'
    concatLists
    length
    listToAttrs
    map
    ;

  defaultHostTypes = {
    custom = {
      outputKey = "nixosConfigurations";
      build =
        {
          name,
          info,
          specialArgs,
          inputs,
        }:
        import info.configPath {
          inherit (specialArgs) flake inputs;
          hostName = name;
        };
    };
    nixos = {
      outputKey = "nixosConfigurations";
      build =
        {
          name,
          info,
          specialArgs,
          inputs,
        }:
        inputs.nixpkgs.lib.nixosSystem {
          modules = [ info.configPath ];
          specialArgs = specialArgs // {
            hostName = name;
          };
        };
    };
  };

  buildHosts =
    {
      discovered,
      inputs,
      self,
      extraHostTypes ? { },
      hostNameMode ? "leaf",
    }:
    let
      specialArgs = {
        flake = self;
        inherit inputs;
      };
      hostTypes = defaultHostTypes // extraHostTypes;

      loadHost =
        name: info:
        addErrorContext "while building host '${name}' (${info.type})" (
          let
            builder = hostTypes.${info.type} or null;
          in
          if builder == null then
            throw "red-tape: unknown host type '${info.type}' for '${name}'"
          else
            {
              type = info.type;
              outputKey = builder.outputKey;
              value = builder.build {
                inherit
                  name
                  info
                  specialArgs
                  inputs
                  ;
              };
            }
        );

      isHostInfo = x: x ? type && x ? configPath && x ? hostPath;

      flattenHosts =
        prefix: tree:
        concatLists (
          map (
            n:
            let
              value = tree.${n};
              path = prefix ++ [ n ];
              name = if hostNameMode == "hyphenated" then concatStringsSep "-" path else n;
            in
            if isHostInfo value then
              [
                {
                  inherit name;
                  info = value;
                }
              ]
            else
              flattenHosts path value
          ) (attrNames tree)
        );

      hostEntries = flattenHosts [ ] discovered;
      hostNames = map (h: h.name) hostEntries;
      duplicateNames = filter (n: length (filter (m: m == n) hostNames) > 1) hostNames;
      duplicateHostNames = attrNames (
        listToAttrs (
          map (name: {
            inherit name;
            value = null;
          }) duplicateNames
        )
      );

      checkedHostEntries =
        if duplicateHostNames == [ ] then
          hostEntries
        else if hostNameMode == "leaf" then
          throw "red-tape: duplicate host names are not allowed in leaf mode: ${concatStringsSep ", " duplicateHostNames}"
        else
          throw "red-tape: duplicate hyphenated host names: ${concatStringsSep ", " duplicateHostNames}";

      loaded = listToAttrs (
        map (h: {
          inherit (h) name;
          value = loadHost h.name h.info;
        }) checkedHostEntries
      );

      outputKeys = attrNames (
        listToAttrs (
          map (n: {
            name = loaded.${n}.outputKey;
            value = null;
          }) (attrNames loaded)
        )
      );

      projectOutput =
        key:
        listToAttrs (
          filter (x: x != null) (
            map (
              n:
              let
                value = loaded.${n};
              in
              if value.outputKey == key then
                {
                  name = n;
                  value = value.value;
                }
              else
                null
            ) (attrNames loaded)
          )
        );

      byOutputKey = foldl' (acc: key: acc // { ${key} = projectOutput key; }) { } outputKeys;

      autoChecks =
        system:
        listToAttrs (
          filter (x: x != null) (
            map (
              n:
              let
                value = loaded.${n};
                s = value.value.config.nixpkgs.hostPlatform.system or null;
              in
              if s == system then
                {
                  name = "${value.type}-${n}";
                  value = value.value.config.system.build.toplevel;
                }
              else
                null
            ) (attrNames loaded)
          )
        );
    in
    byOutputKey // { inherit autoChecks; };
in
{
  name = "hosts";
  options = {
    hostNameMode = {
      type = {
        name = "leaf-or-hyphenated";
        verify =
          v: if v == "leaf" || v == "hyphenated" then null else "expected \"leaf\" or \"hyphenated\"";
      };
      default = "leaf";
    };
  };
  inputs = {
    project = {
      path = "../project";
    };
    contrib = {
      path = "../contrib";
    };
  };
  impl =
    { options, results, ... }:
    let
      src = results.project.resolvedSrc;
      inherit (results.project) self inputs;
      hostTypes = coreHostTypes ++ results.contrib.scanHostTypes;
      discovered = scanHosts (src + "/hosts") hostTypes;
    in
    if discovered != { } then
      buildHosts {
        inherit discovered inputs self;
        extraHostTypes = results.contrib.hostTypes;
        inherit (options) hostNameMode;
      }
    else
      {
        nixosConfigurations = { };
        autoChecks = _: { };
      };
}

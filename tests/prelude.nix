# Test prelude — shared setup for all test files
let
  discover = import ../lib/internal.nix;

  lib = { };

  mockPkgs = {
    system = "x86_64-linux";
    inherit lib;
    mkShell = args: { type = "devshell"; } // args;
    hello = {
      type = "derivation";
      name = "hello";
      meta = { };
    };
    jq = {
      type = "derivation";
      name = "jq";
      meta = { };
    };
    writeShellScriptBin = name: text: {
      type = "derivation";
      inherit name;
      meta = { };
    };
    runCommand = name: env: cmd: {
      type = "derivation";
      inherit name;
      meta = { };
    };
    nodejs = {
      type = "derivation";
      name = "nodejs";
      meta = { };
    };
    nixfmt-tree = {
      type = "derivation";
      name = "nixfmt-tree";
      meta = { };
    };
  };

  sys = "x86_64-linux";
  fixtures = ../tests/fixtures;

  helpers = import ../lib/internal.nix;

  # Domain builders — extracted for direct testing without adios runtime
  inherit (builtins)
    addErrorContext
    all
    attrNames
    concatStringsSep
    concatLists
    elem
    filter
    foldl'
    functionArgs
    intersectAttrs
    isAttrs
    isFunction
    length
    listToAttrs
    map
    mapAttrs
    ;
  inherit (helpers) entryPath;

  # Host type sentinels for scanning — matches modules/hosts.nix
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

  # Host type builders for testing
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
      inputs ? { },
      self ? null,
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
                h = loaded.${n};
              in
              if h.outputKey == key then
                {
                  name = n;
                  value = h.value;
                }
              else
                null
            ) (attrNames loaded)
          )
        );

      byOutputKey = foldl' (acc: key: acc // { ${key} = projectOutput key; }) { } outputKeys;

      autoChecks =
        system:
        listToAttrs (filter (x: x != null) (
          map (
            n:
            let
              h = loaded.${n};
              s = h.value.config.nixpkgs.hostPlatform.system or null;
            in
            if s == system then
              {
                name = "${h.type}-${n}";
                value = h.value.config.system.build.toplevel;
              }
            else
              null
          ) (attrNames loaded)
        )) { } (attrNames byOutputKey);
    in
    byOutputKey // { inherit autoChecks; };

  defaultModuleTypes = {
    nixos = "nixosModules";
  };

  buildModules =
    {
      discovered,
      inputs ? { },
      self ? null,
      extraModuleTypes ? { },
    }:
    let
      publisherArgs = {
        flake = self;
        inherit inputs;
      };
      moduleTypes = defaultModuleTypes // extraModuleTypes;
      isPublisherFn =
        fn:
        isFunction fn
        && (functionArgs fn) != { }
        && all (
          a:
          elem a [
            "flake"
            "inputs"
          ]
        ) (attrNames (functionArgs fn));
      importModule =
        e:
        let
          path = entryPath e;
          mod = import path;
        in
        if isPublisherFn mod then
          {
            _file = toString path;
            imports = [ (mod (intersectAttrs (functionArgs mod) publisherArgs)) ];
          }
        else
          path;
      importTree =
        tree:
        mapAttrs (
          _: value: if value ? path && value ? type then importModule value else importTree value
        ) tree;

      built = mapAttrs (_: importTree) discovered;

      aliased = foldl' (
        acc: t:
        let
          alias = moduleTypes.${t} or null;
        in
        if alias != null then acc // { ${alias} = built.${t}; } else acc
      ) { } (attrNames discovered);
    in
    aliased // (if built != { } then { modules = built; } else { });

  builders = { inherit buildHosts buildModules; };
in
{
  inherit
    mockPkgs
    sys
    fixtures
    discover
    helpers
    builders
    coreHostTypes
    ;
}

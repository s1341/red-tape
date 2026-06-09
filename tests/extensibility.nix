let
  prelude = import ./prelude.nix;
  inherit (prelude)
    discover
    helpers
    builders
    fixtures
    mockPkgs
    ;
  inherit (helpers) entryPath;
  inherit (builders) buildHosts buildModules;
  inherit (prelude) coreHostTypes;
  inherit (discover) scanDir scanHosts scanSubdirs;
in
{
  testScanCustomHostType = {
    expr =
      let
        found = scanHosts (fixtures + "/custom-hosts/hosts") [
          {
            type = "nix-on-droid";
            file = "droid-configuration.nix";
          }
        ];
      in
      {
        names = builtins.attrNames found;
        type = found.myphone.type;
      };
    expected = {
      names = [ "myphone" ];
      type = "nix-on-droid";
    };
  };
  testCoreHostTypesIgnoreCustom = {
    expr = scanHosts (fixtures + "/custom-hosts/hosts") coreHostTypes;
    expected = { };
  };
  testScanHostsFirstMatchWins = {
    expr =
      let
        found = scanHosts (fixtures + "/full/hosts") [
          {
            type = "custom";
            file = "default.nix";
          }
          {
            type = "nixos";
            file = "configuration.nix";
          }
        ];
      in
      {
        customType = found.custom.type;
        myhostType = found.myhost.type;
      };
    expected = {
      customType = "custom";
      myhostType = "nixos";
    };
  };
  testHomeManagerContribBuildsHomeConfigurations = {
    expr =
      let
        homeManagerContrib = (import ../contrib/home-manager.nix).impl {
          results.scope.pkgs = mockPkgs;
        };
        found = scanHosts (fixtures + "/home-manager/hosts") homeManagerContrib.scanHostTypes;
        result = buildHosts {
          discovered = found;
          inputs = {
            home-manager.lib.homeManagerConfiguration = args: {
              _type = "home-manager-configuration";
              inherit (args)
                pkgs
                modules
                extraSpecialArgs
                ;
            };
          };
          extraHostTypes = homeManagerContrib.hostTypes;
        };
      in
      {
        names = builtins.attrNames result.homeConfigurations;
        type = result.homeConfigurations.alice._type;
        pkgsSystem = result.homeConfigurations.alice.pkgs.system;
        moduleIsPath = builtins.isPath (builtins.head result.homeConfigurations.alice.modules);
        hostName = result.homeConfigurations.alice.extraSpecialArgs.hostName;
      };
    expected = {
      names = [ "alice" ];
      type = "home-manager-configuration";
      pkgsSystem = "x86_64-linux";
      moduleIsPath = true;
      hostName = "alice";
    };
  };
  testScanModuleSubdirs = {
    expr =
      let
        modulesPath = fixtures + "/full/modules";
        entries = builtins.readDir modulesPath;
        types = builtins.filter (n: entries.${n} == "directory") (builtins.attrNames entries);
      in
      builtins.sort builtins.lessThan types;
    expected = [
      "darwin"
      "home"
      "nixos"
    ];
  };
  testUnknownModuleTypeSkipped = {
    expr =
      let
        result = buildModules {
          discovered = {
            flake = scanDir (fixtures + "/full/modules/nixos");
          };
        };
      in
      {
        hasAlias = result ? flakeModules;
        hasHierarchy = result ? modules;
        hierarchyKeys = builtins.attrNames result.modules;
      };
    expected = {
      hasAlias = false;
      hasHierarchy = true;
      hierarchyKeys = [ "flake" ];
    };
  };
  testExtraModuleTypes = {
    expr =
      let
        discovered = scanSubdirs (fixtures + "/custom-modules/modules") scanDir;
        result = buildModules {
          inherit discovered;
          extraModuleTypes = {
            flake = "flakeModules";
          };
        };
      in
      {
        keys = builtins.sort builtins.lessThan (builtins.attrNames result);
        modNames = builtins.attrNames (result.flakeModules or { });
      };
    expected = {
      keys = [
        "flakeModules"
        "modules"
      ];
      modNames = [ "mymod" ];
    };
  };
}

# Tests for the adios module tree
{ adios-flake }:
let
  prelude = import ./prelude.nix;
  inherit (prelude) mockPkgs sys fixtures;

  adiosLib = adios-flake.inputs.adios.adios;
  redTape = import ../lib { inherit adios-flake; };
  mkRootModule =
    contribs:
    let
      base = redTape.modules.redTape.default;
      contribMod = base.modules.contrib;
      numberedContribs = builtins.genList (i: {
        name = "_c${toString i}";
        value = builtins.removeAttrs (builtins.elemAt contribs i) [ "name" ];
      }) (builtins.length contribs);
      contribChildren = builtins.listToAttrs numberedContribs;
      contribInputs = builtins.listToAttrs (
        map (c: {
          inherit (c) name;
          value = {
            path = "./${c.name}";
          };
        }) numberedContribs
      );
    in
    base
    // {
      modules = base.modules // {
        contrib = contribMod // {
          inputs = contribMod.inputs or { } // contribInputs;
          modules = (contribMod.modules or { }) // contribChildren;
        };
      };
    };

  evalFixture =
    {
      src,
      prefix ? null,
      modulesOpts ? { },
      rootModule ? redTape.modules.redTape.default,
      projectInputs ? { },
      hostsOpts ? { },
    }:
    let
      rootDef = {
        modules = {
          "red-tape" = builtins.removeAttrs rootModule [ "name" ];
          nixpkgs = {
            options = {
              system = {
                type = adiosLib.types.string;
              };
              pkgs = {
                type = adiosLib.types.attrs;
              };
            };
          };
        };
      };
      tree = adiosLib rootDef {
        options = {
          "/red-tape/project" = {
            inherit src;
            inputs = projectInputs;
          }
          // (if prefix != null then { inherit prefix; } else { });
          "/red-tape/modules" = modulesOpts;
          "/nixpkgs" = {
            system = sys;
            pkgs = mockPkgs;
          };
          "/red-tape" = { };
          "/red-tape/scope" = { };
          "/red-tape/packages" = { };
          "/red-tape/devshells" = { };
          "/red-tape/checks" = { };
          "/red-tape/formatter" = { };
          "/red-tape/hosts" = hostsOpts;
          "/red-tape/templates" = { };
          "/red-tape/lib" = { };
        };
      };
    in
    tree.modules.${"red-tape"} { };

  fullResult = evalFixture { src = fixtures + "/full"; };
  prefixResult = evalFixture {
    src = fixtures + "/prefixed";
    prefix = "nix";
  };
  minimalResult = evalFixture { src = fixtures + "/minimal"; };
  homeManagerResult = evalFixture {
    src = fixtures + "/home-manager";
    rootModule = mkRootModule [ redTape.modules.redTape.home-manager ];
    projectInputs = {
      nixpkgs.lib.nixosSystem = args: {
        _type = "nixos-system";
        inherit (args) modules specialArgs;
        config = {
          nixpkgs.hostPlatform.system = "x86_64-linux";
          system.build.toplevel = {
            type = "derivation";
            name = "alice-system";
            meta = { };
          };
        };
      };
      home-manager.lib.homeManagerConfiguration = args: {
        _type = "home-manager-configuration";
        inherit (args)
          pkgs
          modules
          extraSpecialArgs
          ;
      };
    };
  };
  hyphenatedHostsResult = evalFixture {
    src = fixtures + "/full";
    hostsOpts = {
      hostNameMode = "hyphenated";
    };
  };
in
{
  testModulePackageNames = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames fullResult.packages);
    expected = [
      "goodbye"
      "hello"
      "tools"
    ];
  };
  testModuleNestedPackage = {
    expr = fullResult.packages.tools.extra.type;
    expected = "derivation";
  };
  testModuleDevShellNames = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames fullResult.devShells);
    expected = [
      "backend"
      "default"
      "tools"
    ];
  };
  testModuleFormatterPresent = {
    expr = fullResult.formatter != null;
    expected = true;
  };
  testMinimalChecksHasPackage = {
    expr = minimalResult.checks ? "pkgs-default";
    expected = true;
  };
  testPrefixModulePackageNames = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames prefixResult.packages);
    expected = [
      "default"
      "widget"
    ];
  };
  testMinimalFormatterFallback = {
    expr = minimalResult.formatter.name;
    expected = "nixfmt-tree";
  };
  testNixosModuleNames = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames fullResult.nixosModules);
    expected = [
      "core"
      "injected"
      "server"
    ];
  };
  testNestedNixosModuleName = {
    expr = builtins.isPath fullResult.nixosModules.core.extra.foo;
    expected = true;
  };
  testTemplateNames = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames fullResult.templates);
    expected = [
      "default"
      "group"
      "minimal"
    ];
  };
  testHomeManagerContribOutput = {
    expr = {
      names = builtins.attrNames homeManagerResult.homeConfigurations;
      nixosNames = builtins.attrNames homeManagerResult.nixosConfigurations;
      type = homeManagerResult.homeConfigurations.alice._type;
      nixosType = homeManagerResult.nixosConfigurations.alice._type;
      pkgsSystem = homeManagerResult.homeConfigurations.alice.pkgs.system;
      hostName = homeManagerResult.homeConfigurations.alice.extraSpecialArgs.hostName;
    };
    expected = {
      names = [ "alice" ];
      nixosNames = [ "alice" ];
      type = "home-manager-configuration";
      nixosType = "nixos-system";
      pkgsSystem = "x86_64-linux";
      hostName = "alice";
    };
  };
  testNestedTemplate = {
    expr = fullResult.templates.group.app.description;
    expected = "A nested template";
  };
  testHostNamesFlattenInLeafMode = {
    expr = builtins.sort builtins.lessThan (builtins.attrNames fullResult.nixosConfigurations);
    expected = [
      "app"
      "custom"
      "db"
      "monitoring"
      "myhost"
      "mymac"
    ];
  };
  testHostNamesHyphenatedMode = {
    expr = builtins.sort builtins.lessThan (
      builtins.attrNames hyphenatedHostsResult.nixosConfigurations
    );
    expected = [
      "custom"
      "db"
      "group-app"
      "monitoring"
      "myhost"
      "mymac"
    ];
  };
  testLibPresent = {
    expr = fullResult ? lib;
    expected = true;
  };
}

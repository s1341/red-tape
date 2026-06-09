# Tests for host building
let
  prelude = import ./prelude.nix;
  inherit (prelude)
    discover
    builders
    fixtures
    coreHostTypes
    ;
  inherit (discover) scanHosts;
  inherit (builders) buildHosts;

  fullHosts = scanHosts (fixtures + "/full/hosts") coreHostTypes;
  duplicateHosts = scanHosts (fixtures + "/duplicate-hosts/hosts") coreHostTypes;

  testHostTypes = {
    nixos = {
      outputKey = "nixosConfigurations";
      build =
        {
          name,
          info,
          specialArgs,
          inputs,
        }:
        {
          value = {
            _type = "test-nixos-system";
            hostName = name;
          };
        };
    };
  };

  testResult = buildHosts {
    discovered = { inherit (fullHosts) custom; };
  };

  fullResult = buildHosts {
    discovered = fullHosts;
    extraHostTypes = testHostTypes;
  };
in
{
  testCustomHostLoaded = {
    expr = testResult.nixosConfigurations.custom.value._type;
    expected = "test-nixos-system";
  };

  testCustomHostName = {
    expr = testResult.nixosConfigurations.custom.value.hostName;
    expected = "custom";
  };

  testEmptyHosts = {
    expr =
      let
        result = buildHosts { discovered = { }; };
      in
      {
        hasAutoChecks = builtins.isFunction result.autoChecks;
        noOutputKeys = builtins.attrNames (builtins.removeAttrs result [ "autoChecks" ]);
      };
    expected = {
      hasAutoChecks = true;
      noOutputKeys = [ ];
    };
  };

  testHostDiscoveryTypes = {
    expr =
      let
        hosts = scanHosts (fixtures + "/full/hosts") coreHostTypes;
      in
      {
        myhost = hosts.myhost.type;
        custom = hosts.custom.type;
        nested = hosts.group.app.type;
      };
    expected = {
      myhost = "nixos";
      custom = "custom";
      nested = "nixos";
    };
  };

  testHostsFlattenInLeafMode = {
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

  testNestedHostNameInLeafMode = {
    expr = fullResult.nixosConfigurations.app.value.hostName;
    expected = "app";
  };

  testDuplicateHostsRejectedInLeafMode = {
    expr =
      (builtins.tryEval (
        builtins.attrNames (
          (buildHosts {
            discovered = duplicateHosts;
          }).nixosConfigurations
        )
      )).success;
    expected = false;
  };

  testDuplicateHostsAllowedInHyphenatedMode = {
    expr =
      let
        result = buildHosts {
          discovered = duplicateHosts;
          hostNameMode = "hyphenated";
        };
      in
      {
        names = builtins.sort builtins.lessThan (builtins.attrNames result.nixosConfigurations);
        hostName = result.nixosConfigurations.a-web.value.hostName;
      };
    expected = {
      names = [
        "a-web"
        "b-web"
      ];
      hostName = "a-web";
    };
  };
}

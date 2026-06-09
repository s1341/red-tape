# Tests for per-type scanning patterns (matching what modules do)
let
  prelude = import ./prelude.nix;
  inherit (prelude) discover coreHostTypes;
  inherit (discover)
    scanDir
    scanHosts
    scanEntries
    scanSubdirs
    ;
  inherit (builtins) attrNames pathExists;

  sort = builtins.sort builtins.lessThan;

  inherit (prelude) fixtures;

  # Per-type scanning — mirrors what each module does internally
  scanPackages =
    src:
    scanEntries {
      dir = src + "/packages";
      single = src + "/package.nix";
    };
  scanDevshells =
    src:
    scanEntries {
      dir = src + "/devshells";
      single = src + "/devshell.nix";
    };
  scanChecks = src: scanEntries { dir = src + "/checks"; };

  scanFormatter =
    src:
    let
      p = src + "/formatter.nix";
    in
    if pathExists p then p else null;

  scanModules = src: scanSubdirs (src + "/modules") scanDir;
  scanTemplates =
    src:
    discover.scanDirsWithFile (src + "/templates") "flake.nix" (path: {
      inherit path;
    });

  scanLib =
    src:
    let
      p = src + "/lib/default.nix";
    in
    if pathExists p then p else null;

  full = fixtures + "/full";
  minimal = fixtures + "/minimal";
  empty = fixtures + "/empty";
in
{
  # --- Full fixture ---

  testFullPackages.expr = sort (attrNames (scanPackages full));
  testFullPackages.expected = [
    "goodbye"
    "hello"
    "tools"
  ];

  testFullDevshells.expr = sort (attrNames (scanDevshells full));
  testFullDevshells.expected = [
    "backend"
    "default"
    "tools"
  ];

  testFullChecks.expr = attrNames (scanChecks full);
  testFullChecks.expected = [
    "mycheck"
    "quality"
  ];

  testFullFormatter.expr = (scanFormatter full) != null;
  testFullFormatter.expected = true;

  testFullHosts.expr = sort (attrNames (scanHosts (full + "/hosts") coreHostTypes));
  testFullHosts.expected = [
    "custom"
    "db"
    "group"
    "monitoring"
    "myhost"
    "mymac"
  ];

  testFullHostTypes = {
    expr =
      let
        h = scanHosts (full + "/hosts") coreHostTypes;
      in
      {
        myhost = h.myhost.type;
        mymac = h.mymac.type;
        custom = h.custom.type;
      };
    expected = {
      myhost = "nixos";
      mymac = "custom";
      custom = "custom";
    };
  };

  testFullModuleTypes.expr = sort (attrNames (scanModules full));
  testFullModuleTypes.expected = [
    "darwin"
    "home"
    "nixos"
  ];

  testFullNixosModules.expr = sort (attrNames (scanModules full).nixos);
  testFullNixosModules.expected = [
    "core"
    "injected"
    "server"
  ];

  testFullHomeModules.expr = attrNames (scanModules full).home;
  testFullHomeModules.expected = [ "shared" ];

  testFullTemplates.expr = sort (attrNames (scanTemplates full));
  testFullTemplates.expected = [
    "default"
    "group"
    "minimal"
  ];

  testNestedDiscovery = {
    expr =
      let
        packages = scanPackages full;
        devshells = scanDevshells full;
        checks = scanChecks full;
        hosts = scanHosts (full + "/hosts") coreHostTypes;
        modules = scanModules full;
        templates = scanTemplates full;
      in
      {
        package = packages.tools.extra.type;
        devshell = devshells.tools.backend.type;
        check = checks.quality.lint.type;
        host = hosts.group.app.type;
        module = modules.nixos.core.extra.foo.type;
        template = templates.group.app.path == full + "/templates/group/app";
      };
    expected = {
      package = "file";
      devshell = "file";
      check = "file";
      host = "nixos";
      module = "file";
      template = true;
    };
  };

  testFullLib.expr = (scanLib full) != null;
  testFullLib.expected = true;

  # --- Minimal fixture ---

  testMinimalPackage.expr = attrNames (scanPackages minimal);
  testMinimalPackage.expected = [ "default" ];

  testMinimalNoFormatter.expr = scanFormatter minimal;
  testMinimalNoFormatter.expected = null;

  # --- Empty fixture ---

  testEmpty = {
    expr = {
      packages = scanPackages empty;
      devshells = scanDevshells empty;
      checks = scanChecks empty;
      hosts = scanHosts (empty + "/hosts") coreHostTypes;
      modules = scanModules empty;
      formatter = scanFormatter empty;
      templates = scanTemplates empty;
    };
    expected = {
      packages = { };
      devshells = { };
      checks = { };
      hosts = { };
      modules = { };
      formatter = null;
      templates = { };
    };
  };

  # --- Prefixed fixture ---

  testPrefixedPackages.expr = sort (attrNames (scanPackages (fixtures + "/prefixed/nix")));
  testPrefixedPackages.expected = [
    "default"
    "widget"
  ];
}

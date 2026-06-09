# Tests for scanDir
let
  discover = import ../lib/internal.nix;
  inherit (discover) scanDir;
  fixtures = ../tests/fixtures;
  full = fixtures + "/full";
in
{
  testPackages = {
    expr = builtins.attrNames (scanDir (full + "/packages"));
    expected = [
      "goodbye"
      "hello"
      "tools"
    ];
  };

  testFileType = {
    expr = (scanDir (full + "/packages")).hello.type;
    expected = "file";
  };

  testDirType = {
    expr = (scanDir (full + "/packages")).goodbye.type;
    expected = "directory";
  };

  testDevshells = {
    expr = builtins.attrNames (scanDir (full + "/devshells"));
    expected = [
      "backend"
      "tools"
    ];
  };

  testNonExistent = {
    expr = scanDir (full + "/nonexistent");
    expected = { };
  };

  testEmpty = {
    expr = scanDir (fixtures + "/empty");
    expected = { };
  };

  testChecks = {
    expr = builtins.attrNames (scanDir (full + "/checks"));
    expected = [
      "mycheck"
      "quality"
    ];
  };

  testNestedPaths = {
    expr =
      let
        packages = scanDir (full + "/packages");
        devshells = scanDir (full + "/devshells");
        checks = scanDir (full + "/checks");
      in
      {
        package = packages.tools.extra.type;
        devshell = devshells.tools.backend.type;
        check = checks.quality.lint.type;
      };
    expected = {
      package = "file";
      devshell = "file";
      check = "file";
    };
  };
}

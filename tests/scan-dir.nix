# Tests for scanDir
let
  discover = import ../lib/internal.nix;
  inherit (discover) scanDir;
  fixtures = ../tests/fixtures;
  full = fixtures + "/full";
  recursive = fixtures + "/recursive-scan";
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

  testRecursiveShape = {
    expr =
      let
        packages = scanDir (recursive + "/packages");
      in
      {
        branch = packages.branch.leaf.tool.type;
        mergeA = packages.merge.a.tool.type;
        mergeB = packages.merge.b.tool.type;
      };
    expected = {
      branch = "file";
      mergeA = "file";
      mergeB = "file";
    };
  };

  testDirectoryEntryStopsRecursion = {
    expr =
      let
        entry = (scanDir (recursive + "/packages")).dir-entry;
      in
      {
        inherit (entry) type;
        hasNested = entry ? nested;
      };
    expected = {
      type = "directory";
      hasNested = false;
    };
  };

  testFilePrecedenceOverDirectoryStem = {
    expr =
      let
        packages = scanDir (recursive + "/packages");
      in
      {
        sameStem = packages.same-stem.type;
        sameStemPath = packages.same-stem.path == recursive + "/packages/same-stem.nix";
        fileVsBranch = packages.file-vs-branch.type;
        fileVsBranchPath = packages.file-vs-branch.path == recursive + "/packages/file-vs-branch.nix";
      };
    expected = {
      sameStem = "file";
      sameStemPath = true;
      fileVsBranch = "file";
      fileVsBranchPath = true;
    };
  };
}

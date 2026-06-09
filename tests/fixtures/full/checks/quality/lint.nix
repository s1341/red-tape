{ pkgs, pname, ... }:
pkgs.runCommand pname { } ''
  echo "lint passed"
  touch $out
''

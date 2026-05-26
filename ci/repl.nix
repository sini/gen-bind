# gen-bind REPL — all exports in scope.
let
  nixpkgs = import (builtins.getFlake "nixpkgs") { };
  bindLib = import ../nix/lib { inherit (nixpkgs) lib; };
in
{
  inherit (nixpkgs) lib;
  inherit bindLib;
}
// bindLib

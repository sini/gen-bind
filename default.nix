{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
  ...
}:
import ./nix/lib { inherit lib; }

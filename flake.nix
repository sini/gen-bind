{
  description = "gen-bind: module binding with external arguments for Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      bindLib = import ./nix/lib { lib = nixpkgs.lib; };
    in
    {
      lib = bindLib;
    };
}

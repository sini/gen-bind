{
  inputs = {
    gen.url = "github:sini/gen";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{ gen, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
      bindLib = import ../nix/lib { inherit lib; };
    in
    gen.lib.mkCi {
      inherit inputs;
      name = "gen-bind";
      testModules = ./tests;
      specialArgs = { inherit bindLib; };
    };
}

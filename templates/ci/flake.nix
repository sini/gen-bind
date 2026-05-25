{
  inputs = {
    gen-bind.url = "github:sini/gen-bind";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      gen-bind,
      nixpkgs,
      nix-unit,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      bindLib = gen-bind.lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;
      testFiles = lib.pipe (builtins.readDir ./tests) [
        (lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".nix" n))
        builtins.attrNames
      ];
      tests = lib.foldl' (
        acc: file: acc // (import ./tests/${file} { inherit lib bindLib; })
      ) { } testFiles;
    in
    {
      inherit tests;
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [ nix-unit.packages.${system}.default ];
          };
        }
      );
    };
}

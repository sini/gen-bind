{
  inputs = {
    gen.url = "github:sini/gen";
    gen-prelude.url = "github:sini/gen-prelude";
    # nixpkgs is the CI runner's dependency (test harness, treefmt) and supplies the
    # REAL `lib.evalModules` the equivalence gate drives gen-bind output through. The
    # library itself (../lib) takes only gen-prelude — see the purity remediation.
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{
      gen,
      gen-prelude,
      ...
    }:
    let
      prelude = import "${gen-prelude}/lib" { };
      genBind = import ../lib { inherit prelude; };
    in
    gen.lib.mkCi {
      inherit inputs;
      name = "gen-bind";
      testModules = ./tests;
      specialArgs = { inherit genBind; };
    };
}

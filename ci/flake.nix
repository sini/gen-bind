{
  inputs = {
    gen-harness.url = "github:sini/gen-harness";
    gen-prelude.url = "github:sini/gen-prelude";
    # nixpkgs is the CI runner's dependency (test harness, treefmt) and supplies the
    # REAL `lib.evalModules` the equivalence gate drives gen-bind output through. The
    # library itself (../lib) takes only gen-prelude — see the purity remediation.
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{
      gen-harness,
      gen-prelude,
      ...
    }:
    let
      prelude = import "${gen-prelude}/lib";
      genBind = import ../lib { inherit prelude; };
    in
    gen-harness.lib.mkCi {
      inherit inputs;
      name = "gen-bind";
      testModules = ./tests;
      # `prelude` reaches the suite because `tests/entry.nix` applies the STANDALONE root entry with
      # explicit arguments — which is what keeps that cell pure, since supplying the formal means the
      # shim's fetching default is never forced. It is the SAME instance `genBind` above is built
      # from, so the two sides of that comparison differ in entry point and in nothing else.
      specialArgs = { inherit genBind prelude; };
    };
}

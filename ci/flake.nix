{
  inputs = {
    gen-harness.url = "github:sini/gen-harness";
    gen-prelude.url = "github:sini/gen-prelude";
    gen-graph = {
      url = "github:sini/gen-graph";
      inputs.gen-prelude.follows = "gen-prelude";
    };
    # ★★ gen-delivery IS A TEST DEPENDENCY AND ONLY A TEST DEPENDENCY, ON THE SAME
    # TERMS AS gen-scope is for gen-view's own `ci/flake.nix`. O-1's oracle
    # (specs/2026-09-08-gen-bind-extent-peer-read-shape-spec.md §3) is explicit:
    # "Wire the real `gen-delivery.realize` into the real `gen-bind`
    # `mkHostedTerminal` adapter" — a hand-written fold in the test file would make
    # every cell built on it an assertion about the fixture rather than about the
    # real class-major fold `realize` performs. `gen-delivery` itself declares ZERO
    # flake inputs (its `flake.nix` publishes `lib = import ./.;`, UNAPPLIED); its
    # own `algebra`/`aspects` formals resolve via ITS OWN `ci/flake.lock`-pinned
    # fetch when called with `{ }`, so this one input pulls in no further gen-bind
    # input — `gen-bind` gains no edge onto gen-algebra or gen-aspects.
    gen-delivery.url = "github:sini/gen-delivery";
    # ★★ gen-view IS ALSO A TEST DEPENDENCY ONLY — O-6's oracle (spec §3) reads
    # `gen-view/lib/carrier.nix`'s own `elementOf`, "a tag, not an attribute-name
    # match", so the check that the peer relation is a genuine tagged carrier
    # element has to be the SUBSTRATE's own check, not a re-implementation of it
    # in this test file. `carrier.nix` takes `{ prelude, graph }:` and nothing
    # else, so this import goes straight to that one file with the SAME
    # `prelude`/`graph` instance below — no `follows` wiring is needed because
    # gen-view's own flake outputs are never resolved.
    gen-view.url = "github:sini/gen-view";
    # nixpkgs is the CI runner's dependency (test harness, treefmt) and supplies the
    # REAL `lib.evalModules` the equivalence gate drives gen-bind output through. The
    # library itself (../lib) takes gen-prelude and gen-graph — see the purity
    # remediation and specs/2026-09-08-gen-bind-extent-peer-read-shape-spec.md §4.1.
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{
      gen-harness,
      gen-prelude,
      gen-graph,
      gen-delivery,
      gen-view,
      ...
    }:
    let
      prelude = import "${gen-prelude}/lib";
      graph = import "${gen-graph}/lib" { inherit prelude; };
      genBind = import ../lib { inherit prelude graph; };
      # Called with `{ }`: gen-delivery resolves its own `algebra`/`aspects`
      # through its own standalone entry's `ci/flake.lock`-pinned defaults — the
      # same channel `genBind`'s own standalone shim uses for `prelude`/`graph`.
      genDelivery = gen-delivery.lib { };
      genViewCarrier = import "${gen-view}/lib/carrier.nix" { inherit prelude graph; };
    in
    gen-harness.lib.mkCi {
      inherit inputs;
      name = "gen-bind";
      testModules = ./tests;
      # `prelude` reaches the suite because `tests/entry.nix` applies the STANDALONE root entry with
      # explicit arguments — which is what keeps that cell pure, since supplying the formal means the
      # shim's fetching default is never forced. It is the SAME instance `genBind` above is built
      # from, so the two sides of that comparison differ in entry point and in nothing else.
      specialArgs = {
        inherit
          genBind
          prelude
          graph
          genDelivery
          genViewCarrier
          ;
      };
    };
}

{
  description = "gen-bind: module binding with external arguments for Nix";

  # gen-bind is nixpkgs-lib-free (purity remediation): it stays module-system-*aware*
  # — it emits modules in the nixpkgs `__functionArgs`/`_file` convention via
  # locally-vendored helpers (lib/module-convention.nix) — but imports no
  # `nixpkgs.lib`. TWO dependencies now, both pure and nixpkgs-lib-free:
  # gen-prelude and gen-graph — the already-shipped ADR-0026 boundary-mark
  # mechanism the extent peer-read shape reuses rather than reconstructs
  # (specs/2026-09-08-gen-bind-extent-peer-read-shape-spec.md §2.2, §4.1 Q1 Arm
  # B: "gen-bind acquires gen-graph, ending its one-input shape").
  #
  # ★ THE `follows` IS LOAD-BEARING, NOT HYGIENE. Without it gen-graph resolves
  # its own gen-prelude and the lock carries TWO instances of one library. One
  # prelude in the closure means the shim's `graph` and the flake's `graph` are
  # the same construction rather than two that happen to agree.
  inputs = {
    gen-prelude.url = "github:sini/gen-prelude";
    gen-graph = {
      url = "github:sini/gen-graph";
      inputs.gen-prelude.follows = "gen-prelude";
    };
  };

  outputs =
    { gen-prelude, gen-graph, ... }:
    {
      # ★ THE ROOT, NOT `./lib`. `./.` and `./lib` were two independent constructions of one
      # value and so free to disagree; there is ONE construction site now, and the two entry
      # paths differ only in who supplies the arguments. Here the flake supplies them, so
      # `follows` governs every argument passed, while the standalone path falls back to
      # `ci/flake.lock`.
      lib = import ./. {
        prelude = gen-prelude.lib;
        graph = gen-graph.lib;
      };
    };
}

{
  description = "gen-bind: module binding with external arguments for Nix";

  # gen-bind is nixpkgs-lib-free (purity remediation): the library depends only on
  # gen-prelude (pure, zero-input). It stays module-system-*aware* — it emits modules
  # in the nixpkgs `__functionArgs`/`_file` convention via locally-vendored helpers
  # (lib/module-convention.nix) — but imports no `nixpkgs.lib`.
  inputs = {
    gen-prelude.url = "github:sini/gen-prelude";
  };

  outputs =
    { gen-prelude, ... }:
    {
      # `nix flake check` forces the WHNF of every top-level output and nothing deeper, so this root's
      # green quantified over the `lib` SPINE alone: a member of the published surface could throw and
      # the check still exited 0 (measured — den-hoag-z1ta6). Hanging the force on that spine is what
      # makes the green mean "the surface evaluates", and a library needs no new output name for it.
      # The depth is each member's WHNF and no deeper: a retirement tombstone is a published `throw`
      # by design (gen-scope's `buildNodes`), so a deep force is red on a healthy tree.
      lib =
        let
          surface = import ./lib { prelude = gen-prelude.lib; };
        in
        builtins.deepSeq (builtins.mapAttrs (_: builtins.typeOf) surface) surface;
    };
}

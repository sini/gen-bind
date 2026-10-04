{
  description = "gen-bind: module binding with external arguments for Nix";

  # gen-bind is nixpkgs-lib-free (purity remediation): it stays module-system-*aware*
  # — it emits modules in the nixpkgs `__functionArgs`/`_file` convention via
  # locally-vendored helpers (lib/module-convention.nix) — but imports no
  # `nixpkgs.lib`. TWO dependencies, both pure and nixpkgs-lib-free: gen-prelude,
  # and gen-algebra, whose first-order term algebra BodyTerm was extracted into and
  # this library instantiates (den-hoag-lwbb1 unit 1). gen-graph left with the
  # one-calculus migration (den-hoag-gayc U2d): the extent peer read resolves through
  # the carriage's injected `engine` (gen-scope's `resolve`), so this library reads
  # no gen-graph surface.
  inputs = {
    gen-prelude.url = "github:sini/gen-prelude";
    # The term algebra BodyTerm was extracted into (den-hoag-lwbb1 unit 1). gen-algebra declares no
    # inputs, so there is nothing to `follows`.
    gen-algebra.url = "github:sini/gen-algebra";
  };

  outputs =
    {
      gen-prelude,
      gen-algebra,
      ...
    }:
    {
      # ★ THE ROOT, NOT `./lib`. `./.` and `./lib` were two independent constructions of one
      # value and so free to disagree; there is ONE construction site now, and the two entry
      # paths differ only in who supplies the arguments. Here the flake supplies them, so
      # `follows` governs every argument passed, while the standalone path falls back to
      # `ci/flake.lock`.
      lib = import ./. {
        prelude = gen-prelude.lib;
        algebra = gen-algebra.lib;
      };
    };
}

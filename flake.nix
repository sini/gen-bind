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
    let
      genBind = import ./lib { prelude = import "${gen-prelude}/lib" { }; };
    in
    {
      lib = genBind;
    };
}

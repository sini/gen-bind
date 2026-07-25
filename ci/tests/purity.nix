# Purity invariant (gen-prelude design §5): gen-bind depends only on gen-prelude and
# must import NO `nixpkgs.lib`. This pins "pure" as a checked property, not an
# aspiration — a stray `lib.foo` / `lib.types` / `evalModules` / nixpkgs input creeping
# back into the library source fails CI.
#
# Scope: lib/**.nix + the root flake.nix (the library + its flake). NOT ci/ — the
# test harness legitimately uses nixpkgs.lib (including, here, to do this scan).
{ genPrelude, lib, ... }:
let
  libDir = ../../lib;

  # Comment-stripped source: drop everything from the first `#` on each line. Safe here
  # because `#` appears only in comments across these files (no `#` in string literals);
  # documentation may freely mention forbidden tokens (e.g. the vendored helpers' nixpkgs
  # provenance) without tripping the invariant.
  stripComments =
    text:
    lib.concatStringsSep "\n" (
      map (line: lib.head (lib.splitString "#" line)) (lib.splitString "\n" text)
    );

  nixFiles = lib.filter (lib.hasSuffix ".nix") (lib.attrNames (builtins.readDir libDir));
  sources =
    map (name: {
      inherit name;
      code = stripComments (builtins.readFile (libDir + "/${name}"));
    }) nixFiles
    ++ [
      {
        name = "flake.nix";
        code = stripComments (builtins.readFile ../../flake.nix);
      }
      {
        name = "default.nix";
        code = stripComments (builtins.readFile ../../default.nix);
      }
    ];

  # Tokens that signal a nixpkgs-lib tether or the module-system (Korora-class) tier.
  forbidden = [
    "nixpkgs" # a nixpkgs flake input / reference
    "lib." # any nixpkgs lib call (lib.types, lib.genAttrs, lib.setFunctionArgs, …)
    "{ lib }" # the old `{ lib }` parameter signature
    "{ lib," # `{ lib, … }` parameter signature
    "evalModules" # module-system tier
    "mkOption" # module-system tier
  ];

  # arg-env.nix is the ONE module-system-OPERATING file: `crossEval`/`configGate` drive a
  # NESTED `evalModules` and call `mkIf`/`types` at the terminal crossing — but ONLY via a
  # `lib` THREADED IN at runtime (crossEval's `lib` parameter; the module functions'
  # `args.lib`), NEVER an imported `nixpkgs.lib`. Its file signature is `{ ... }:` and the lib
  # is wired as `import ./arg-env.nix { }` (no lib passed at the file boundary), so it CANNOT
  # receive nixpkgs at import — structurally lib-import-free.
  #
  # The exemption whitelists EXACTLY the two tokens this file legitimately uses — `lib.` (the
  # threaded lib's members) and `evalModules` (the nested eval). Every OTHER forbidden token
  # stays banned even here, deliberately:
  #   - `{ lib }` / `{ lib,` — a file-sig change to `{ lib, ... }:` (which nixfmt renders
  #     single-line, matching `{ lib,`) would inject nixpkgs.lib as a DEPENDENCY yet still
  #     ride the `lib.`/`evalModules` exemption. Keeping the sig tokens banned closes that
  #     latent regression: the lib must stay RUNTIME-THREADED, never a file parameter.
  #   - `mkOption` — this file EVALUATES modules; it must never DECLARE options.
  #   - `nixpkgs` — P1 (no-nixpkgs-dependency) stays global, unconditionally.
  # So "no nixpkgs DEPENDENCY" holds for every file; only "never operates the module system"
  # is relaxed, for THIS one crossing file, BY DESIGN (gen-bind G4 charter — see README).
  moduleSystemOperators = [ "arg-env.nix" ];
  argEnvExempt = [
    "lib."
    "evalModules"
  ];
  forbiddenFor =
    name:
    if lib.elem name moduleSystemOperators then
      lib.filter (tok: !(lib.elem tok argEnvExempt)) forbidden
    else
      forbidden;

  violations = lib.concatMap (
    src:
    map (tok: "${src.name}: '${tok}'") (
      lib.filter (tok: genPrelude.hasInfix tok src.code) (forbiddenFor src.name)
    )
  ) sources;
in
{
  flake.tests.purity.test-library-source-is-nixpkgs-lib-free = {
    expr = violations;
    expected = [ ];
  };
}

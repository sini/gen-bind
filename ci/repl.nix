# gen-bind REPL — all exports in scope. Run: nix repl --impure --file ci/repl.nix
#
# The root declares only dependency formals, each defaulted from the root flake.lock, and never
# `lib`. So it is called with this entry's arguments minus `lib`: none under `nix repl --file`,
# where the root resolves its own pins, and the ci flake's own instances under `ci/tests/repl.nix`,
# which keeps that cell from fetching. `prelude` is the one the root wired, read through its `wire`
# seam rather than resolved a second time. `lib` rides beside the surface for convenience only.
{
  lib ? (builtins.getFlake "nixpkgs").lib,
  ...
}@args:
let
  rootArgs = removeAttrs args [ "lib" ];
  inherit (import ./.. (rootArgs // { wire = { deps, resolve }: deps; })) prelude;
  genBind = import ./.. rootArgs;
in
{ inherit lib prelude genBind; } // genBind

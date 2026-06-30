# gen-bind REPL — all exports in scope. Run: nix repl --impure --file ci/repl.nix
#
# gen-bind is built from gen-prelude (nixpkgs-lib-free); prelude is resolved from the
# ci flake.lock so the REPL needs no registry entry for gen-prelude. nixpkgs `lib` is
# still exposed for interactive convenience.
let
  nixpkgs = import (builtins.getFlake "nixpkgs") { };
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  node = lock.nodes.gen-prelude.locked;
  prelude = import "${
    builtins.fetchTree {
      inherit (node)
        type
        owner
        repo
        rev
        narHash
        ;
    }
  }/lib";
  genBind = import ../lib { inherit prelude; };
in
{
  inherit (nixpkgs) lib;
  inherit prelude genBind;
}
// genBind

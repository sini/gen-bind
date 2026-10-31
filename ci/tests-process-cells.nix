# THE PER-PROCESS CELLS (den-hoag-ien5k G6) — the hosted terminal's peer read: a class of n nodes, a
# reader with one declared peer handed through `peersOf`, and the adapter's `specialArgs.nodes` read
# deep. `tests-process.nix` reads the evaluator's thunk count.
#
# Verdict is a PROCESS EXIT read by `tests-process.nix` (one fixture per process). Sources arrive as
# ARGUMENTS rather than through `fetchTree`, and every dependency is rebuilt from its own `lib/` with
# explicit arguments, as gen-aspects' process cells are.
{
  arm,
  libSrc,
  genPreludeSrc,
  genAlgebraSrc,
  genGraphSrc,
  genIdentitySrc,
  genScopeSrc,
  # The class size, as a string (`--argstr`).
  n ? "0",
}:
let
  prelude = import "${genPreludeSrc}/lib";
  algebra = import "${genAlgebraSrc}/lib";
  graph = import "${genGraphSrc}/lib" { inherit prelude; };
  identity = import "${genIdentitySrc}/lib";
  engine = import "${genScopeSrc}/lib" {
    inherit
      algebra
      graph
      identity
      prelude
      ;
  };
  genBind = import libSrc { inherit prelude algebra; };

  size = builtins.fromJSON n;
  name = k: "n${toString k}";
  extent = builtins.listToAttrs (
    builtins.genList (k: {
      name = name k;
      value = {
        k = name k;
      };
    }) size
  );
  # The reader `n0` declares one peer, `n1` (itself at n = 1).
  peersOf = id: if id == name 0 then [ (name (if size > 1 then 1 else 0)) ] else [ ];
  terminal = genBind.crossing.mkHostedTerminal {
    evaluator = a: a.specialArgs.nodes;
    locateConfig = x: x;
    class = "host";
  };
  adapter = terminal.adapter {
    inherit extent peersOf engine;
    extraModules = [ ];
    marksOf = _: [ ];
    readerId = name 0;
  };

  cells = {
    # The reader's handed peer set; its value is the number of nodes handed.
    peers = builtins.length (builtins.attrNames (adapter.wrapUnit (adapter.bindFormals { } [ ]) [ ]));
    # The floor: the class itself, built and read, nothing handed.
    floor = builtins.length (builtins.attrNames extent);
  };
in
builtins.deepSeq cells.${arm} cells.${arm}

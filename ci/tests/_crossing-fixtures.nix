# Shared fixtures for the crossing suites. Underscore-prefixed so import-tree
# does NOT pick it up as a flake-parts module; the suites import it by path.
#
# ★ THE MINTING AUTHORITY IS INJECTED HERE, EXPLICITLY, AND IT IS A TEST
# FIXTURE. The published surface ships NO formula and NO bound operation —
# ADR-0016 gives the substrate one minting authority, and a formula shipped as a
# convenience default would be a second one that a consumer could reach simply by
# omitting the injection. `_testHashIdentity` exists to let the suite exercise the
# operations and for NOTHING ELSE; the name carries its status so it cannot be
# mistaken for the real mint or lifted into the library.
#
# `x` below is therefore the published surface WITH the suite's own injection
# applied. `genBind.crossing` — the raw published surface, carrying no
# operations — is what the non-leakage cells in crossing-operations.nix assert
# against, and the two must not be confused.
{ genBind }:
let
  published = genBind.crossing;

  _testHashIdentity =
    kind: labels: relatumOf:
    builtins.hashString "sha256" (
      kind
      + "@"
      + builtins.concatStringsSep "|" (
        builtins.map (l: l + "=" + relatumOf l) (builtins.sort (a: b: a < b) labels)
      )
    );

  ops = (published.mkOperations { hashIdentity = _testHashIdentity; }).value;

  x = published // ops;
in
rec {
  inherit
    x
    published
    ops
    _testHashIdentity
    ;
  t = x.term;

  imp = c: {
    merge = "one";
    contract = c;
    required = true;
    sealed = false;
    origin = "fixture";
    satisfiedBy = null;
  };

  sig = imports: {
    inherit imports;
    exports = { };
  };

  plainB =
    v:
    x.binding.plain {
      value = v;
      mark = x.mark.open;
    };

  termedB =
    term:
    x.binding.termed {
      inherit term;
      mark = x.mark.open;
    };

  wrappedB =
    p: body:
    x.binding.wrapped {
      producer = p;
      inherit body;
      mark = x.mark.open;
    };

  supply = bindings: {
    inherit bindings;
    proposals = { };
    origins = { };
  };

  reg = bindings: x.registerSupply (supply bindings);
  proj = bindings: (reg bindings).value.projection;
  heights = bindings: (reg bindings).value.heights;

  # A conforming Adapter offering every position, so a placement refusal in a
  # test is always about the row under test and never about this fixture.
  adapter = {
    bindFormals = vals: body: body // { bound = vals; };
    bindArgEnv = vals: { argEnv = vals; };
    wrapFn = f: { wrapFnOf = f; };
    wrapUnit = body: units: { inherit body units; };
    interpret = x.interpret;
  };

  codeOf = r: r.refusal.code;
  blameOf = r: r.refusal.blamed;

  resolve =
    term:
    x.resolveTerm {
      targets = { };
      siblings = { };
    } term;

  resolveIn = env: term: x.resolveTerm env term;

  # declare -> link -> close, for the cells that exercise the whole path.
  pipeline =
    {
      imports,
      bindings,
      target ? "igloo",
      members ? [ ],
      withAdapter ? adapter,
      body ? {
        kind = "body";
      },
    }:
    let
      p = proj bindings;
      f = x.declare (sig imports) body;
      l = x.link target p (supply bindings) f.value;
    in
    if x.isRefusal f then
      f
    else if x.isRefusal l then
      l
    else
      x.close target p { inherit members; } withAdapter l.value;
}

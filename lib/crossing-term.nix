# BodyTerm — gen-bind's INSTANCE of gen-algebra's first-order term algebra (`algebra.term`), the
# algebra this file used to define (den-hoag-lwbb1 unit 1: specs/2026-10-02-gen-algebra-term-extraction-spec.md).
# The formers, the `InertValue` walk, the primitive table, resolution and their refusal codes now live
# in gen-algebra `lib/term.nix`, extracted from here with their codes and witnesses unchanged. What
# stays here is what is gen-bind's own:
#
# - the INSTANCE: the formers a crossing body admits (`vocabulary`), the open world (`declared = null`,
#   so an absent sibling refuses as it always has), no module slots;
# - the CARRIER: the core answers in gen-algebra's `either` sum; gen-bind's surface answers in its own
#   `__crossingResult` sum with a `blamed` party (lib/crossing-refusal.nix), so every published entry
#   maps one to the other, and every term refusal blames the supplier, as before;
# - the ENVIRONMENT: `siblings` is gen-bind's name for the core's `context`, and an absent sibling's
#   `read-absent` is reported as `readctx-unresolvable-sibling`, its witness unchanged.
#
# NO MINTING AUTHORITY. The core takes the mint as a constructor parameter. gen-bind ships no minting
# formula (lib/crossing.nix, `mintIdentity`) and a crossing body enters no mint (the binding relatum is
# the binding's KEY), so this instance passes `null`: every term built here is REFUSED (ADR-0034) by
# name if an identity is ever demanded of it.
#
# Spec: specs/2026-08-18-gen-crossing-rederivation-spec.md §2.10 (the algebra), §2.10a-c, §2.11.
# Academic: Reynolds 1972 — defunctionalization.
{ prelude, algebra }:
let
  core = algebra.term null;
  inherit (import ./crossing-refusal.nix { inherit prelude; })
    ok
    refuse
    isRefusal
    party
    ;

  # The formers a crossing body admits: BodyTerm's nine, plus `Default`, `Ref` and `Not`, each with a
  # δ equation (lib/crossing-delta.nix). The condition atoms are guard vocabulary and stay out.
  vocabulary = [
    "Lit"
    "ReadFrom"
    "ReadCtx"
    "If"
    "Attrs"
    "List"
    "Concat"
    "PathJoin"
    "Apply"
    "Default"
    "Ref"
    "Not"
  ];
  instance = {
    inherit vocabulary;
    declared = null;
  };

  # core `either` -> crossing result. A core refusal is `{ left = { code; witness; }; }`.
  fromCore =
    r:
    if r ? left then
      refuse {
        code = if r.left.code == "read-absent" then "readctx-unresolvable-sibling" else r.left.code;
        blamed = party.supplier;
        witness =
          if r.left.code == "read-absent" then
            {
              inherit (r.left.witness) head;
              siblings = r.left.witness.available;
            }
          else
            r.left.witness;
      }
    else
      ok r.right;
  # A constructor's result is a term or a core refusal; only the refusal is mapped.
  fromCoreTerm = t: if core.isTerm t then t else fromCore t;
  # crossing refusal -> core refusal, so an operand refused at minting still propagates through the
  # core's formers (a refused `lit` cannot be lost by being nested).
  toCore = v: if isRefusal v then { left = { inherit (v.refusal) code witness; }; } else v;

  f1 = c: a: fromCoreTerm (c (toCore a));
  fN = c: xs: fromCoreTerm (c (map toCore xs));
in
{
  inherit (core)
    inertBudget
    isTerm
    prims
    children
    readCtxHeads
    ;
  knownFormers = vocabulary;

  checkInert =
    v:
    let
      r = core.checkInert v;
    in
    if r == null then null else fromCore r;
  checkTerm = t: if isRefusal t then t else fromCore (core.checkTerm instance t);
  resolveTerm =
    env: t:
    if isRefusal t then
      t
    else
      fromCore (
        core.resolveTerm {
          targets = env.targets;
          context = env.siblings;
        } t
      );

  term = {
    lit = v: fromCoreTerm (core.term.lit v);
    readFrom = target: path: fromCoreTerm (core.term.readFrom target path);
    readCtx = head: path: fromCoreTerm (core.term.readCtx head path);
    default = head: path: f1 (core.term.default head path);
    ref = id: fromCoreTerm (core.term.ref id);
    not = f1 core.term.not;
    attrs = m: fromCoreTerm (core.term.attrs (builtins.mapAttrs (_: toCore) m));
    list = fN core.term.list;
    concat = fN core.term.concat;
    pathJoin = head: segments: fromCoreTerm (core.term.pathJoin (toCore head) (map toCore segments));
    apply = prim: fN (core.term.apply prim);
    ifThenElse =
      cond: then_: else_:
      fromCoreTerm (core.term.ifThenElse (toCore cond) (toCore then_) (toCore else_));
  };
}

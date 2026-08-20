# The demand relation, DERIVED — the stratification, the structural recursion
# that computes it, and `deltaExact`, the residue bit the derived class is
# decided on.
#
# Spec: specs/2026-08-18-gen-crossing-rederivation-spec.md §2.3 (the relation is
# DERIVED and no declaration survives), §2.4a-i (the stratification is derived
# too — a declared `stratum` would be a constructible fact standing declared),
# §2.10a (the equations, and why each former is safe), §2.10a-i (the staging that
# makes a sibling cycle inexpressible), §2.11 (the refusal rows).
#
# ★ THE RECURSION RETURNS A PAIR, NOT A BARE SET. Measured in the spec: an
# APPROX chain and an EXACT chain of the same shape return IDENTICAL,
# INDISTINGUISHABLE sets, so a predicate over the set alone cannot decide the
# condition the derived class rests on. `exact` is a conjunction accumulated by
# the same traversal that produces the set — no second walk — and it sees through
# `If`, because the join conjoins all three arms and a residue-carrying arm
# therefore marks the whole term APPROX. That is the conservative direction.
#
# Academic: the height function of §2.4a-i is CANONICAL — it is not a choice of
# topological order, of which there are many and of which an adjacent library has
# measured two valid disagreeing ones. There is exactly one assignment satisfying
# the equation, and `max` over a set is order-free, so the assignment is
# invariant under the presentation order of the bindings.
{ prelude }:
let
  refusalLib = import ./crossing-refusal.nix { inherit prelude; };
  termLib = import ./crossing-term.nix { inherit prelude; };
  bindingLib = import ./crossing-binding.nix { inherit prelude; };

  inherit (refusalLib)
    ok
    refuse
    codes
    party
    ;

  exact = {
    exact = "EXACT";
    approx = "APPROX";
  };

  empty = {
    targets = [ ];
    exact = exact.exact;
  };

  approxEmpty = {
    targets = [ ];
    exact = exact.approx;
  };

  # (S1,e1) join (S2,e2) = (S1 union S2, e1 and e2)
  join = a: b: {
    targets = prelude.unique (a.targets ++ b.targets);
    exact = if a.exact == exact.exact && b.exact == exact.exact then exact.exact else exact.approx;
  };

  joinAll = xs: prelude.foldl' join empty xs;

  # ── the stratification (§2.4a-i) ─────────────────────────────────────────────
  # outEdges(b) is the set of `ReadCtx` HEAD NAMES occurring in b's term — empty
  # for Plain, Scoped and Wrapped, which carry no term.
  outEdges = b: if b.__binding == "Termed" then termLib.readCtxHeads b.term else [ ];

  # stratum(b) = 0                                       if outEdges(b) = {}
  #            = 1 + max { stratum(n) | n in outEdges(b) } otherwise
  #
  # THE DOMAIN, stated because `max` over a partial set otherwise has no value: a
  # head naming NO sibling contributes nothing to the max — it is not an absent
  # stratification. Such a binding stratifies at height 1, and the unresolved
  # name is caught at `link`. Registration decides STRATIFIABILITY; resolution
  # decides RESOLVABILITY, and conflating them reports a cycle that does not
  # exist.
  strata =
    bindings:
    let
      names = builtins.attrNames bindings;
      edges = prelude.genAttrs names (n: outEdges bindings.${n});
      resolvable = prelude.genAttrs names (n: builtins.filter (h: bindings ? ${h}) edges.${n});

      step =
        st:
        let
          settled = builtins.filter (
            n: !(st.heights ? ${n}) && builtins.all (h: st.heights ? ${h}) resolvable.${n}
          ) names;
          heightOf =
            n:
            if edges.${n} == [ ] then
              0
            else
              1 + prelude.foldl' (acc: h: prelude.max acc st.heights.${h}) 0 resolvable.${n};
        in
        {
          heights = st.heights // prelude.genAttrs settled heightOf;
        };

      # A bounded iteration: at most |bindings| rounds do work, and the step is
      # the identity once no work remains, so FAILURE TO REACH A FIXED POINT IS
      # THE REFUSAL. Non-termination does not arise.
      final = prelude.foldl' (st: _: step st) { heights = { }; } (
        prelude.range 1 (builtins.length names)
      );

      unstratified = builtins.filter (n: !(final.heights ? ${n})) names;
    in
    if unstratified != [ ] then
      refuse {
        code = codes.supplyUnstratifiable;
        blamed = party.supplier;
        # THE WITNESS IS THE SET OF BINDINGS WITH NO FINITE HEIGHT, a SUPERSET of
        # the cycle's members: it includes every binding that can REACH one. A
        # supplier handed a binding whose only fault is naming a broken one must
        # be able to tell that from lying on the cycle. Narrowing to the members
        # is one condensation pass over the same reference graph — available, and
        # deliberately not performed.
        witness = {
          withoutFiniteHeight = unstratified;
          references = prelude.genAttrs unstratified (n: resolvable.${n});
        };
      }
    else
      ok final.heights;

  # ── the recursion (§2.10a) ───────────────────────────────────────────────────
  # `sigma` maps a name to a BINDING, not to a term, which is why `ReadCtx` needs
  # an equation per constructor rather than an unconditional projection.
  deltaTerm =
    sigma: memo: t:
    let
      recurse = deltaTerm sigma memo;
    in
    if !(termLib.isTerm t) then
      empty
    else if t.__bodyTerm == "ReadFrom" then
      {
        targets = [ t.target ];
        exact = exact.exact;
      }
    else if t.__bodyTerm == "ReadCtx" then
      readCtxDelta sigma memo t.head
    else if t.__bodyTerm == "Lit" then
      empty
    else
      joinAll (builtins.map recurse (termLib.children t));

  # The two APPROX rows are why the derived class is narrower than "Termed": a
  # Scoped or Wrapped sibling's own demand set UNDER-APPROXIMATES, so a Termed
  # binding that reads one INHERITS that residue and its set is no more total
  # than the sibling's.
  #
  # ★★ THIS ANALYSIS DOES NOT RESPECT ACCESS MARKS, AND THAT IS THE POINT.
  # ADR-0026's mark is compiled into a QUERY's effective reachability — a query,
  # which is to say ACCESS. This recursion is not a query: it is the input a GATE
  # is trusted for, and ADR-0030 forbids a gate whose domain is narrower than the
  # property it is trusted for. An analysis blinded by an access mark is exactly
  # that narrowing, so the walk computes the TRUE demand set regardless of marks
  # and the marks keep bounding the access queries only (`crossings` and `E`, in
  # crossing-linkset.nix).
  #
  # An earlier revision cut the walk at a Floor-marked sibling and recorded the
  # cut as APPROX. That was FAIL-OPEN in the one direction that matters: a
  # Floor-marked binding demanding the consuming target reported an empty demand
  # set, and the congruence predicate then admitted a substrate placement the
  # value cannot support. The disposition is withdrawn.
  #
  # ★ SPEC AMENDMENT OWED. §2.6 item 3's traversal rule names δ explicitly —
  # "δ, `crossings` and `E` terminate at a Floor-marked node" — so this rules
  # against the spec's own sentence rather than filling a gap it left. The
  # sentence lumps an ANALYSIS in with two QUERIES; the amendment strikes δ from
  # it and leaves the queries. Recorded here so the two records do not disagree
  # silently.
  readCtxDelta =
    sigma: memo: head:
    if !(sigma ? ${head}) then
      # DANGLING. The same lenient disposition the stratification takes: a name
      # resolving to nothing contributes nothing. The unresolved name is caught
      # at `link` — which is AFTER this projection is materialized, so leaving
      # this case undefined would abort uncatchably before the row could fire.
      empty
    else
      let
        b = sigma.${head};
        p = bindingLib.producerOf b;
      in
      if p != null then
        {
          targets = [ p ];
          exact = exact.approx;
        }
      else if b.__binding == "Plain" then
        empty
      else
        memo.${head} or approxEmpty;

  deltaOf =
    sigma: memo: b:
    let
      p = bindingLib.producerOf b;
    in
    if p != null then
      {
        targets = [ p ];
        exact = exact.approx;
      }
    else if b.__binding == "Termed" then
      deltaTerm sigma memo b.term
    else
      empty;

  # ── the materialized projection (§2.10's `DeltaProjection`) ──────────────────
  # Keyed by BINDING, carrying the set AND the exactness bit, already computed.
  # It is not the edge relation and carries no query surface, which is the whole
  # of its purpose: both consumers of the relation take the projection, so
  # neither re-runs the query under its own reachability.
  #
  # The memo is sound precisely because the staging makes each binding's demand
  # set path-independent; the stratum order is topological by construction, so
  # each sibling is evaluated ONCE and the cost is linear in the sibling set
  # rather than in the number of paths through it.
  projectionFor =
    bindings: heights:
    let
      byHeight = builtins.sort (a: b: heights.${a} < heights.${b}) (builtins.attrNames bindings);
    in
    prelude.foldl' (memo: n: memo // { ${n} = deltaOf bindings memo bindings.${n}; }) { } byHeight;

  # ── registration ─────────────────────────────────────────────────────────────
  # TAKEN-DEFAULT (operation). §2.11 assigns two rows to a `registration` stage —
  # the unapplicable `Wrapped` body and the unstratifiable supply — but §2.10's
  # operation list names no registration operation. This is that operation: it is
  # where the supply's bindings are checked, where the stratification is computed
  # and refused, and where the projection both later consumers take is minted.
  registerSupply =
    supply:
    let
      missing = builtins.filter (f: !(supply ? ${f})) [
        "bindings"
        "proposals"
        "origins"
      ];
      names = builtins.attrNames (supply.bindings or { });
      checks = builtins.map (n: bindingLib.checkBinding supply.bindings.${n}) names;
      badBinding = refusalLib.firstRefusal checks;
      termChecks = builtins.map (n: termLib.checkTerm supply.bindings.${n}.term) (
        builtins.filter (n: supply.bindings.${n}.__binding == "Termed") names
      );
      badTerm = refusalLib.firstRefusal termChecks;
    in
    if missing != [ ] then
      refuse {
        code = codes.declarationMissingField;
        blamed = party.supplier;
        witness = {
          object = "Supply";
          fields = missing;
        };
      }
    else if badBinding != null then
      badBinding
    else if badTerm != null then
      badTerm
    else
      refusalLib.andThen (strata supply.bindings) (
        heights:
        ok {
          inherit supply heights;
          projection = projectionFor supply.bindings heights;
        }
      );

  # `deltaExact(c)` — the Exact half of the projection entry for a binding. This
  # is the carrier the derived-class condition is decided on; "decidable in
  # principle" was never the gap, a bare set was.
  deltaExact = projection: name: (projection.${name} or approxEmpty).exact;

  isExact = projection: name: deltaExact projection name == exact.exact;

  demands = projection: name: (projection.${name} or approxEmpty).targets;
in
{
  inherit
    exact
    join
    joinAll
    outEdges
    strata
    projectionFor
    registerSupply
    deltaExact
    isExact
    demands
    ;
}

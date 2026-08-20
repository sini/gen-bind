# Linkset — the fleet as a named materialized view, and the cross-unit
# environment its coherence condition is stated over.
#
# Spec: specs/2026-08-18-gen-crossing-rederivation-spec.md §2.6 (the queries and
# the discipline on consuming them), §2.8 (the linkset), §2.11 (the close row).
#
#   E(u)      = union { delta(binding(c)) | c a crossing of unit u }  minus  {u}
#   coherent  = E(u) subset-of members
#   linked(u) = E(u) is empty
#
# ★ E(u) IS A SET OF TARGET IDENTITIES AND IT TAKES NO `dom`. Cardelli's
# Definition 5-2 writes `dom(Ei) ⊆ exp(L)` because his `Ei` IS an environment of
# `x:A` bindings; transplanting the operator onto a set of identities would be a
# borrowed notation carried onto an object where it has no meaning. What
# transfers from Cardelli is the CONTAINMENT CONDITION, not the operator.
#
# `linked(u)` is the predicate that licenses evaluating and shipping a unit
# alone, and — contracts now being first-order data with a structural identity —
# it licenses caching too.
#
# Cardelli 1997 supplies the linkset structure and the two disjointness clauses
# that stay imposed (`imp(L) ∩ exp(L) = {}` at Definition 5-2, and
# `exp(L) ∩ exp(L') = {}` at Definition 5-7's precondition); both are enforced by
# the declare/merge rows in crossing.nix. His Theorem 7-6 is NOT cited as a
# licence: its hypotheses are F1 typing derivations this setting cannot supply.
#
# THE COARSENING IS DELIBERATE AND SAFE. E(u) unions over a UNIT because a
# linkset is a statement about units; it can cost staticity, never admit an
# inadmissible substrate placement. Every finer construct — the demand edge, the
# crossing's relata, the congruence predicate — stays per BINDING.
{ prelude }:
let
  refusalLib = import ./crossing-refusal.nix { inherit prelude; };
  deltaLib = import ./crossing-delta.nix { inherit prelude; };
  bindingLib = import ./crossing-binding.nix { inherit prelude; };
  inherit (refusalLib)
    ok
    refuse
    codes
    party
    ;

  mkLinkset =
    l:
    if !(builtins.isAttrs l) || !(l ? members) then
      refuse {
        code = codes.declarationMissingField;
        blamed = party.declarer;
        witness = {
          object = "Linkset";
          field = "members";
        };
      }
    else if !(builtins.isList l.members) || !(builtins.all builtins.isString l.members) then
      refuse {
        code = codes.declarationMissingField;
        blamed = party.declarer;
        witness = {
          object = "Linkset";
          field = "members";
          expected = "list of TargetId";
        };
      }
    else
      ok { members = prelude.unique l.members; };

  # E(u), over the crossings of one unit. `crossings` is the crossing NODE list;
  # each node names its binding as a relatum, and the demand set is read from the
  # MATERIALIZED projection, never re-queried from the relation — one discipline,
  # both consumers, because giving it to one and not the other leaves the failure
  # exactly where it was.
  #
  # ★ THIS IS WHERE ADR-0026'S MARK BINDS. `crossings` and `E` are QUERIES —
  # access — so they terminate at a `Floor`-marked node and never traverse past
  # it. The demand ANALYSIS does not (crossing-delta.nix states why): an analysis
  # a gate is trusted for may not have its domain narrowed by an access mark.
  # That split is what keeps the mark a declaration binding something at use
  # while leaving the congruence predicate total.
  #
  # TAKEN-DEFAULT #19 (the mark's consumer). Striking the analysis from
  # ADR-0026's traversal rule left `mark` with no consumer at all — a declaration
  # binding nothing at use, which premise R§2.10 forbids — so the consumer moved
  # HERE, to the two constructs that are queries. The relocation is this
  # implementation's reading, not the spec's words.
  #
  # ★ THE COST, WITH THE DIRECTION WORD STATED CORRECTLY. A Floor-marked
  # binding's cross-unit references do not enter E(u), so the coherence refusal
  # cannot see them and `linked(u)` can be wrongly TRUE for that unit — measured.
  # **On the decisions E feeds, that narrowing is PERMISSIVE, not fail-closed.**
  # An earlier revision of this comment called it fail-closed, which described the
  # declaration (the author opting a node out) and not its effect; the two point
  # opposite ways and the effect is what a reader needs.
  #
  # It is BOUNDED by two facts, both measured:
  #
  #   (a) IT IS NOT TRANSITIVE. The mark stops the query at the node that carries
  #       it, and nowhere else — so an OPEN reader of a Floor-marked sibling puts
  #       the demanded target straight back into E(u). The leak is in the
  #       CONSERVATIVE direction: one unmarked reader anywhere on the chain
  #       restores the reference.
  #   (b) THE UNIT STILL REFUSES — all three constructors, measured, by two
  #       routes. The mechanism sentence here is Termed's: the placement decision
  #       reads the analysis, which is mark-blind, so a Floor-marked Termed
  #       binding demanding a peer is still Substrate-placed and refuses
  #       `value-not-obtainable` at close. Scoped and Wrapped never reach
  #       Substrate placement at all — the exactness belt refuses them one step
  #       earlier (`substrate-placement-inexact-demand`). Either way a unit that
  #       is `linked` wrongly true CANNOT silently cross carrying an unresolvable
  #       reference; it fails, by name.
  #
  # (a) is armed at crossing-linkset.test-floor-narrowing-is-not-transitive;
  # (b) at crossing-operations.test-a-linked-wrongly-true-unit-still-refuses-at-close,
  # which needs the whole pipeline and so lives with the other close cells.
  traversable = c: (c.record.mark or bindingLib.mark.open) != bindingLib.mark.floor;

  environment =
    {
      unit,
      crossings,
      projection,
    }:
    let
      demanded = builtins.concatMap (c: deltaLib.demands projection c.binding) (
        builtins.filter traversable crossings
      );
    in
    builtins.filter (t: t != unit) (prelude.unique demanded);

  linked = args: environment args == [ ];

  coherence =
    {
      unit,
      crossings,
      projection,
      linkset,
    }:
    let
      e = environment { inherit unit crossings projection; };
      offending = builtins.filter (t: !(prelude.elem t linkset.members)) e;
    in
    if offending == [ ] then
      ok e
    else
      refuse {
        code = codes.linksetIncoherent;
        blamed = party.declarer;
        witness = {
          inherit offending;
          environment = e;
          inherit (linkset) members;
        };
      };
in
{
  inherit
    mkLinkset
    environment
    linked
    coherence
    ;
}

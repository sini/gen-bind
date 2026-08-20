# Adapter — the target-shaped half of the crossing, and PLACEMENT, the derived
# fact it resolves.
#
# Spec: specs/2026-08-18-gen-crossing-rederivation-spec.md §2.5 (placement is
# derived, in two steps at two operations), §2.10 (the `Adapter` record and the
# opaque target-owned types), §2.11 (the two adapter rows).
#
# Every value the Adapter produces or consumes — Body, TargetUnit, TargetArgs,
# ProducerScope — is TARGET-OWNED AND DELIBERATELY OPAQUE. Naming their structure
# would breach target-agnosticism, so this file never reads one: `wrapUnit`'s
# result is returned by `close` exactly as the adapter built it.
#
#   bindFormals :: Maybe (AttrsOf Value -> Body -> Body)
#   bindArgEnv  :: Maybe (AttrsOf Value -> TargetUnit)
#   wrapFn      :: Maybe ((TargetArgs -> Body) -> Body)
#   wrapUnit    :: Body -> [TargetUnit] -> TargetUnit
#   interpret   :: ContractTerm -> Value -> Either Violation Value
#
# `Maybe` is realized as `null` for Nothing, and it is what the placement table
# reads. The three `Maybe` fields are TOTAL: a missing key is malformed, not
# permissive, so `null` is how "this adapter does not offer that position" is
# said VISIBLY.
#
# ★ PLACEMENT IS RESOLVED, NEVER STORED, AND THAT IS WHY THE ADAPTER IS NOT A
# RELATUM. A crossing's identity is over its import, its binding and its target;
# the adapter is not among them. Two adapters over one crossing therefore yield
# ONE crossing node and TWO placements, which is correct — placement is an output
# of `close`, not a fact about the relation — and it is consistent with
# content-independence, under which identity does not vary with what a later pass
# computes about the node.
{ prelude }:
let
  refusalLib = import ./crossing-refusal.nix { inherit prelude; };
  inherit (refusalLib)
    ok
    refuse
    codes
    party
    ;

  channel = {
    formals = "Formals";
    argEnv = "ArgEnv";
  };

  time = {
    substrate = "Substrate";
    targetInvoked = "TargetInvoked";
  };

  fields = [
    "bindFormals"
    "bindArgEnv"
    "wrapFn"
    "wrapUnit"
    "interpret"
  ];

  # TAKEN-DEFAULT (code). §2.11 carries no row for a malformed Adapter; the
  # alternative to this row is Nix's own "called with unexpected argument", which
  # `tryEval` cannot catch — and refusal staying IN THE TYPE is exactly why the
  # surface returns tagged values rather than throwing.
  mkAdapter =
    a:
    let
      missing = builtins.filter (f: !(a ? ${f})) fields;
      notFunction = builtins.filter (f: a.${f} != null && !(builtins.isFunction a.${f})) fields;
    in
    if missing != [ ] then
      refuse {
        code = codes.adapterMalformed;
        blamed = party.adapterSelector;
        witness = {
          object = "Adapter";
          inherit missing;
        };
      }
    else if a.wrapUnit == null || a.interpret == null then
      refuse {
        code = codes.adapterMalformed;
        blamed = party.adapterSelector;
        witness = {
          object = "Adapter";
          reason = "wrapUnit and interpret are not optional";
        };
      }
    else if notFunction != [ ] then
      refuse {
        code = codes.adapterMalformed;
        blamed = party.adapterSelector;
        witness = {
          object = "Adapter";
          notFunction = notFunction;
        };
      }
    else
      ok (
        builtins.listToAttrs (
          builtins.map (f: {
            name = f;
            value = a.${f};
          }) fields
        )
      );

  offers = adapter: f: (adapter.${f} or null) != null;

  # ── STEP 2 of §2.5: placement, at `close`, the only operation holding an
  #    Adapter. Resolved TOTALLY over the six rows.
  #
  #  staticityAdmissible | deltaExact | adapter offers        | placement
  #  --------------------+------------+-----------------------+---------------------
  #  true                | EXACT      | bindFormals           | (Formals, Substrate)
  #  true                | EXACT      | no bindFormals        | REFUSE
  #  true                | APPROX     | (not reached)         | REFUSE
  #  false               | any        | wrapFn                | (Formals, TargetInvoked)
  #  false               | any        | no wrapFn, bindArgEnv | (ArgEnv,  TargetInvoked)
  #  false               | any        | neither               | REFUSE
  #
  # TAKEN-DEFAULT #20 (refuse, not demote). The exactness REQUIREMENT is forced;
  # what is a taken default is the DISPOSITION. Demoting an inexact name to
  # TargetInvoked would also be sound — the value would resolve inside the
  # target's own fixpoint — and would keep a population this refuses: a `Scoped`
  # or `Wrapped` binding whose producer is a PEER no longer crosses at all.
  # Refusal is taken because a silent demotion reports nothing, and a fleet would
  # never learn which of its bindings had left the derived class.
  #
  # ★★ SUBSTRATE ADMISSION REQUIRES EXACTNESS, AND THAT IS SOUNDNESS RATHER THAN
  # PRECISION. The congruence predicate is `target NOT IN demands` over the
  # materialized set, and ADR-0013's own row says an APPROX set
  # UNDER-APPROXIMATES — the true set may be LARGER and may contain the very
  # target. A negative membership test over an APPROX set can therefore be
  # wrongly TRUE, and admitting a substrate placement on it substitutes a value
  # before the fixpoint that determines it has run.
  #
  # The two facts stay DISTINCT on the crossing node — `staticityAdmissible` is
  # still §2.5 step 1's congruence fact and nothing else — because collapsing
  # "proved safe" into "could not prove" loses the witness.
  #
  # It REFUSES rather than demoting, so the failure names the ANALYSIS limit that
  # caused it and the supplier can act on it: make the binding `Termed` with a
  # closure reaching no `Scoped` or `Wrapped` sibling. Demoting silently to
  # TargetInvoked would also be sound, but it would report nothing and a fleet
  # would never learn which of its bindings had left the derived class.
  #
  # It must not silently downgrade an ADMISSIBLE Substrate name either: that is a
  # congruence violation, not a degradation.
  #
  # ★ This is a per-binding CLASSIFICATION READ of one recorded attribute. There
  # is no traversal here and it must not become cycle detection.
  placement =
    {
      staticityAdmissible,
      deltaExact,
      adapter,
      name,
    }:
    if staticityAdmissible then
      if deltaExact != "EXACT" then
        refuse {
          code = codes.substrateDemandInexact;
          blamed = party.supplier;
          witness = {
            inherit name deltaExact;
            reason = "the congruence predicate passed over a demand set that under-approximates";
          };
        }
      else if offers adapter "bindFormals" then
        ok {
          channel = channel.formals;
          time = time.substrate;
        }
      else
        refuse {
          code = codes.adapterMissingBindFormals;
          blamed = party.adapterSelector;
          witness = {
            inherit name;
            offered = builtins.filter (offers adapter) fields;
          };
        }
    else if offers adapter "wrapFn" then
      ok {
        channel = channel.formals;
        time = time.targetInvoked;
      }
    else if offers adapter "bindArgEnv" then
      ok {
        channel = channel.argEnv;
        time = time.targetInvoked;
      }
    else
      refuse {
        code = codes.adapterMissingTargetInvoked;
        blamed = party.adapterSelector;
        witness = {
          inherit name;
          offered = builtins.filter (offers adapter) fields;
        };
      };
in
{
  inherit
    channel
    time
    fields
    mkAdapter
    offers
    placement
    ;
}

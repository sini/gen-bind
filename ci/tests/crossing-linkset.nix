# The fleet linkset as a named materialized view — spec §2.6, §2.8, §2.11's
# close row.
#
# E(u) is a SET OF TARGET IDENTITIES and it takes no `dom`: what transfers from
# Cardelli is the CONTAINMENT CONDITION, not the operator, because his
# environment is one of `x:A` bindings and this is not.
{ genBind, ... }:
let
  f = import ./_crossing-fixtures.nix { inherit genBind; };
  inherit (f)
    x
    t
    proj
    plainB
    termedB
    wrappedB
    codeOf
    ;

  bindings = {
    quiet = plainB 1;
    fromIceberg = termedB (t.readFrom "iceberg" [ "x" ]);
    fromSelf = termedB (t.readFrom "igloo" [ "y" ]);
    opaque = wrappedB "glacier" (_: 1);
  };

  projection = proj bindings;

  node = n: {
    binding = n;
    import = n;
    target = "igloo";
    record = bindings.${n};
  };

  # The same node with the binding re-marked, so the mark is the ONLY thing that
  # differs between the two arms below.
  markedNode =
    m: n:
    (node n)
    // {
      record = bindings.${n} // {
        mark = m;
      };
    };

  env =
    names:
    x.environment {
      unit = "igloo";
      crossings = builtins.map node names;
      inherit projection;
    };
in
{
  # ── ★ THIS IS WHERE ADR-0026'S MARK BINDS. `crossings` and `E` are QUERIES —
  #    access — so they terminate at a Floor-marked node and never traverse past
  #    it. The demand ANALYSIS does not; it is a gate input, and a gate blinded by
  #    an access mark is a domain narrower than the property it is trusted for.
  #    Splitting them is what keeps the mark a declaration that binds something at
  #    use while leaving the congruence predicate total.
  flake.tests.crossing-linkset.test-floor-marked-node-terminates-the-environment-query = {
    expr = x.environment {
      unit = "igloo";
      crossings = [ (markedNode x.mark.floor "fromIceberg") ];
      inherit projection;
    };
    expected = [ ];
  };

  flake.tests.crossing-linkset.test-control-open-marked-node-enters-the-environment-query = {
    expr = x.environment {
      unit = "igloo";
      crossings = [ (markedNode x.mark.open "fromIceberg") ];
      inherit projection;
    };
    expected = [ "iceberg" ];
  };

  # ...and the SAME binding's demand set is untouched by the mark, in the same
  # run. That pair is the whole content of the split: the query narrows, the
  # analysis does not.
  flake.tests.crossing-linkset.test-the-mark-narrows-the-query-never-the-analysis = {
    expr = {
      queried = x.environment {
        unit = "igloo";
        crossings = [ (markedNode x.mark.floor "fromIceberg") ];
        inherit projection;
      };
      analysed = x.demands projection "fromIceberg";
    };
    expected = {
      queried = [ ];
      analysed = [ "iceberg" ];
    };
  };

  # ── ★ THE NARROWING IS PERMISSIVE ON WHAT E FEEDS, AND IT IS BOUNDED TWICE.
  #    `linked(u)` can be wrongly TRUE and the coherence refusal goes blind, so
  #    calling this "fail-closed" would describe the DECLARATION and not its
  #    EFFECT — the two point opposite ways.
  #
  #    BOUND (a): THE MARK IS NOT TRANSITIVE. It stops the query at the node
  #    carrying it and nowhere else, so an OPEN reader of a Floor-marked sibling
  #    puts the demanded target straight back into E(u). One unmarked reader
  #    anywhere on the chain restores the reference, which is the conservative
  #    direction to leak in.
  flake.tests.crossing-linkset.test-floor-narrowing-is-not-transitive = {
    expr =
      let
        chainBindings = {
          hidden = x.binding.termed {
            term = t.readFrom "iceberg" [ "x" ];
            mark = x.mark.floor;
          };
          reader = termedB (t.readCtx "hidden" [ ]);
        };
        chainProjection = proj chainBindings;
        crossingOn = n: {
          binding = n;
          import = n;
          target = "igloo";
          record = chainBindings.${n};
        };
      in
      {
        floorMarkedNodeAlone = x.environment {
          unit = "igloo";
          crossings = [ (crossingOn "hidden") ];
          projection = chainProjection;
        };
        openReaderOfIt = x.environment {
          unit = "igloo";
          crossings = [ (crossingOn "reader") ];
          projection = chainProjection;
        };
      };
    expected = {
      floorMarkedNodeAlone = [ ];
      openReaderOfIt = [ "iceberg" ];
    };
  };

  flake.tests.crossing-linkset.test-environment-unions-the-units-crossings = {
    expr = env [
      "fromIceberg"
      "opaque"
    ];
    expected = [
      "iceberg"
      "glacier"
    ];
  };

  # ...MINUS the unit itself: a unit demanding its own fixpoint is not a
  # cross-unit reference.
  flake.tests.crossing-linkset.test-environment-subtracts-the-unit-itself = {
    expr = env [ "fromSelf" ];
    expected = [ ];
  };

  flake.tests.crossing-linkset.test-environment-of-a-quiet-binding-is-empty = {
    expr = env [ "quiet" ];
    expected = [ ];
  };

  # `linked(u)` licenses evaluating and shipping a unit ALONE — and, contracts
  # now being first-order data with a structural identity, caching it too.
  flake.tests.crossing-linkset.test-linked-is-true-when-the-environment-is-empty = {
    expr = x.linked {
      unit = "igloo";
      crossings = [ (node "quiet") ];
      inherit projection;
    };
    expected = true;
  };

  flake.tests.crossing-linkset.test-control-linked-is-false-with-a-cross-unit-reference = {
    expr = x.linked {
      unit = "igloo";
      crossings = [ (node "fromIceberg") ];
      inherit projection;
    };
    expected = false;
  };

  # ── coherence: every cross-unit reference names a unit the fleet CONTAINS.
  flake.tests.crossing-linkset.test-coherence-refuses-a-non-member = {
    expr = codeOf (
      x.coherence {
        unit = "igloo";
        crossings = [ (node "fromIceberg") ];
        inherit projection;
        linkset.members = [ "igloo" ];
      }
    );
    expected = "linkset-incoherent";
  };

  flake.tests.crossing-linkset.test-coherence-witness-names-the-offender = {
    expr =
      (x.coherence {
        unit = "igloo";
        crossings = [
          (node "fromIceberg")
          (node "opaque")
        ];
        inherit projection;
        linkset.members = [
          "igloo"
          "iceberg"
        ];
      }).refusal.witness.offending;
    expected = [ "glacier" ];
  };

  flake.tests.crossing-linkset.test-control-coherence-admits-a-complete-fleet = {
    expr =
      (x.coherence {
        unit = "igloo";
        crossings = [
          (node "fromIceberg")
          (node "opaque")
        ];
        inherit projection;
        linkset.members = [
          "igloo"
          "iceberg"
          "glacier"
        ];
      }).value;
    expected = [
      "iceberg"
      "glacier"
    ];
  };

  # ── the linkset is TOTAL over its one field.
  flake.tests.crossing-linkset.test-linkset-missing-members-refuses = {
    expr = codeOf (x.mkLinkset { });
    expected = "declaration-missing-field";
  };

  flake.tests.crossing-linkset.test-linkset-non-list-members-refuses = {
    expr = codeOf (x.mkLinkset { members = "igloo"; });
    expected = "declaration-missing-field";
  };

  flake.tests.crossing-linkset.test-control-linkset-admits-a-member-list = {
    expr =
      (x.mkLinkset {
        members = [
          "igloo"
          "iceberg"
          "igloo"
        ];
      }).value.members;
    expected = [
      "igloo"
      "iceberg"
    ];
  };

  # THE COARSENING IS DELIBERATE AND SAFE: E(u) unions over a UNIT because a
  # linkset is a statement about units. It can cost staticity, never admit an
  # inadmissible substrate placement — the finer constructs stay per binding.
  flake.tests.crossing-linkset.test-environment-coarsens-over-the-unit-only = {
    expr =
      let
        unioned = env [
          "quiet"
          "fromIceberg"
        ];
        perBinding = {
          quiet = x.demands projection "quiet";
          fromIceberg = x.demands projection "fromIceberg";
        };
      in
      {
        inherit unioned;
        quietStaysEmpty = perBinding.quiet == [ ];
      };
    expected = {
      unioned = [ "iceberg" ];
      quietStaysEmpty = true;
    };
  };
}

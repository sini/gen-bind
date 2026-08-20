# The three populations, measured — spec §3.1 (the derivation reproduces the
# shipped assignment and is strictly more precise than it) and §3.3 (the demand
# set's totality, per population, and the one population where there is no
# oracle).
#
# ★ P-C HAS NO ORACLE, AND THE RESIDUE IS ARMED BY A POSITIVE CONTROL INSTEAD. A
# lexically captured value is read through no substrate accessor, so a dynamic
# read recorder observes nothing and reads CLEAN — that is predicate-blindness,
# not evidence. What makes the admission non-vacuous is a control showing the
# channel is LIVE, and that pair is below.
{ genBind, ... }:
let
  f = import ./_crossing-fixtures.nix { inherit genBind; };
  inherit (f)
    x
    t
    proj
    termedB
    ;

  scopedBody = ./_crossing-scoped-body.nix;

  # A substrate-built, substrate-applied wrapper: exactly the shape that bounds
  # the ARGUMENT channel and nothing lexical.
  substrateWrapper = body: scope: body scope;
  peerValue = "CAPTURED";
in
{
  # ── P-B, arm 1: a body loaded with a substrate-supplied scope reads the
  #    SUBSTRATE's binding for a name.
  flake.tests.crossing-populations.test-scoped-body-reads-the-supplied-scope = {
    expr = (builtins.scopedImport { supplied = "FROM-SCOPE"; } scopedBody).value;
    expected = "FROM-SCOPE";
  };

  # ── P-B, arm 2 AS ORIGINALLY CUT IS WITHDRAWN, and the withdrawal is recorded
  #    rather than the cell quietly deleted. It evaluated the same expression as
  #    arm 1 under an enclosing `let supplied = "FROM-CALLER"` and asserted
  #    "FROM-SCOPE". ★ UNDER NIX SEMANTICS THAT `let` CANNOT REACH AN IMPORTED
  #    FILE AT ALL, so the cell could not have failed for the reason it claimed to
  #    test: it was arm 1 wearing a second name, and an assertion whose only
  #    distinguishing input cannot change the result measures nothing.
  #
  #    What DOES discriminate is which value the supplied scope decides, so that
  #    is the cell below: two different scopes over ONE file yield two different
  #    values. That is `scopedImport`'s real contribution — the substrate DECIDES
  #    what the body may name — as distinct from the closure property, which
  #    comes from file import and which only arm 3 would measure, were arm 3
  #    expressible.
  flake.tests.crossing-populations.test-the-supplied-scope-decides-what-the-body-names = {
    expr = {
      first = (builtins.scopedImport { supplied = "FIRST"; } scopedBody).value;
      second = (builtins.scopedImport { supplied = "SECOND"; } scopedBody).value;
    };
    expected = {
      first = "FIRST";
      second = "SECOND";
    };
  };

  # ── P-B, STATED LIMIT: the `import` channel is measured OPEN. Under a scope
  #    that omits them the base scope still resolves `builtins`, so this oracle
  #    establishes caller-lexical closure and nothing wider — which is why the
  #    population's demand set is complete on the caller-lexical channel only.
  flake.tests.crossing-populations.test-scoped-body-still-reaches-the-base-scope = {
    expr = (builtins.scopedImport { supplied = "x"; } scopedBody).viaBaseScope;
    expected = 2;
  };

  # ── P-B, arm 3 is NOT EXPRESSIBLE AS A CELL, and the reason is measured here
  #    rather than asserted. A plain `import` of the same file under the same
  #    caller binding fails on the FREE VARIABLE rather than capturing — which is
  #    what shows the closure comes from FILE IMPORT and not from the supplied
  #    scope — but an undefined-variable error is UNCATCHABLE: `tryEval` does not
  #    convert it, so a cell attempting it aborts the whole suite instead of
  #    returning false. The live control for that claim is the next cell: a
  #    `throw` IS caught by the same instrument in the same run, so "uncatchable"
  #    is a property of the error class and not of a broken probe.
  flake.tests.crossing-populations.test-control-tryEval-catches-a-throw-in-the-same-run = {
    expr = (builtins.tryEval (throw "boom")).success;
    expected = false;
  };

  # ── P-C: the capture control. The channel is LIVE — a substrate-built,
  #    substrate-applied wrapper over a body that closes over a peer value
  #    returns the CAPTURED result, not the passed one.
  flake.tests.crossing-populations.test-wrapped-lexical-capture-is-live = {
    expr = substrateWrapper (_: peerValue) { v = "PASSED"; };
    expected = "CAPTURED";
  };

  # ── the no-capture arm, in the same run. Without this pair the unguarded row
  #    would be an ASSERTION that the seam exists rather than a MEASUREMENT that
  #    it does.
  flake.tests.crossing-populations.test-control-wrapped-without-capture-returns-the-passed-value = {
    expr = substrateWrapper (scope: scope.v) { v = "PASSED"; };
    expected = "PASSED";
  };

  # Substrate-controlled application bounds the ARGUMENT channel and bounds
  # nothing lexical: the same wrapper, the same application, two different
  # answers according to what the body closes over.
  flake.tests.crossing-populations.test-application-bounds-only-the-argument-channel = {
    expr =
      let
        captured = substrateWrapper (_: peerValue) { v = "PASSED"; };
        passed = substrateWrapper (scope: scope.v) { v = "PASSED"; };
      in
      captured != passed;
    expected = true;
  };

  # ── §3.1's SECOND ARM — the PRECISION claim, a positive result rather than a
  #    parity check. The shipped classifier decides whether to defer by testing
  #    the body's DECLARED FORMALS; the term-based derivation reads the TERM. On
  #    a body that declares a `config` formal and NEVER READS IT, the shipped
  #    test defers and the derived demand set is EMPTY — the binding needs no
  #    deferral at all.
  flake.tests.crossing-populations.test-declared-formal-defers-but-the-term-demands-nothing = {
    expr = {
      shippedWouldDefer = builtins.functionArgs ({ config }: 42) ? config;
      derivedDemands = (proj { quiet = termedB (t.lit 42); }).quiet.targets;
    };
    expected = {
      shippedWouldDefer = true;
      derivedDemands = [ ];
    };
  };

  # Control: a body that DOES read the fixpoint must yield a non-empty demand set
  # in the same run, or the empty one has not been distinguished from a term
  # walker that finds nothing anywhere.
  flake.tests.crossing-populations.test-control-a-genuine-read-yields-a-non-empty-demand-set = {
    expr =
      (proj {
        reader = termedB (
          t.readFrom "iceberg" [
            "networking"
            "hostName"
          ]
        );
      }).reader.targets;
    expected = [ "iceberg" ];
  };

  # ── §3.1's FIRST ARM — the placement rule reproduces the shipped assignment:
  #    a binding demanding `iceberg` is Substrate-admissible AT THE CONSUMER and
  #    inadmissible AT THE PRODUCER, which are exactly the two branches the
  #    shipped code takes. The control is the second row: a run in which both
  #    arms agree has not tested the derivation.
  flake.tests.crossing-populations.test-congruence-admits-at-consumer-refuses-at-producer = {
    expr =
      let
        p = proj { fromIceberg = termedB (t.readFrom "iceberg" [ "x" ]); };
        admissibleAt = target: !(builtins.elem target (x.demands p "fromIceberg"));
      in
      {
        atConsumer = admissibleAt "igloo";
        atProducer = admissibleAt "iceberg";
      };
    expected = {
      atConsumer = true;
      atProducer = false;
    };
  };

  # The precision is PER BINDING all the way from the edge to the crossing node,
  # so a plain binding is never demoted by a sibling that carries a producer —
  # which is the whole reason the BINDING and not the supply is the relatum.
  flake.tests.crossing-populations.test-a-plain-binding-is-not-demoted-by-its-sibling = {
    expr =
      let
        p = proj {
          quiet = termedB (t.lit 1);
          noisy = termedB (t.readFrom "igloo" [ "x" ]);
        };
      in
      {
        quiet = builtins.elem "igloo" (x.demands p "quiet");
        noisy = builtins.elem "igloo" (x.demands p "noisy");
      };
    expected = {
      quiet = false;
      noisy = true;
    };
  };
}

# Adapter and PLACEMENT — the derived fact of spec §2.5 step 2, resolved at
# `close`, the only operation holding an Adapter.
#
# Oracle: the five rows of the placement table, each with its conforming
# control, plus §2.11's two adapter rows. ★ Placement MUST NOT silently downgrade
# a Substrate name to TargetInvoked: that is a congruence violation, not a
# degradation, so the "true + no bindFormals" row REFUSES rather than falling
# through to the target-invoked rows below it.
{ genBind, ... }:
let
  f = import ./_crossing-fixtures.nix { inherit genBind; };
  inherit (f)
    x
    adapter
    codeOf
    blameOf
    ;

  without = names: builtins.mapAttrs (n: v: if builtins.elem n names then null else v) adapter;

  place =
    a: admissible:
    x.placement {
      staticityAdmissible = admissible;
      deltaExact = "EXACT";
      adapter = a;
      name = "db";
    };

  placeInexact =
    a: admissible:
    x.placement {
      staticityAdmissible = admissible;
      deltaExact = "APPROX";
      adapter = a;
      name = "db";
    };
in
{
  # ── ★ SUBSTRATE ADMISSION REQUIRES EXACTNESS. The congruence predicate is a
  #    NEGATIVE membership test, and an APPROX set UNDER-APPROXIMATES — the true
  #    set may be LARGER and may contain the very target — so the predicate can be
  #    wrongly TRUE, and the placement would then substitute a value before the
  #    fixpoint that determines it has run. Soundness, not precision.
  flake.tests.crossing-adapter.test-approx-demand-refuses-substrate-placement = {
    expr = codeOf (placeInexact adapter true);
    expected = "substrate-placement-inexact-demand";
  };

  flake.tests.crossing-adapter.test-approx-refusal-blames-the-supplier-and-names-the-bit = {
    expr = {
      blamed = blameOf (placeInexact adapter true);
      inherit ((placeInexact adapter true).refusal.witness) deltaExact name;
    };
    expected = {
      blamed = "supplier";
      deltaExact = "APPROX";
      name = "db";
    };
  };

  # The control that makes the row mean anything: the SAME adapter and the SAME
  # congruence verdict, exact this time, IS admitted at Substrate.
  flake.tests.crossing-adapter.test-control-exact-demand-admits-substrate-placement = {
    expr = (place adapter true).value;
    expected = {
      channel = "Formals";
      time = "Substrate";
    };
  };

  # Exactness gates the SUBSTRATE row only. An inadmissible name still routes to
  # the target-invoked channel whatever its exactness — the residue costs it
  # nothing there, the value being resolved inside the target's own fixpoint.
  flake.tests.crossing-adapter.test-approx-does-not-affect-the-target-invoked-rows = {
    expr = (placeInexact adapter false).value;
    expected = {
      channel = "Formals";
      time = "TargetInvoked";
    };
  };

  flake.tests.crossing-adapter.test-row1-admissible-with-bindFormals = {
    expr = (place adapter true).value;
    expected = {
      channel = "Formals";
      time = "Substrate";
    };
  };

  flake.tests.crossing-adapter.test-row2-admissible-without-bindFormals-refuses = {
    expr = codeOf (place (without [ "bindFormals" ]) true);
    expected = "adapter-missing-bind-formals";
  };

  # The blame is on WHOEVER SELECTED THE ADAPTER, not on the supplier: the
  # binding is fine, the adapter cannot host it.
  flake.tests.crossing-adapter.test-row2-blames-the-adapter-selector = {
    expr = blameOf (place (without [ "bindFormals" ]) true);
    expected = "adapter-selector";
  };

  # ★ No silent downgrade: the same adapter offers `wrapFn` and `bindArgEnv`, so
  # a rule that fell through would have produced a TargetInvoked placement here.
  # It refuses instead.
  flake.tests.crossing-adapter.test-admissible-name-is-never-downgraded = {
    expr = x.isRefusal (place (without [ "bindFormals" ]) true);
    expected = true;
  };

  flake.tests.crossing-adapter.test-row3-inadmissible-with-wrapFn = {
    expr = (place adapter false).value;
    expected = {
      channel = "Formals";
      time = "TargetInvoked";
    };
  };

  flake.tests.crossing-adapter.test-row4-inadmissible-without-wrapFn-takes-argEnv = {
    expr = (place (without [ "wrapFn" ]) false).value;
    expected = {
      channel = "ArgEnv";
      time = "TargetInvoked";
    };
  };

  flake.tests.crossing-adapter.test-row5-inadmissible-with-neither-refuses = {
    expr = codeOf (
      place (without [
        "wrapFn"
        "bindArgEnv"
      ]) false
    );
    expected = "adapter-missing-target-invoked-channel";
  };

  flake.tests.crossing-adapter.test-row5-witness-names-what-was-offered = {
    expr =
      (place (without [
        "wrapFn"
        "bindArgEnv"
      ]) false).refusal.witness.offered;
    expected = [
      "bindFormals"
      "wrapUnit"
      "interpret"
    ];
  };

  # ── PLACEMENT IS RESOLVED, NEVER STORED. Two adapters over one crossing yield
  #    ONE crossing node and TWO placements, which is correct: placement is an
  #    output of `close`, not a fact about the relation, and identity does not
  #    vary with what a later pass computes about the node.
  flake.tests.crossing-adapter.test-two-adapters-one-crossing-two-placements = {
    expr =
      let
        a = (place adapter false).value;
        b = (place (without [ "wrapFn" ]) false).value;
      in
      {
        differ = a != b;
        bothTargetInvoked = a.time == b.time;
      };
    expected = {
      differ = true;
      bothTargetInvoked = true;
    };
  };

  # ── the Adapter record is TOTAL: a missing key is malformed, not permissive,
  #    so `null` is how "this adapter does not offer that position" is said
  #    VISIBLY. The alternative is Nix's own uncatchable arity error.
  flake.tests.crossing-adapter.test-adapter-missing-a-field-refuses = {
    expr = (x.mkAdapter (builtins.removeAttrs adapter [ "wrapUnit" ])).refusal.witness.missing;
    expected = [ "wrapUnit" ];
  };

  flake.tests.crossing-adapter.test-adapter-refusal-is-a-value-not-an-arity-error = {
    expr = (builtins.tryEval (codeOf (x.mkAdapter { }))).success;
    expected = true;
  };

  flake.tests.crossing-adapter.test-adapter-null-wrapUnit-refuses = {
    expr = codeOf (x.mkAdapter (adapter // { wrapUnit = null; }));
    expected = "adapter-malformed";
  };

  flake.tests.crossing-adapter.test-adapter-non-function-field-refuses = {
    expr = (x.mkAdapter (adapter // { bindFormals = "not-a-function"; })).refusal.witness.notFunction;
    expected = [ "bindFormals" ];
  };

  flake.tests.crossing-adapter.test-control-a-total-adapter-is-admitted = {
    expr = builtins.attrNames (x.mkAdapter adapter).value;
    expected = [
      "bindArgEnv"
      "bindFormals"
      "interpret"
      "wrapFn"
      "wrapUnit"
    ];
  };

  flake.tests.crossing-adapter.test-control-null-optional-positions-are-admitted = {
    expr = x.isOk (
      x.mkAdapter (without [
        "wrapFn"
        "bindArgEnv"
        "bindFormals"
      ])
    );
    expected = true;
  };
}

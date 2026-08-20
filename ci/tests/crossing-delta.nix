# The derived demand relation: the stratification, the structural recursion, and
# the exactness bit the derived class is decided on.
#
# Oracle: spec §3.3 P-A arm (c) SIBLINGS, with the constructor NAMED because
# "sibling that carries no demand" has two readings and one of them is a
# different arm; §2.10a's totality table; §2.4a-i's four measured properties;
# §2.11's registration row.
#
# ★ A run that exercises only the `Termed` arm has tested ONE of four equations
# and cannot speak to the closure condition the derived-class row rests on. All
# four are exercised below, each named.
{ genBind, ... }:
let
  f = import ./_crossing-fixtures.nix { inherit genBind; };
  inherit (f)
    x
    t
    reg
    proj
    heights
    plainB
    termedB
    wrappedB
    codeOf
    ;

  scopedB =
    p:
    x.binding.scoped {
      file = ./_crossing-scoped-body.nix;
      scope = {
        supplied = "FROM-SCOPE";
      };
      producer = p;
      mark = x.mark.open;
    };

  floorTermed =
    term:
    x.binding.termed {
      inherit term;
      mark = x.mark.floor;
    };

  chain = {
    leaf = plainB { host = "igloo"; };
    mid = termedB (t.readCtx "leaf" [ "host" ]);
    top = termedB (t.attrs { v = t.readCtx "mid" [ ]; });
  };
in
{
  # ── §2.4a-i property 3: a REFERENCE-FREE SIBLING SITS BELOW EVERYTHING, so the
  #    strictly-lower relation holds by construction and a same-level read of a
  #    reference-free sibling is not refused but UNCONSTRUCTIBLE.
  flake.tests.crossing-delta.test-reference-free-binding-is-height-zero = {
    expr = (heights chain).leaf;
    expected = 0;
  };

  flake.tests.crossing-delta.test-heights-ascend-with-the-reference-chain = {
    expr = {
      inherit (heights chain) mid top;
    };
    expected = {
      mid = 1;
      top = 2;
    };
  };

  # ── property 2: PRESENTATION-ORDER INVARIANT BY CONSTRUCTION. `max` over a set
  #    is order-free and the bindings live in an attrset, which carries no order.
  #    (This is the SIBLING-HEIGHT assignment inside one supply and nothing else;
  #    the minting spec's pass-assignment obligation is a different assignment on
  #    a different graph and is NOT discharged here.)
  flake.tests.crossing-delta.test-strata-are-presentation-order-invariant = {
    expr =
      let
        a = heights {
          leaf = chain.leaf;
          mid = chain.mid;
          top = chain.top;
        };
        b = heights {
          top = chain.top;
          leaf = chain.leaf;
          mid = chain.mid;
        };
      in
      a == b;
    expected = true;
  };

  # ── THE DOMAIN, stated because `max` over a partial set otherwise has no
  #    value: a head naming NO sibling contributes nothing to the max. Such a
  #    binding stratifies at height 1 — registration decides STRATIFIABILITY,
  #    resolution decides RESOLVABILITY, and conflating them reports a cycle that
  #    does not exist.
  flake.tests.crossing-delta.test-all-dangling-heads-stratify-at-height-one = {
    expr = (heights { lonely = termedB (t.readCtx "nowhere" [ ]); }).lonely;
    expected = 1;
  };

  # ── property 4: a cycle has NO stratification and is refused at REGISTRATION,
  #    before the recursion runs. Not a traversal-time detector: an unstratifiable
  #    supply is MALFORMED and never reaches the equations.
  flake.tests.crossing-delta.test-sibling-cycle-refused-at-registration = {
    expr = codeOf (reg {
      a = termedB (t.readCtx "bee" [ ]);
      bee = termedB (t.readCtx "a" [ ]);
    });
    expected = "supply-unstratifiable";
  };

  flake.tests.crossing-delta.test-self-cycle-refused-at-registration = {
    expr = codeOf (reg {
      a = termedB (t.readCtx "a" [ ]);
    });
    expected = "supply-unstratifiable";
  };

  # THE WITNESS IS A SUPERSET OF THE CYCLE'S MEMBERS: it includes every binding
  # that can REACH one. A supplier handed a binding whose only fault is naming a
  # broken one must be able to tell that from lying on the cycle.
  flake.tests.crossing-delta.test-unstratifiable-witness-includes-reachers = {
    expr =
      (reg {
        a = termedB (t.readCtx "bee" [ ]);
        bee = termedB (t.readCtx "a" [ ]);
        innocent = termedB (t.readCtx "a" [ ]);
      }).refusal.witness.withoutFiniteHeight;
    expected = [
      "a"
      "bee"
      "innocent"
    ];
  };

  flake.tests.crossing-delta.test-control-acyclic-supply-stratifies = {
    expr = x.isOk (reg chain);
    expected = true;
  };

  # ── the equations. ONE former names a unit.
  flake.tests.crossing-delta.test-readFrom-is-the-only-unit-naming-former = {
    expr = proj {
      readsUnit = termedB (t.readFrom "iceberg" [ "x" ]);
      readsNothing = termedB (
        t.attrs {
          a = t.lit 1;
          b = t.concat [ (t.lit "s") ];
          c = t.apply "length" [ (t.lit [ ]) ];
        }
      );
    };
    expected = {
      readsUnit = {
        targets = [ "iceberg" ];
        exact = "EXACT";
      };
      readsNothing = {
        targets = [ ];
        exact = "EXACT";
      };
    };
  };

  # `If` chooses between literal reads; the recursion takes the union over the
  # condition and BOTH arms, which OVER-APPROXIMATES the dynamic demand set — the
  # sound direction for a demand analysis.
  flake.tests.crossing-delta.test-if-unions-all-three-arms = {
    expr =
      (proj {
        branch = termedB (
          t.ifThenElse (t.readFrom "cond-unit" [ "c" ]) (t.readFrom "then-unit" [ ]) (
            t.readFrom "else-unit" [ ]
          )
        );
      }).branch.targets;
    expected = [
      "cond-unit"
      "then-unit"
      "else-unit"
    ];
  };

  # ── arm (c) SIBLINGS, all four equations, each named.
  flake.tests.crossing-delta.test-sibling-termed-carrying-demand-propagates-it = {
    expr =
      (proj {
        producer = termedB (t.readFrom "iceberg" [ "x" ]);
        reader = termedB (t.readCtx "producer" [ ]);
      }).reader;
    expected = {
      targets = [ "iceberg" ];
      exact = "EXACT";
    };
  };

  flake.tests.crossing-delta.test-control-sibling-termed-without-readFrom-is-empty-and-exact = {
    expr =
      (proj {
        quiet = termedB (t.lit 1);
        reader = termedB (t.readCtx "quiet" [ ]);
      }).reader;
    expected = {
      targets = [ ];
      exact = "EXACT";
    };
  };

  # By the `Plain` equation, NOT by falling through: a Plain sibling costs
  # exactness NOTHING, so a closure of Termed and Plain is exact and a width
  # written as "entirely Termed" would exclude it wrongly.
  flake.tests.crossing-delta.test-control-sibling-plain-is-empty-and-exact = {
    expr =
      (proj {
        base = plainB { host = "igloo"; };
        reader = termedB (t.readCtx "base" [ "host" ]);
      }).reader;
    expected = {
      targets = [ ];
      exact = "EXACT";
    };
  };

  flake.tests.crossing-delta.test-sibling-wrapped-contributes-producer-and-APPROX = {
    expr =
      (proj {
        opaque = wrappedB "iceberg" (_: 1);
        reader = termedB (t.readCtx "opaque" [ ]);
      }).reader;
    expected = {
      targets = [ "iceberg" ];
      exact = "APPROX";
    };
  };

  flake.tests.crossing-delta.test-sibling-scoped-contributes-producer-and-APPROX = {
    expr =
      (proj {
        fromFile = scopedB "iceberg";
        reader = termedB (t.readCtx "fromFile" [ ]);
      }).reader;
    expected = {
      targets = [ "iceberg" ];
      exact = "APPROX";
    };
  };

  # ★ The residue PROPAGATES: a Termed binding whose transitive closure reaches a
  # Wrapped sibling is no more total than that sibling, which is exactly why the
  # derived-class row is narrower than "Termed".
  flake.tests.crossing-delta.test-residue-propagates-transitively = {
    expr =
      (proj {
        opaque = wrappedB "iceberg" (_: 1);
        mid = termedB (t.readCtx "opaque" [ ]);
        top = termedB (t.readCtx "mid" [ ]);
      }).top.exact;
    expected = "APPROX";
  };

  # The bit sees through `If`, because the join conjoins all three arms and a
  # residue-carrying arm therefore marks the whole term APPROX. That is the
  # conservative direction.
  flake.tests.crossing-delta.test-exactness-sees-through-if = {
    expr =
      (proj {
        opaque = wrappedB "iceberg" (_: 1);
        branch = termedB (t.ifThenElse (t.lit true) (t.lit 1) (t.readCtx "opaque" [ ]));
      }).branch.exact;
    expected = "APPROX";
  };

  # ★ COMPUTING THE SET WITHOUT THE BIT IS NO BETTER: an APPROX chain and an
  # EXACT chain of the same shape return IDENTICAL, INDISTINGUISHABLE SETS, so a
  # predicate over the set alone cannot decide the row's condition. This cell IS
  # that measurement.
  flake.tests.crossing-delta.test-sets-alone-cannot-decide-the-derived-class = {
    expr =
      let
        p = proj {
          exactProducer = termedB (t.readFrom "iceberg" [ "x" ]);
          exactReader = termedB (t.readCtx "exactProducer" [ ]);
          approxProducer = wrappedB "iceberg" (_: 1);
          approxReader = termedB (t.readCtx "approxProducer" [ ]);
        };
      in
      {
        setsAgree = p.exactReader.targets == p.approxReader.targets;
        bitsDiffer = p.exactReader.exact != p.approxReader.exact;
      };
    expected = {
      setsAgree = true;
      bitsDiffer = true;
    };
  };

  # ── the DANGLING row. The recursion is materialized BEFORE `link`, so leaving
  #    this case undefined would abort UNCATCHABLY before the row that objects
  #    could fire. Registration and the recursion take the same lenient
  #    disposition; only `link` refuses.
  flake.tests.crossing-delta.test-dangling-head-contributes-nothing = {
    expr = (proj { lonely = termedB (t.readCtx "nowhere" [ ]); }).lonely;
    expected = {
      targets = [ ];
      exact = "EXACT";
    };
  };

  flake.tests.crossing-delta.test-dangling-head-does-not-abort = {
    expr =
      (builtins.tryEval (proj {
        lonely = termedB (t.readCtx "nowhere" [ ]);
      })).success;
    expected = true;
  };

  # ── ★★ THE ANALYSIS DOES NOT RESPECT ACCESS MARKS, AND THAT IS THE POINT.
  #    ADR-0026's mark is compiled into a QUERY's reachability — access. This
  #    recursion is not a query, it is the input a GATE is trusted for, and a gate
  #    whose domain is narrower than the property it is trusted for is exactly the
  #    narrowing ADR-0030 forbids. So the walk sees THROUGH the floor and computes
  #    the true demand set; the marks bound `crossings` and `E` and nothing else.
  #
  #    An earlier revision cut the walk here and recorded the cut as APPROX. That
  #    was FAIL-OPEN in the direction that matters: a Floor-marked binding
  #    demanding the consuming target reported an EMPTY demand set, and the
  #    congruence predicate then admitted a substrate placement the value cannot
  #    support. These two cells are the seeded probe for that defect.
  flake.tests.crossing-delta.test-floor-mark-does-not-blind-the-analysis = {
    expr =
      (proj {
        producer = floorTermed (t.readFrom "iceberg" [ "x" ]);
        reader = termedB (t.readCtx "producer" [ ]);
      }).reader;
    expected = {
      targets = [ "iceberg" ];
      exact = "EXACT";
    };
  };

  flake.tests.crossing-delta.test-control-open-mark-traverses = {
    expr =
      (proj {
        producer = termedB (t.readFrom "iceberg" [ "x" ]);
        reader = termedB (t.readCtx "producer" [ ]);
      }).reader;
    expected = {
      targets = [ "iceberg" ];
      exact = "EXACT";
    };
  };

  # ★ THE EXACT WITNESS THE GATE NAMED: s = Termed(ReadFrom target), Floor-marked;
  # r = Termed(ReadCtx s). Under the withdrawn disposition r's demand set was
  # EMPTY, so r WAS substrate-admissible at the very target it demands — a
  # congruence violation the floor had hidden. It must not be admissible now, and
  # the reason must be the congruence fact itself rather than the exactness belt.
  flake.tests.crossing-delta.test-floor-marked-chain-is-not-substrate-admissible = {
    expr =
      let
        p = proj {
          s = floorTermed (t.readFrom "igloo" [ "x" ]);
          r = termedB (t.readCtx "s" [ ]);
        };
      in
      {
        demandsTheTarget = builtins.elem "igloo" (x.demands p "r");
        staticityAdmissible = !(builtins.elem "igloo" (x.demands p "r"));
        exact = x.deltaExact p "r";
      };
    expected = {
      demandsTheTarget = true;
      staticityAdmissible = false;
      exact = "EXACT";
    };
  };

  # Control, same run, same shape, a target the binding does NOT demand: the
  # analysis is not simply reporting everything.
  flake.tests.crossing-delta.test-control-floor-marked-chain-admits-a-different-target = {
    expr =
      let
        p = proj {
          s = floorTermed (t.readFrom "iceberg" [ "x" ]);
          r = termedB (t.readCtx "s" [ ]);
        };
      in
      !(builtins.elem "igloo" (x.demands p "r"));
    expected = true;
  };

  # A floor must NOT hide a producer edge: that would be the fail-OPEN direction
  # and would let a mark suppress the very demand the congruence predicate exists
  # to catch.
  flake.tests.crossing-delta.test-floor-does-not-suppress-a-producer-edge = {
    expr =
      (proj {
        opaque = x.binding.wrapped {
          producer = "iceberg";
          body = _: 1;
          mark = x.mark.floor;
        };
        reader = termedB (t.readCtx "opaque" [ ]);
      }).reader.targets;
    expected = [ "iceberg" ];
  };

  # ── the carrier itself.
  flake.tests.crossing-delta.test-deltaExact-reads-the-recorded-bit = {
    expr =
      let
        p = proj {
          opaque = wrappedB "iceberg" (_: 1);
          clean = termedB (t.readFrom "iceberg" [ "x" ]);
        };
      in
      {
        clean = x.deltaExact p "clean";
        opaque = x.deltaExact p "opaque";
        cleanIsExact = x.isExact p "clean";
        opaqueIsExact = x.isExact p "opaque";
      };
    expected = {
      clean = "EXACT";
      opaque = "APPROX";
      cleanIsExact = true;
      opaqueIsExact = false;
    };
  };

  # ── registration refuses a `Wrapped` body the substrate cannot itself apply.
  flake.tests.crossing-delta.test-wrapped-non-function-body-refused-at-registration = {
    expr = codeOf (
      x.binding.wrapped {
        producer = "iceberg";
        body = "not-a-function";
        mark = x.mark.open;
      }
    );
    expected = "wrapped-body-not-applicable";
  };

  # ── the mark is TOTAL with no default: an absent declaration leaves the floor
  #    undetermined, which the no-defaults rule forbids.
  flake.tests.crossing-delta.test-binding-mark-must-be-in-the-vocabulary = {
    expr = codeOf (
      x.binding.plain {
        value = 1;
        mark = "Somewhere";
      }
    );
    expected = "binding-mark-missing";
  };

  flake.tests.crossing-delta.test-registerSupply-refuses-a-supply-missing-a-field = {
    expr = codeOf (x.registerSupply { bindings = { }; });
    expected = "declaration-missing-field";
  };

  flake.tests.crossing-delta.test-control-registerSupply-admits-a-total-supply = {
    expr = x.isOk (
      x.registerSupply {
        bindings = { };
        proposals = { };
        origins = { };
      }
    );
    expected = true;
  };

  # An out-of-vocabulary former inside a supply's term is refused when the supply
  # registers, not discovered later inside a target evaluation.
  flake.tests.crossing-delta.test-registration-refuses-out-of-vocabulary-term = {
    expr = codeOf (reg {
      bad = termedB (t.apply "readFile" [ (t.lit "/etc/passwd") ]);
    });
    expected = "term-vocabulary";
  };
}

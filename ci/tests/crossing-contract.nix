# Contracts are DATA, checked substrate-side, EAGER AND COMPLETE.
#
# Oracle: spec §2.7 (i) first-order terms, (ii) the eager check and its price,
# (iii) higher-order contracts inadmissible; §2.11's four contract rows.
{ genBind, ... }:
let
  f = import ./_crossing-fixtures.nix { inherit genBind; };
  inherit (f) x codeOf;
  c = x.contractTerm;
in
{
  # ── (i) a contract is ORDINARY DATA, so structural equality decides contract
  #    equality outright: `merge`'s refusal stops being conservative-by-necessity
  #    and a signature gains an identity it did not have.
  flake.tests.crossing-contract.test-contract-terms-are-comparable-data = {
    expr = {
      same = c.prop "isString" == c.prop "isString";
      different = c.prop "isString" == c.prop "isInt";
      isNotAFunction = builtins.isFunction (c.prop "isString");
    };
    expected = {
      same = true;
      different = false;
      isNotAFunction = false;
    };
  };

  # ── (ii) `Any` is unconstrained SAID VISIBLY and costs NO FORCING. That is what
  #    makes the completeness price opt-in per name: a throwing value passes under
  #    `Any` and is caught under a predicate, in the same run.
  flake.tests.crossing-contract.test-any-passes-without-forcing = {
    expr = x.isOk (x.interpret c.any (throw "never forced"));
    expected = true;
  };

  flake.tests.crossing-contract.test-control-a-predicate-does-force = {
    expr = (builtins.tryEval (x.isOk (x.interpret (c.prop "isString") (throw "forced")))).success;
    expected = false;
  };

  flake.tests.crossing-contract.test-prop-passes-a-satisfying-value = {
    expr = (x.interpret (c.prop "isString") "ok").value;
    expected = "ok";
  };

  flake.tests.crossing-contract.test-prop-refuses-a-violating-value = {
    expr = codeOf (x.interpret (c.prop "isString") 1);
    expected = "contract-violated";
  };

  # The witness names the offending CONSTRUCTOR and the PATH above it.
  flake.tests.crossing-contract.test-violation-witness-carries-constructor-and-path = {
    expr =
      (x.interpret (c.attrs { a = c.attrs { b = c.prop "isInt"; }; }) {
        a = {
          b = "not-an-int";
        };
      }).refusal.witness;
    expected = {
      constructor = "Prop";
      path = [
        "a"
        "b"
      ];
      detail = {
        pred = "isInt";
      };
    };
  };

  # ★ COMPLETENESS, and it is the half of the Degen-Thiemann-Wehr disjunction
  # this construction takes: a violation in a part the target would NEVER HAVE
  # DEMANDED is still reported. A fleet that succeeds today by never forcing a
  # bad part fails under it — that is the price, stated and armed.
  flake.tests.crossing-contract.test-violation-in-an-undemanded-part-is-reported = {
    expr = codeOf (
      x.interpret
        (c.attrs {
          demanded = c.prop "isString";
          neverRead = c.prop "isInt";
        })
        {
          demanded = "fine";
          neverRead = "violating";
        }
    );
    expected = "contract-violated";
  };

  flake.tests.crossing-contract.test-attrs-refuses-a-missing-declared-field = {
    expr = (x.interpret (c.attrs { needed = c.any; }) { }).refusal.witness.detail.missing;
    expected = [ "needed" ];
  };

  flake.tests.crossing-contract.test-attrs-refuses-a-non-set = {
    expr = (x.interpret (c.attrs { }) "not-a-set").refusal.witness.detail.got;
    expected = "string";
  };

  flake.tests.crossing-contract.test-control-attrs-passes-a-conforming-value = {
    expr =
      (x.interpret (c.attrs { a = c.prop "isInt"; }) {
        a = 1;
        extra = "ignored";
      }).value;
    expected = {
      a = 1;
      extra = "ignored";
    };
  };

  flake.tests.crossing-contract.test-list-checks-every-element = {
    expr =
      (x.interpret (c.list (c.prop "isInt")) [
        1
        "bad"
        3
      ]).refusal.witness.path;
    expected = [ "1" ];
  };

  flake.tests.crossing-contract.test-control-list-passes-a-conforming-value = {
    expr =
      (x.interpret (c.list (c.prop "isInt")) [
        1
        2
      ]).value;
    expected = [
      1
      2
    ];
  };

  flake.tests.crossing-contract.test-and-requires-both = {
    expr = {
      pass = x.isOk (x.interpret (c.and (c.prop "isString") (c.prop "nonEmpty")) "x");
      fail = x.isOk (x.interpret (c.and (c.prop "isString") (c.prop "nonEmpty")) "");
    };
    expected = {
      pass = true;
      fail = false;
    };
  };

  # Chitil's `|>`: the right alternative is tried only when the left fails.
  flake.tests.crossing-contract.test-orElse-falls-through-to-the-right = {
    expr = x.isOk (x.interpret (c.orElse (c.prop "isInt") (c.prop "isString")) "a-string");
    expected = true;
  };

  flake.tests.crossing-contract.test-control-orElse-refuses-when-both-fail = {
    expr = x.isOk (x.interpret (c.orElse (c.prop "isInt") (c.prop "isString")) true);
    expected = false;
  };

  flake.tests.crossing-contract.test-never-always-violates = {
    expr = codeOf (x.interpret c.never "anything");
    expected = "contract-violated";
  };

  # ── (iii) HIGHER-ORDER CONTRACTS ARE NOT ADMISSIBLE, and refusing them is what
  #    keeps the substrate-side check TRUE rather than nearly true: the function
  #    combinator's contracts fire ON APPLICATION, inside the consuming target,
  #    which needs the very substrate closure the construction exists to remove.
  flake.tests.crossing-contract.test-function-contract-refused-by-name = {
    expr = codeOf (x.checkContract (_: true));
    expected = "higher-order-contract";
  };

  flake.tests.crossing-contract.test-arrow-tagged-contract-refused-by-name = {
    expr = codeOf (
      x.checkContract {
        __contractTerm = ">->";
        pre = c.any;
        post = c.any;
      }
    );
    expected = "higher-order-contract";
  };

  # A function-valued import may still cross; it simply takes `Any`, and its
  # correctness is the target's concern.
  flake.tests.crossing-contract.test-control-a-function-value-may-cross-under-any = {
    expr = builtins.isFunction (x.interpret c.any (a: a)).value;
    expected = true;
  };

  # ── the vocabulary rows, distinct from the higher-order row because the two
  #    are refused for different reasons.
  flake.tests.crossing-contract.test-out-of-vocabulary-former-refused = {
    expr = codeOf (x.checkContract { __contractTerm = "Fabricated"; });
    expected = "contract-vocabulary";
  };

  flake.tests.crossing-contract.test-out-of-vocabulary-pred-refused = {
    expr = codeOf (x.checkContract (c.prop "isSemverString"));
    expected = "contract-vocabulary";
  };

  flake.tests.crossing-contract.test-nested-out-of-vocabulary-pred-refused = {
    expr = codeOf (x.checkContract (c.attrs { a = c.list (c.prop "isSemverString"); }));
    expected = "contract-vocabulary";
  };

  flake.tests.crossing-contract.test-control-the-vocabulary-is-admitted = {
    expr = x.isOk (
      x.checkContract (
        c.attrs {
          a = c.orElse (c.prop "isInt") (c.and (c.prop "isString") (c.prop "nonEmpty"));
          b = c.list c.any;
          z = c.never;
        }
      )
    );
    expected = true;
  };

  # CLOSED, and extended by owner ruling only — never by accretion.
  flake.tests.crossing-contract.test-contract-vocabulary-is-closed = {
    expr = {
      formers = x.contractFormers;
      preds = x.contractPreds;
    };
    expected = {
      formers = [
        "Any"
        "Never"
        "Prop"
        "Attrs"
        "List"
        "And"
        "OrElse"
      ];
      preds = [
        "isBool"
        "isInt"
        "isPath"
        "isString"
        "nonEmpty"
      ];
    };
  };
}

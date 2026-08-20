# BodyTerm — the closed algebra, the `InertValue` minting walk, the primitive
# vocabulary and resolution.
#
# Oracle: spec §3.3 P-A arms (a) FORMERS and (b) LEAVES, and §3.4 (every named
# refusal fires, none throws). Every refusal cell has its conforming control in
# the same suite: a row whose conforming input is untested has not been armed,
# and a walk that refuses everything is indistinguishable from one that works.
{ genBind, ... }:
let
  f = import ./_crossing-fixtures.nix { inherit genBind; };
  inherit (f)
    x
    t
    codeOf
    resolve
    ;

  deep = n: if n == 0 then 1 else { inner = deep (n - 1); };
  cyclic =
    let
      c = {
        self = c;
      };
    in
    c;
in
{
  # ── (b) LEAVES: the `InertValue` walk. An unconstrained `Lit` is a fixpoint
  #    channel the demand analysis cannot see, so every gate below is load-bearing.
  flake.tests.crossing-term.test-lit-refuses-function = {
    expr = codeOf (t.lit (_: 1));
    expected = "lit-payload-function";
  };

  flake.tests.crossing-term.test-lit-refuses-nested-function = {
    expr = codeOf (t.lit { a.b.c = [ (_: 1) ]; });
    expected = "lit-payload-function";
  };

  flake.tests.crossing-term.test-lit-function-witness-names-the-position = {
    expr = (t.lit { a.b.c = [ (_: 1) ]; }).refusal.witness.path;
    expected = [
      "a"
      "b"
      "c"
      "0"
    ];
  };

  # The type test runs at EVERY node before descending: a root-only test returns
  # false on `{ pkg = drv; }` and the nested derivation then reaches the descent.
  flake.tests.crossing-term.test-lit-refuses-derivation-at-root = {
    expr = codeOf (t.lit { type = "derivation"; });
    expected = "lit-payload-derivation";
  };

  flake.tests.crossing-term.test-lit-refuses-nested-derivation = {
    expr = codeOf (
      t.lit {
        pkg = {
          type = "derivation";
        };
      }
    );
    expected = "lit-payload-derivation";
  };

  flake.tests.crossing-term.test-lit-refuses-derivation-in-list = {
    expr = codeOf (t.lit [ { type = "derivation"; } ]);
    expected = "lit-payload-derivation";
  };

  flake.tests.crossing-term.test-control-lit-admits-attrset-with-ordinary-type-field = {
    expr = (t.lit { type = "not-a-derivation"; }).__bodyTerm;
    expected = "Lit";
  };

  # Budget exhaustion is what ARMS the non-termination case: deciding "reachable
  # from itself" needs an observation of sharing that Nix's builtins do not
  # offer, and structural equality on a cyclic value diverges for the same reason
  # the walk does.
  flake.tests.crossing-term.test-lit-refuses-cyclic-payload-by-budget = {
    expr = codeOf (t.lit cyclic);
    expected = "lit-payload-budget";
  };

  flake.tests.crossing-term.test-lit-cyclic-refusal-is-a-value-not-a-throw = {
    expr = (builtins.tryEval (t.lit cyclic).refusal.code).success;
    expected = true;
  };

  flake.tests.crossing-term.test-lit-refuses-over-depth-budget = {
    expr = (t.lit (deep 40)).refusal.witness.axis;
    expected = "depth";
  };

  flake.tests.crossing-term.test-lit-refuses-over-node-budget = {
    expr = (t.lit (builtins.genList (i: i) 10005)).refusal.witness.axis;
    expected = "nodes";
  };

  flake.tests.crossing-term.test-control-lit-admits-payload-inside-both-budgets = {
    expr = (t.lit (deep 8)).__bodyTerm;
    expected = "Lit";
  };

  # A lazily-erroring field is refused EVEN THOUGH NOTHING READS IT, because the
  # walk forces what lazy evaluation would not. That is a legitimate Nix value
  # being refused and it is a real narrowing beyond the fixpoint case.
  flake.tests.crossing-term.test-lit-refuses-throwing-field = {
    expr = codeOf (t.lit { a = throw "boom"; });
    expected = "lit-payload-throws";
  };

  flake.tests.crossing-term.test-control-lit-admits-inert-scalars-and-paths = {
    expr =
      (t.lit {
        s = "x";
        i = 1;
        b = true;
        n = null;
        xs = [
          1
          2
        ];
      }).__bodyTerm;
    expected = "Lit";
  };

  # A refused `Lit` nested in another former surfaces at the outer former: a
  # refusal cannot be lost by being nested.
  flake.tests.crossing-term.test-refused-lit-propagates-through-attrs = {
    expr = codeOf (t.attrs { a = t.lit (_: 1); });
    expected = "lit-payload-function";
  };

  flake.tests.crossing-term.test-refused-lit-propagates-through-apply = {
    expr = codeOf (t.apply "length" [ (t.lit (_: 1)) ]);
    expected = "lit-payload-function";
  };

  # ── (a) FORMERS: enumerating the constructors finds exactly ONE that names a
  #    unit. That is a finite check over a closed sum type.
  flake.tests.crossing-term.test-former-vocabulary-is-closed = {
    expr = x.knownFormers;
    expected = [
      "Lit"
      "ReadFrom"
      "ReadCtx"
      "If"
      "Attrs"
      "List"
      "Concat"
      "PathJoin"
      "Apply"
    ];
  };

  flake.tests.crossing-term.test-prim-vocabulary-is-closed = {
    expr = builtins.attrNames x.prims;
    expected = [
      "attrNames"
      "concatStringsSep"
      "elemAt"
      "getAttr"
      "length"
      "toString"
    ];
  };

  flake.tests.crossing-term.test-checkTerm-refuses-out-of-vocabulary-former = {
    expr = codeOf (x.checkTerm { __bodyTerm = "Fabricated"; });
    expected = "term-vocabulary";
  };

  flake.tests.crossing-term.test-checkTerm-refuses-out-of-vocabulary-prim = {
    expr = codeOf (x.checkTerm (t.apply "readFile" [ (t.lit "/etc/passwd") ]));
    expected = "term-vocabulary";
  };

  flake.tests.crossing-term.test-checkTerm-refuses-non-term-node = {
    expr = codeOf (x.checkTerm { plain = "attrset"; });
    expected = "term-vocabulary";
  };

  flake.tests.crossing-term.test-control-checkTerm-admits-the-vocabulary = {
    expr = x.isOk (
      x.checkTerm (
        t.attrs {
          a = t.readFrom "iceberg" [ "x" ];
          b = t.ifThenElse (t.lit true) (t.lit 1) (t.readCtx "sib" [ ]);
          c = t.apply "length" [ (t.lit [ 1 ]) ];
        }
      )
    );
    expected = true;
  };

  # ── §2.10a's totality table: every former's degenerate input has a stated
  #    disposition, so the next round has nowhere to hide.
  flake.tests.crossing-term.test-readFrom-empty-path-denotes-the-config-root = {
    expr =
      (x.resolveTerm {
        targets.iceberg = {
          whole = "root";
        };
        siblings = { };
      } (t.readFrom "iceberg" [ ])).value;
    expected = {
      whole = "root";
    };
  };

  flake.tests.crossing-term.test-readCtx-empty-projection-denotes-the-whole-value = {
    expr =
      (x.resolveTerm {
        targets = { };
        siblings.sib = {
          all = 1;
        };
      } (t.readCtx "sib" [ ])).value;
    expected = {
      all = 1;
    };
  };

  flake.tests.crossing-term.test-empty-attrs-list-and-concat-are-defined = {
    expr = {
      attrs = (resolve (t.attrs { })).value;
      list = (resolve (t.list [ ])).value;
      concat = (resolve (t.concat [ ])).value;
    };
    expected = {
      attrs = { };
      list = [ ];
      concat = "";
    };
  };

  flake.tests.crossing-term.test-pathJoin-with-no-segments-is-the-head-alone = {
    expr = (resolve (t.pathJoin (t.lit /tmp) [ ])).value;
    expected = /tmp;
  };

  # ── §2.10c: `Concat` is string-only; paths take `PathJoin`.
  # The class is STORE-COPYING COERCION, not string coercion: `path + "s"` is a
  # path while `"s" + path` is a string COPIED TO THE STORE, and on this corpus's
  # own population that is a store copy of a secrets file as a side effect of a
  # concatenation.
  flake.tests.crossing-term.test-concat-refuses-path-operand = {
    expr = codeOf (
      resolve (
        t.concat [
          (t.lit /tmp)
          (t.lit "x")
        ]
      )
    );
    expected = "path-operand-store-copying-former";
  };

  flake.tests.crossing-term.test-concat-refuses-non-string-operand = {
    expr = codeOf (
      resolve (
        t.concat [
          (t.lit 1)
          (t.lit "x")
        ]
      )
    );
    expected = "former-operand-type";
  };

  flake.tests.crossing-term.test-control-concat-joins-strings = {
    expr =
      (resolve (
        t.concat [
          (t.lit "a")
          (t.lit "b")
        ]
      )).value;
    expected = "ab";
  };

  # Restricting `Concat` alone would re-enter the hazard through a sibling former
  # in the same closed vocabulary: `concatStringsSep` store-copies identically.
  flake.tests.crossing-term.test-concatStringsSep-path-element-is-the-store-copy-row = {
    expr = codeOf (
      x.resolveTerm
        {
          targets.u = {
            p = /tmp;
          };
          siblings = { };
        }
        (
          t.apply "concatStringsSep" [
            (t.lit "-")
            (t.list [ (t.readFrom "u" [ "p" ]) ])
          ]
        )
    );
    expected = "path-operand-store-copying-former";
  };

  flake.tests.crossing-term.test-control-concatStringsSep-joins-strings = {
    expr =
      (resolve (
        t.apply "concatStringsSep" [
          (t.lit "-")
          (t.lit [
            "a"
            "b"
          ])
        ]
      )).value;
    expected = "a-b";
  };

  # `toString` is the SEPARATING ELEMENT and is explicitly outside the store-copy
  # rule — it yields the path's own string and does not store-copy. A rule
  # written over "string coercion" would refuse the one primitive kept.
  flake.tests.crossing-term.test-control-toString-of-a-path-is-admitted = {
    expr = builtins.isString (resolve (t.apply "toString" [ (t.lit /tmp) ])).value;
    expected = true;
  };

  # `Scalar` is a deliberate narrowing: declaring `any` had made the type row
  # unfireable, nothing being mistyped.
  flake.tests.crossing-term.test-toString-of-a-set-is-a-type-violation = {
    expr = codeOf (resolve (t.apply "toString" [ (t.attrs { }) ]));
    expected = "apply-arity-or-type";
  };

  # ── `PathJoin`: the head is structurally separate, so OPERAND ORDER CANNOT
  #    DECIDE THE RESULT TYPE, and the join is separator-bearing because Nix
  #    inserts none.
  flake.tests.crossing-term.test-pathJoin-inserts-the-separator = {
    expr = builtins.baseNameOf (resolve (t.pathJoin (t.lit /tmp) [ (t.lit "child") ])).value;
    expected = "child";
  };

  flake.tests.crossing-term.test-pathJoin-refuses-non-path-head = {
    expr = (resolve (t.pathJoin (t.lit "/tmp") [ (t.lit "x") ])).refusal.witness.position;
    expected = "head";
  };

  flake.tests.crossing-term.test-pathJoin-refuses-non-string-segment = {
    expr = (resolve (t.pathJoin (t.lit /tmp) [ (t.lit 1) ])).refusal.witness.position;
    expected = "segment";
  };

  # The predicate is over COMPONENTS, never substrings: `p + "/../x"` normalises
  # silently and escapes the head's directory, while `p + "/a..b"` is harmless.
  flake.tests.crossing-term.test-pathJoin-refuses-parent-component = {
    expr = (resolve (t.pathJoin (t.lit /tmp) [ (t.lit "../etc") ])).refusal.witness.reason;
    expected = "parent-directory-component";
  };

  flake.tests.crossing-term.test-control-pathJoin-admits-dots-inside-a-component = {
    expr = builtins.baseNameOf (resolve (t.pathJoin (t.lit /tmp) [ (t.lit "a..b") ])).value;
    expected = "a..b";
  };

  # ── `Apply`: arity, TYPE and DOMAIN are three distinct rows. Measured in the
  #    spec: two of the six primitives abort UNCATCHABLY on operands their
  #    declared types admit, which is what the domain row exists to convert.
  flake.tests.crossing-term.test-apply-refuses-arity-mismatch = {
    expr = codeOf (
      resolve (
        t.apply "length" [
          (t.lit [ ])
          (t.lit 1)
        ]
      )
    );
    expected = "apply-arity-or-type";
  };

  flake.tests.crossing-term.test-apply-refuses-operand-type = {
    expr = codeOf (resolve (t.apply "length" [ (t.lit "not-a-list") ]));
    expected = "apply-arity-or-type";
  };

  flake.tests.crossing-term.test-apply-refuses-elemAt-out-of-range = {
    expr = codeOf (
      resolve (
        t.apply "elemAt" [
          (t.lit [
            1
            2
          ])
          (t.lit 7)
        ]
      )
    );
    expected = "apply-domain";
  };

  flake.tests.crossing-term.test-apply-refuses-elemAt-negative-index = {
    expr = codeOf (
      resolve (
        t.apply "elemAt" [
          (t.lit [
            1
            2
          ])
          (t.lit (-1))
        ]
      )
    );
    expected = "apply-domain";
  };

  flake.tests.crossing-term.test-apply-refuses-getAttr-absent-name = {
    expr = codeOf (
      resolve (
        t.apply "getAttr" [
          (t.lit "missing")
          (t.lit { present = 1; })
        ]
      )
    );
    expected = "apply-domain";
  };

  flake.tests.crossing-term.test-apply-domain-refusal-is-a-value-not-an-abort = {
    expr =
      (builtins.tryEval (
        codeOf (
          resolve (
            t.apply "getAttr" [
              (t.lit "missing")
              (t.lit { present = 1; })
            ]
          )
        )
      )).success;
    expected = true;
  };

  flake.tests.crossing-term.test-control-apply-in-domain-computes = {
    expr = {
      elemAt =
        (resolve (
          t.apply "elemAt" [
            (t.lit [
              1
              2
            ])
            (t.lit 1)
          ]
        )).value;
      getAttr =
        (resolve (
          t.apply "getAttr" [
            (t.lit "present")
            (t.lit { present = 42; })
          ]
        )).value;
      length =
        (resolve (
          t.apply "length" [
            (t.lit [
              1
              2
              3
            ])
          ]
        )).value;
      attrNames =
        (resolve (
          t.apply "attrNames" [
            (t.lit {
              b = 1;
              a = 2;
            })
          ]
        )).value;
    };
    expected = {
      elemAt = 2;
      getAttr = 42;
      length = 3;
      attrNames = [
        "a"
        "b"
      ];
    };
  };

  # ── `If` chooses BETWEEN literal reads; it never computes one.
  flake.tests.crossing-term.test-if-selects-a-branch-at-resolution = {
    expr = (resolve (t.ifThenElse (t.lit false) (t.lit "then") (t.lit "else"))).value;
    expected = "else";
  };

  flake.tests.crossing-term.test-if-refuses-non-bool-condition = {
    expr = codeOf (resolve (t.ifThenElse (t.lit 1) (t.lit "a") (t.lit "b")));
    expected = "former-operand-type";
  };

  # ── the sibling channel resolves to the sibling's VALUE, never its Binding
  #    RECORD: a `Wrapped` sibling's record carries a function that would ride
  #    into the target.
  flake.tests.crossing-term.test-readCtx-projects-the-sibling-value = {
    expr =
      (x.resolveTerm {
        targets = { };
        siblings.base = {
          host = "igloo";
        };
      } (t.readCtx "base" [ "host" ])).value;
    expected = "igloo";
  };

  flake.tests.crossing-term.test-readCtx-refuses-an-unresolvable-head-at-resolution = {
    expr = codeOf (resolve (t.readCtx "absent" [ ]));
    expected = "readctx-unresolvable-sibling";
  };

  # §2.11 places this row at `link`, whose signature carries no member list; it is
  # armed here, where the resolution environment IS in scope, and again at `close`
  # under the coherence row — a ReadFrom-named unit is in the demand set, hence in
  # the cross-unit environment the containment check ranges over.
  flake.tests.crossing-term.test-readFrom-naming-an-absent-unit-refuses-by-name = {
    expr = codeOf (resolve (t.readFrom "not-in-the-fleet" [ "x" ]));
    expected = "readfrom-names-non-member";
  };

  flake.tests.crossing-term.test-control-readFrom-naming-a-present-unit-resolves = {
    expr =
      (x.resolveTerm {
        targets.iceberg = {
          x = "read";
        };
        siblings = { };
      } (t.readFrom "iceberg" [ "x" ])).value;
    expected = "read";
  };

  flake.tests.crossing-term.test-projection-path-missing-refuses-by-name = {
    expr = codeOf (
      x.resolveTerm {
        targets = { };
        siblings.base = {
          host = "igloo";
        };
      } (t.readCtx "base" [ "absent" ])
    );
    expected = "projection-path-missing";
  };

  # ★ `Termed` is NOT a restriction on the authoring language. An author builds
  # the term with ordinary Nix — map, listToAttrs, computed attribute names — and
  # all of that runs at TERM-CONSTRUCTION time, leaving a term whose keys and
  # whose read paths are literal by the time the analysis runs.
  flake.tests.crossing-term.test-control-generated-term-is-ordinary-nix = {
    expr =
      (resolve (
        t.attrs (
          builtins.listToAttrs (
            builtins.map
              (n: {
                name = "key-${n}";
                value = t.lit n;
              })
              [
                "a"
                "b"
              ]
          )
        )
      )).value;
    expected = {
      key-a = "a";
      key-b = "b";
    };
  };
}

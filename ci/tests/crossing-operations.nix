# The six operations, the crossing node, and the invariant the whole
# construction exists to deliver.
#
# Oracle: spec §3.2 (what crosses is provably plain data), §3.4 (every named
# refusal fires and none throws), §3.5 (identity and staging), plus §2.5's two
# steps recorded on the node and §2.11's declare/merge/link/close rows.
{
  genBind,
  genPrelude,
  lib,
  ...
}:
let
  f = import ./_crossing-fixtures.nix { inherit genBind; };
  inherit (f)
    x
    t
    sig
    imp
    proj
    supply
    plainB
    termedB
    wrappedB
    adapter
    codeOf
    pipeline
    published
    _testHashIdentity
    ;

  # Comment-stripped library source, for the non-leakage scan. Same technique as
  # the `purity` suite, and for the same reason: documentation may name a
  # forbidden token freely, only CODE may not carry one.
  crossingSources =
    let
      libDir = ../../lib;
      names = builtins.filter (n: lib.hasSuffix ".nix" n && lib.hasPrefix "crossing" n) (
        builtins.attrNames (builtins.readDir libDir)
      );
    in
    map (n: {
      name = n;
      code = lib.concatStringsSep "\n" (
        map (line: lib.head (lib.splitString "#" line)) (
          lib.splitString "\n" (builtins.readFile (libDir + "/${n}"))
        )
      );
    }) names;

  c = x.contractTerm;

  simpleBindings = {
    base = plainB { host = "igloo"; };
    derived = termedB (t.readCtx "base" [ "host" ]);
  };

  simpleImports = {
    base = imp c.any;
    derived = imp (c.prop "isString");
  };

  linkedFragment =
    let
      frag = x.declare (sig simpleImports) { kind = "body"; };
    in
    x.link "igloo" (proj simpleBindings) (supply simpleBindings) frag.value;

  nodesOf = frag: builtins.map (id: frag.nodes.${id}) frag.crossings;

  # A payload-side predicate: over every position the SUBSTRATE ITSELF WROTE, no
  # function is reachable, transitively. Positions holding a pass-through user
  # value are outside this predicate's domain and are named as outside it rather
  # than silently counted clean.
  reachesFunction =
    v:
    if builtins.isFunction v then
      true
    else if builtins.isList v then
      builtins.any reachesFunction v
    else if builtins.isAttrs v then
      builtins.any reachesFunction (builtins.attrValues v)
    else
      false;
in
{
  # ── declare: the signature is TOTAL. No field has a default; omission is
  #    MALFORMED, not unconstrained, because absence as a silent default is a
  #    decision nobody made.
  flake.tests.crossing-operations.test-declare-refuses-an-import-missing-a-field = {
    expr =
      (x.declare (sig { a = builtins.removeAttrs (imp c.any) [ "sealed" ]; }) null)
      .refusal.witness.missing;
    expected = [ "sealed" ];
  };

  flake.tests.crossing-operations.test-declare-refuses-an-out-of-vocabulary-merge-policy = {
    expr = codeOf (
      x.declare (sig {
        a = (imp c.any) // {
          merge = "clobber";
        };
      }) null
    );
    expected = "merge-policy-vocabulary";
  };

  flake.tests.crossing-operations.test-declare-refuses-a-higher-order-contract = {
    expr = codeOf (x.declare (sig { a = imp (_: true); }) null);
    expected = "higher-order-contract";
  };

  # Cardelli Definition 5-2: imp(L) intersect exp(L) is empty.
  flake.tests.crossing-operations.test-declare-refuses-import-export-overlap = {
    expr = codeOf (
      x.declare {
        imports.a = imp c.any;
        exports.a = {
          contract = c.any;
          origin = "fixture";
        };
      } null
    );
    expected = "import-export-overlap";
  };

  flake.tests.crossing-operations.test-control-declare-admits-a-total-signature = {
    expr = x.isOk (x.declare (sig simpleImports) { kind = "body"; });
    expected = true;
  };

  flake.tests.crossing-operations.test-declare-mints-a-token = {
    expr = (x.declare (sig { }) null).value.token ? __fragmentToken;
    expected = true;
  };

  # ── residue: the unsatisfied portion of a TOTAL signature. It cannot be
  #    structurally always empty, because the totality rule is what stops the
  #    minuend being incomplete.
  flake.tests.crossing-operations.test-residue-is-the-whole-signature-before-linking = {
    expr = builtins.attrNames (x.residue (x.declare (sig simpleImports) null).value).imports;
    expected = [
      "base"
      "derived"
    ];
  };

  flake.tests.crossing-operations.test-residue-narrows-at-link = {
    expr = builtins.attrNames (x.residue linkedFragment.value).imports;
    expected = [ ];
  };

  flake.tests.crossing-operations.test-control-residue-keeps-an-unsatisfied-name = {
    expr =
      let
        frag = x.declare (sig (simpleImports // { extra = imp c.any; })) null;
        l = x.link "igloo" (proj simpleBindings) (supply simpleBindings) frag.value;
      in
      builtins.attrNames (x.residue l.value).imports;
    expected = [ "extra" ];
  };

  # ── merge: exports are DISJOINT across fragments (Cardelli 5-7's
  #    precondition); imports may overlap, and a DIFFERING declaration is the
  #    incompatibility — structural equality decides it.
  flake.tests.crossing-operations.test-merge-refuses-duplicate-export = {
    expr =
      let
        e = {
          exports.a = {
            contract = c.any;
            origin = "left";
          };
          imports = { };
        };
        fa = (x.declare e null).value;
        fb =
          (x.declare (
            e
            // {
              exports.a = {
                contract = c.any;
                origin = "right";
              };
            }
          ) null).value;
      in
      codeOf (x.merge fa fb);
    expected = "duplicate-export";
  };

  flake.tests.crossing-operations.test-merge-refuses-incompatible-import = {
    expr =
      let
        fa = (x.declare (sig { a = imp (c.prop "isString"); }) null).value;
        fb = (x.declare (sig { a = imp (c.prop "isInt"); }) null).value;
      in
      (x.merge fa fb).refusal.witness;
    expected = [
      {
        name = "a";
        fields = [ "contract" ];
        origins = [
          "fixture"
          "fixture"
        ];
      }
    ];
  };

  # ★ A DIFFERING ORIGIN IS NOT AN INCOMPATIBILITY. Two declarers of one name
  # necessarily differ there, and the witness carries both origins BESIDE the
  # differing fields — so comparing origins would refuse every compatible merge.
  flake.tests.crossing-operations.test-control-merge-admits-differing-origins = {
    expr =
      let
        fa = (x.declare (sig { a = imp c.any; }) null).value;
        fb =
          (x.declare (sig {
            a = (imp c.any) // {
              origin = "elsewhere";
            };
          }) null).value;
      in
      x.isOk (x.merge fa fb);
    expected = true;
  };

  flake.tests.crossing-operations.test-control-merge-unions-disjoint-signatures = {
    expr =
      let
        fa = (x.declare (sig { a = imp c.any; }) null).value;
        fb = (x.declare (sig { b = imp c.any; }) null).value;
      in
      builtins.attrNames (x.merge fa fb).value.signature.imports;
    expected = [
      "a"
      "b"
    ];
  };

  # ── gate: Jones's precondition is ENFORCED, not inherited. Without the row the
  #    surface would face a choice between writing a conditional edge and
  #    silently producing an incomplete union.
  flake.tests.crossing-operations.test-gate-refuses-a-non-finite-enum = {
    expr = codeOf (
      x.gate {
        enum = throw "not determined before any target fixpoint";
        select = x.selectTerm.literal "a";
        branches = { };
      }
    );
    expected = "gate-enum-not-finite";
  };

  flake.tests.crossing-operations.test-gate-refuses-an-empty-enum = {
    expr = codeOf (
      x.gate {
        enum = [ ];
        select = x.selectTerm.literal "a";
        branches = { };
      }
    );
    expected = "gate-enum-not-finite";
  };

  flake.tests.crossing-operations.test-gate-refuses-an-uncovered-key = {
    expr =
      (x.gate {
        enum = [
          "a"
          "b"
        ];
        select = x.selectTerm.literal "a";
        branches.a = (x.declare (sig { }) null).value;
      }).refusal.witness.uncovered;
    expected = [ "b" ];
  };

  # Branches of ONE gate are ALTERNATIVES, so identical declarations union and
  # only a DIFFERING one refuses — an incompatibility, never a silent union.
  flake.tests.crossing-operations.test-gate-refuses-incompatible-branches = {
    expr = codeOf (
      x.gate {
        enum = [
          "a"
          "b"
        ];
        select = x.selectTerm.literal "a";
        branches = {
          a = (x.declare (sig { n = imp (c.prop "isString"); }) null).value;
          b = (x.declare (sig { n = imp (c.prop "isInt"); }) null).value;
        };
      }
    );
    expected = "merge-incompatibility";
  };

  # With the precondition enforced EVERY BRANCH IS MATERIALIZED, so the declared
  # edge set is the union over branches unconditionally — whether or not that
  # branch is selected.
  flake.tests.crossing-operations.test-control-gate-unions-every-branch = {
    expr =
      builtins.attrNames
        (x.gate {
          enum = [
            "a"
            "b"
          ];
          select = x.selectTerm.literal "a";
          branches = {
            a = (x.declare (sig { fromA = imp c.any; }) null).value;
            b = (x.declare (sig { fromB = imp c.any; }) null).value;
          };
        }).value.signature.imports;
    expected = [
      "fromA"
      "fromB"
    ];
  };

  # ── link mints ONE CROSSING PER name-and-binding pair it satisfies, and
  #    records BOTH derived facts on the node: the congruence verdict (step 1)
  #    and the residue bit (step 1b).
  flake.tests.crossing-operations.test-link-mints-one-crossing-per-satisfied-name = {
    expr = builtins.length linkedFragment.value.crossings;
    expected = 2;
  };

  flake.tests.crossing-operations.test-crossing-node-records-both-derived-facts = {
    # Keyed by name, because `crossings` is ordered by IDENTITY and identity is a
    # hash: a cell that depended on that order would be asserting something about
    # the digest rather than about the node.
    expr = builtins.listToAttrs (
      builtins.map (n: {
        name = n.import;
        value = {
          inherit (n) staticityAdmissible deltaExact;
        };
      }) (nodesOf linkedFragment.value)
    );
    expected = {
      base = {
        staticityAdmissible = true;
        deltaExact = "EXACT";
      };
      derived = {
        staticityAdmissible = true;
        deltaExact = "EXACT";
      };
    };
  };

  # The relata are the IMPORT, the BINDING and the TARGET — the binding, never
  # the supply, because the demand set is a property of a body and a body is a
  # field of a binding.
  flake.tests.crossing-operations.test-crossing-relata-are-import-binding-target = {
    expr = builtins.attrNames (builtins.head (nodesOf linkedFragment.value));
    expected = [
      "binding"
      "deltaExact"
      "id"
      "import"
      "origin"
      "record"
      "staticityAdmissible"
      "target"
    ];
  };

  flake.tests.crossing-operations.test-link-refuses-a-dangling-sibling-head = {
    expr =
      let
        bindings = {
          reader = termedB (t.readCtx "nowhere" [ ]);
        };
        frag = x.declare (sig { reader = imp c.any; }) null;
      in
      codeOf (x.link "igloo" (proj bindings) (supply bindings) frag.value);
    expected = "readctx-unresolvable-sibling";
  };

  flake.tests.crossing-operations.test-link-refuses-a-proposal-against-a-sealed-declaration = {
    expr =
      let
        bindings = {
          a = plainB 1;
        };
        frag = x.declare (sig {
          a = (imp c.any) // {
            sealed = true;
          };
        }) null;
      in
      codeOf (
        x.link "igloo" (proj bindings) (
          (supply bindings)
          // {
            proposals.a = {
              policy = "first";
              origin = "proposer";
            };
          }
        ) frag.value
      );
    expected = "proposal-against-sealed";
  };

  # `link` consumes the MATERIALIZED projection and never re-runs the query under
  # its own reachability, so a satisfied name with no entry is a refusal rather
  # than a silent recomputation.
  flake.tests.crossing-operations.test-link-refuses-a-name-absent-from-the-projection = {
    expr =
      let
        bindings = {
          a = plainB 1;
        };
        frag = x.declare (sig { a = imp c.any; }) null;
      in
      (x.link "igloo" { } (supply bindings) frag.value).refusal.witness.names;
    expected = [ "a" ];
  };

  flake.tests.crossing-operations.test-control-link-admits-a-name-present-in-the-projection = {
    expr =
      let
        bindings = {
          a = plainB 1;
        };
        frag = x.declare (sig { a = imp c.any; }) null;
      in
      x.isOk (x.link "igloo" (proj bindings) (supply bindings) frag.value);
    expected = true;
  };

  flake.tests.crossing-operations.test-link-refuses-a-forged-token = {
    expr = codeOf (
      x.link "igloo" { } (supply { }) {
        signature = sig { };
        token = {
          __fragmentToken = "forged";
        };
      }
    );
    expected = "fragment-token";
  };

  # ── §3.5 IDENTITY AND STAGING. Order-insensitivity holds AT THE ENCODING and
  #    no caller owes a sort: two emitters presenting the same relata under
  #    different label orders mint ONE crossing.
  flake.tests.crossing-operations.test-identity-is-label-order-insensitive = {
    expr =
      let
        a = x.mintIdentity _testHashIdentity "crossing" {
          import = "db";
          binding = "db";
          target = "igloo";
        };
        b = x.mintIdentity _testHashIdentity "crossing" {
          target = "igloo";
          binding = "db";
          import = "db";
        };
      in
      a.value == b.value;
    expected = true;
  };

  # A collapse oracle whose SEPARATING case is untested proves nothing: distinct
  # relata must mint distinct crossings in the same run.
  flake.tests.crossing-operations.test-control-distinct-relata-mint-distinct-crossings = {
    expr =
      let
        a = x.mintIdentity _testHashIdentity "crossing" {
          import = "db";
          binding = "db";
          target = "igloo";
        };
        b = x.mintIdentity _testHashIdentity "crossing" {
          import = "db";
          binding = "db";
          target = "iceberg";
        };
      in
      a.value == b.value;
    expected = false;
  };

  flake.tests.crossing-operations.test-empty-relation-kind-refuses-by-name = {
    expr = codeOf (x.mintIdentity _testHashIdentity "" { import = "db"; });
    expected = "empty-relation-kind";
  };

  flake.tests.crossing-operations.test-the-minting-authority-is-injected-not-defined-here = {
    expr =
      let
        other =
          (published.mkOperations {
            hashIdentity =
              kind: labels: _:
              "${kind}/${builtins.concatStringsSep "+" labels}";
          }).value;
        frag = x.declare (sig { base = imp c.any; }) null;
        b = {
          base = plainB 1;
        };
      in
      (x.link "igloo" (proj b) (supply b) frag.value).value.crossings
      != (other.link "igloo" (proj b) (supply b) frag.value).value.crossings;
    expected = true;
  };

  # ── ★ NON-LEAKAGE. The published surface ships NO bound operation, so there is
  #    no path by which a caller reaches `link` without having named an authority,
  #    and no formula a caller reaches by simply omitting the injection.
  flake.tests.crossing-operations.test-published-surface-carries-no-bound-operation = {
    expr = builtins.filter (n: published ? ${n}) [
      "declare"
      "merge"
      "gate"
      "link"
      "close"
      "residue"
      "referenceHashIdentity"
    ];
    expected = [ ];
  };

  flake.tests.crossing-operations.test-control-mkOperations-yields-the-six-operations = {
    expr = builtins.attrNames (published.mkOperations { hashIdentity = _testHashIdentity; }).value;
    expected = [
      "close"
      "declare"
      "gate"
      "link"
      "merge"
      "residue"
    ];
  };

  # No library source carries a minting formula at all — a grep-able invariant,
  # over comment-stripped source so documentation may still name the builtin.
  flake.tests.crossing-operations.test-no-crossing-source-mints-an-identity = {
    expr = builtins.filter (s: genPrelude.hasInfix "hashString" s.code) crossingSources;
    expected = [ ];
  };

  # Control on the SAME instrument in the same run: the scan reaches the sources
  # and the predicate can match. A zero from a scan that reads nothing is not an
  # absence.
  flake.tests.crossing-operations.test-control-the-non-leakage-scan-reaches-the-sources = {
    expr = {
      files = builtins.length crossingSources >= 8;
      predicateCanMatch =
        builtins.length (builtins.filter (s: genPrelude.hasInfix "mkOperations" s.code) crossingSources)
        >= 1;
    };
    expected = {
      files = true;
      predicateCanMatch = true;
    };
  };

  flake.tests.crossing-operations.test-mkOperations-refuses-an-absent-authority = {
    expr = (published.mkOperations { }).refusal.witness.field;
    expected = "hashIdentity";
  };

  flake.tests.crossing-operations.test-mkOperations-refuses-a-non-function-authority = {
    expr = codeOf (published.mkOperations { hashIdentity = "not-a-function"; });
    expected = "declaration-missing-field";
  };

  flake.tests.crossing-operations.test-mkOperations-refusal-is-a-value-not-an-arity-error = {
    expr = (builtins.tryEval (codeOf (published.mkOperations { }))).success;
    expected = true;
  };

  # ── close: the whole path, and the invariant it delivers.
  flake.tests.crossing-operations.test-close-produces-the-adapters-target-unit = {
    expr =
      (pipeline {
        imports = simpleImports;
        bindings = simpleBindings;
      }).value.body.bound;
    expected = {
      base = {
        host = "igloo";
      };
      derived = "igloo";
    };
  };

  # ★ §3.2 PAYLOAD SIDE: over every position the substrate itself wrote, no
  #    function is reachable, transitively.
  flake.tests.crossing-operations.test-what-crosses-is-plain-data = {
    expr =
      reachesFunction
        (pipeline {
          imports = simpleImports;
          bindings = simpleBindings;
        }).value.body.bound;
    expected = false;
  };

  # Control on the SAME predicate in the same run: a planted closure at a
  # substrate-written position must FAIL it. Without this arm the clean result
  # above is indistinguishable from a predicate that cannot match.
  flake.tests.crossing-operations.test-control-a-planted-closure-fails-the-payload-predicate = {
    expr = reachesFunction {
      base = {
        host = "igloo";
      };
      derived = _: "a monitor";
    };
    expected = true;
  };

  # A user-authored function routed through the substrate is NOT substrate
  # structure, and is named as outside the predicate's domain rather than
  # silently counted clean — it crosses, under `Any`.
  flake.tests.crossing-operations.test-control-a-pass-through-user-function-still-crosses = {
    expr =
      builtins.isFunction
        (pipeline {
          imports.fn = imp c.any;
          bindings.fn = plainB (a: a);
        }).value.body.bound.fn;
    expected = true;
  };

  flake.tests.crossing-operations.test-close-refuses-a-forged-token = {
    expr = codeOf (
      x.close "igloo" { } { members = [ ]; } adapter {
        token = null;
      }
    );
    expected = "fragment-token";
  };

  flake.tests.crossing-operations.test-close-refuses-a-malformed-adapter = {
    expr = codeOf (pipeline {
      imports = simpleImports;
      bindings = simpleBindings;
      withAdapter = builtins.removeAttrs adapter [ "interpret" ];
    });
    expected = "adapter-malformed";
  };

  # A required import with no crossing node AND no `satisfiedBy` edge is the
  # completeness check — a QUERY OVER THE EDGE RELATION, not an attribute read.
  flake.tests.crossing-operations.test-close-refuses-an-unsatisfied-required-import = {
    expr = codeOf (pipeline {
      imports.missing = imp c.any;
      bindings = { };
    });
    expected = "required-import-unsatisfied";
  };

  # ...and the `satisfiedBy` EDGE discharges it: the name is the consuming
  # target's own obligation, not the substrate's.
  flake.tests.crossing-operations.test-control-a-satisfiedBy-edge-discharges-the-requirement = {
    expr = x.isOk (pipeline {
      imports.selfSupplied = (imp c.any) // {
        satisfiedBy = "igloo";
      };
      bindings = { };
    });
    expected = true;
  };

  flake.tests.crossing-operations.test-close-refuses-an-incoherent-fleet = {
    expr = codeOf (pipeline {
      imports.peer = imp c.any;
      bindings.peer = termedB (t.readFrom "iceberg" [ "x" ]);
      members = [ "igloo" ];
    });
    expected = "linkset-incoherent";
  };

  flake.tests.crossing-operations.test-close-refuses-a-violated-contract = {
    expr = codeOf (pipeline {
      imports.n = imp (c.prop "isInt");
      bindings.n = plainB "not-an-int";
    });
    expected = "contract-violated";
  };

  flake.tests.crossing-operations.test-control-close-admits-a-satisfied-contract = {
    expr = x.isOk (pipeline {
      imports.n = imp (c.prop "isInt");
      bindings.n = plainB 1;
    });
    expected = true;
  };

  # ── ★ F4's ARM: a CONTRACTED binding on the TARGET-INVOKED channel. Its value
  #    exists only once the target hands back its args, so the check cannot run
  #    substrate-side and no lazy-monitor construction delivers the invariant. It
  #    refuses BY NAME rather than crossing unchecked, and the witness carries the
  #    two fields that distinguish THIS branch from the obtainability branch
  #    beside it: the NAME and the REASON.
  #
  #    The producer is the CONSUMING target deliberately — that is what makes the
  #    congruence verdict false and routes the name to `wrapFn`. With a peer
  #    producer it never reaches here; it refuses one step earlier, at placement.
  flake.tests.crossing-operations.test-contracted-target-invoked-binding-refuses-by-name = {
    expr =
      (pipeline {
        imports.opaque = imp (c.prop "isInt");
        bindings.opaque = wrappedB "igloo" (_: 1);
        members = [ "igloo" ];
      }).refusal.witness;
    expected = {
      name = "opaque";
      constructor = "Wrapped";
      reason = "a contract cannot be checked substrate-side on a target-time value";
      missingCarrier = "ProducerScope";
    };
  };

  # The control that keeps the row honest: the same binding UNCONTRACTED crosses,
  # so the refusal is about the contract and not about the constructor.
  flake.tests.crossing-operations.test-control-the-same-binding-uncontracted-crosses = {
    expr = x.isOk (pipeline {
      imports.opaque = imp c.any;
      bindings.opaque = wrappedB "igloo" (_: 1);
      members = [ "igloo" ];
    });
    expected = true;
  };

  # ── ★ BOUND (b) ON THE FLOOR'S PERMISSIVE NARROWING: `close` STILL REFUSES THE
  #    UNIT. The query goes blind — E(u) is empty and `linked(u)` is wrongly true
  #    for this unit — but the PLACEMENT decision reads the analysis, which is
  #    mark-blind, so the binding is still Substrate-placed and still refuses by
  #    name. A unit that is linked-wrongly-true therefore CANNOT silently cross
  #    carrying an unresolvable reference; it fails one operation later, with a
  #    witness. Bound (a) — non-transitivity — is armed in crossing-linkset.nix.
  flake.tests.crossing-operations.test-a-linked-wrongly-true-unit-still-refuses-at-close = {
    expr =
      let
        hidden = x.binding.termed {
          term = t.readFrom "iceberg" [ "x" ];
          mark = x.mark.floor;
        };
        crossingNode = {
          binding = "hidden";
          import = "hidden";
          target = "igloo";
          record = hidden;
        };
      in
      {
        # the query is blind...
        linkedWronglyTrue = x.linked {
          unit = "igloo";
          crossings = [ crossingNode ];
          projection = proj { inherit hidden; };
        };
        # ...and the unit still does not cross.
        closeStillRefuses = codeOf (pipeline {
          imports.hidden = imp c.any;
          bindings.hidden = hidden;
          members = [ "igloo" ];
        });
      };
    expected = {
      linkedWronglyTrue = true;
      closeStillRefuses = "value-not-obtainable";
    };
  };

  # ── ★★ POPULATION P-B, END TO END, AND THIS IS ITS ONLY SUCH COVERAGE. Every
  #    other P-B cell calls `builtins.scopedImport` directly and therefore
  #    measures Nix rather than this surface; this one drives the value through
  #    `close` and `substrateValue`, which is the path a consumer actually gets.
  #
  #    THE PRODUCER IS THE CONSUMING TARGET BECAUSE IT HAS TO BE. After taken
  #    default #20 a Scoped binding's demand set is always APPROX, so a PEER
  #    producer refuses at placement and the TARGET-INVOKED CHANNEL IS THE ONLY
  #    REMAINING PATH FOR THE WHOLE P-B POPULATION — which is what makes this
  #    single cell that population's sole end-to-end coverage.
  #
  #    It asserts the crossed VALUE, not that a call happened: override the
  #    declared scope inside `substrateValue` and `value` becomes the override, so
  #    the cell goes red. `viaBaseScope` rides along because the base scope
  #    staying reachable is the stated LIMIT of this population's closure claim,
  #    and it is worth measuring on the real path and not only on a direct call.
  flake.tests.crossing-operations.test-scoped-binding-crosses-carrying-its-supplied-scope = {
    expr =
      let
        r = pipeline {
          imports.fromFile = imp c.any;
          bindings.fromFile = x.binding.scoped {
            file = ./_crossing-scoped-body.nix;
            scope = {
              supplied = "FROM-SCOPE";
            };
            producer = "igloo";
            mark = x.mark.open;
          };
          members = [ "igloo" ];
        };
      in
      (r.value.body.wrapFnOf { }).bound.fromFile;
    expected = {
      value = "FROM-SCOPE";
      viaBaseScope = 2;
    };
  };

  # ── ★ F2's ARM: an UNCONTRACTED name on the target-invoked channel whose value
  #    is not obtainable substrate-side. An earlier revision guarded only the
  #    CONTRACTED path here and then read `.value` off the result unguarded, so
  #    this population produced an uncatchable `attribute 'value' missing` INSIDE
  #    the wrapFn closure, at target force time, carrying no name of ours. It must
  #    now be a tagged refusal from `close`.
  flake.tests.crossing-operations.test-uncontracted-unobtainable-invoked-value-refuses-by-name = {
    expr =
      let
        r = pipeline {
          imports.peer = imp c.any;
          bindings.peer = termedB (t.readFrom "igloo" [ "x" ]);
          members = [ "igloo" ];
        };
      in
      {
        code = codeOf r;
        carrier = r.refusal.witness.missingCarrier;
      };
    expected = {
      code = "value-not-obtainable";
      carrier = "TargetId -> config";
    };
  };

  # ...and it is a VALUE, reachable without forcing anything that aborts. The
  # seeded probe wrapped the old behaviour in `tryEval` and the failure escaped
  # it; this asserts the tagged shape directly, which the old behaviour could not
  # have produced.
  flake.tests.crossing-operations.test-that-refusal-is-tagged-not-an-uncatchable-abort = {
    expr =
      let
        r = pipeline {
          imports.peer = imp c.any;
          bindings.peer = termedB (t.readFrom "igloo" [ "x" ]);
          members = [ "igloo" ];
        };
      in
      {
        isRefusal = x.isRefusal r;
        catchable = (builtins.tryEval (builtins.deepSeq r.refusal r.refusal.code)).success;
      };
    expected = {
      isRefusal = true;
      catchable = true;
    };
  };

  flake.tests.crossing-operations.test-contracted-readFrom-term-refuses-with-the-missing-carrier = {
    expr =
      (pipeline {
        imports.peer = imp (c.prop "isInt");
        bindings.peer = termedB (t.readFrom "iceberg" [ "x" ]);
        members = [
          "igloo"
          "iceberg"
        ];
      }).refusal.witness.missingCarrier;
    expected = "TargetId -> config";
  };

  # An UNCONTRACTED Wrapped binding whose demand is the CONSUMING target is
  # inadmissible for substrate placement, so it crosses on the target-invoked
  # channel with its body applied to the TargetArgs as its ProducerScope. The
  # substrate builds the wrapper and applies it — which is what bounds the
  # argument channel and bounds nothing lexical.
  flake.tests.crossing-operations.test-control-an-uncontracted-wrapped-binding-crosses = {
    expr =
      let
        r = pipeline {
          imports.opaque = imp c.any;
          bindings.opaque = wrappedB "igloo" (scope: scope.fromTarget);
          members = [ "igloo" ];
        };
      in
      (r.value.body.wrapFnOf { fromTarget = "AT-TARGET-TIME"; }).bound.opaque;
    expected = "AT-TARGET-TIME";
  };

  # ★ A Wrapped binding demanding a PEER passes the congruence predicate — the
  # peer is not the consuming target — but only over a demand set that
  # UNDER-APPROXIMATES, so the pass proves nothing and substrate placement is
  # refused on the exactness requirement. It refuses one step BEFORE the carrier
  # gap it used to hit: the analysis limit is the earlier and more actionable
  # fact, and the supplier can act on it.
  flake.tests.crossing-operations.test-approx-peer-demanding-binding-refuses-at-placement = {
    expr =
      let
        r = pipeline {
          imports.opaque = imp c.any;
          bindings.opaque = wrappedB "iceberg" (_: 1);
          members = [
            "igloo"
            "iceberg"
          ];
        };
      in
      {
        code = codeOf r;
        inherit (r.refusal.witness) deltaExact;
      };
    expected = {
      code = "substrate-placement-inexact-demand";
      deltaExact = "APPROX";
    };
  };

  # The control: the same shape with an EXACT demand set on a peer IS admitted at
  # Substrate and crosses. Without it, the refusal above is indistinguishable
  # from a rule that refuses every peer-demanding binding.
  flake.tests.crossing-operations.test-control-an-exact-peer-demanding-binding-is-substrate-placed = {
    expr =
      (pipeline {
        imports.peer = imp c.any;
        bindings.peer = termedB (t.attrs { v = t.lit 1; });
        members = [
          "igloo"
          "iceberg"
        ];
      }).value.body.bound.peer;
    expected = {
      v = 1;
    };
  };

  # ── the body-count row, DERIVED FROM OPACITY rather than invented: `Body` is
  #    target-owned and produced or consumed ONLY by an Adapter, so the substrate
  #    cannot combine two. A merged multi-body fragment fails LOUDLY here rather
  #    than having one of its bodies silently dropped.
  flake.tests.crossing-operations.test-close-refuses-a-multi-body-fragment = {
    expr =
      let
        fa = (x.declare (sig { a = imp c.any; }) { body = "left"; }).value;
        fb = (x.declare (sig { b = imp c.any; }) { body = "right"; }).value;
        merged = (x.merge fa fb).value;
      in
      codeOf (x.close "igloo" { } { members = [ ]; } adapter merged);
    expected = "close-body-count";
  };

  # ── the gate's select row.
  flake.tests.crossing-operations.test-close-refuses-a-select-outside-the-enum = {
    expr =
      let
        g =
          (x.gate {
            enum = [ "a" ];
            select = x.selectTerm.literal "not-a-key";
            branches.a = (x.declare (sig { }) { kind = "body"; }).value;
          }).value;
      in
      codeOf (x.close "igloo" { } { members = [ ]; } adapter g);
    expected = "gate-select-outside-enum";
  };

  flake.tests.crossing-operations.test-control-close-admits-a-select-inside-the-enum = {
    expr =
      let
        g =
          (x.gate {
            enum = [ "a" ];
            select = x.selectTerm.literal "a";
            branches.a = (x.declare (sig { }) { kind = "body"; }).value;
          }).value;
      in
      x.isOk (x.close "igloo" { } { members = [ ]; } adapter g);
    expected = true;
  };

  # ── the TargetUnit is OPAQUE: `close` returns exactly what the adapter built
  #    and does not read its structure. A sentinel carrying a throwing field
  #    survives `close` untouched — which is what its opacity IS.
  flake.tests.crossing-operations.test-target-unit-is-returned-unread = {
    expr =
      let
        opaqueAdapter = adapter // {
          wrapUnit = _: _: {
            marker = "opaque";
            neverRead = throw "close read the TargetUnit";
          };
        };
        r = pipeline {
          imports = simpleImports;
          bindings = simpleBindings;
          withAdapter = opaqueAdapter;
        };
      in
      r.value.marker;
    expected = "opaque";
  };

  # ── §3.4's discipline: a refusal is a TAGGED VALUE, never a throw, because
  #    `tryEval` cannot catch every failure form and a thrown refusal is not
  #    reliably recoverable.
  flake.tests.crossing-operations.test-every-refusal-carries-code-blame-and-witness = {
    expr =
      let
        r = pipeline {
          imports.n = imp (c.prop "isInt");
          bindings.n = plainB "not-an-int";
        };
      in
      builtins.attrNames r.refusal;
    expected = [
      "blamed"
      "code"
      "witness"
    ];
  };

  flake.tests.crossing-operations.test-refusals-are-values-not-throws = {
    expr =
      (builtins.tryEval (
        codeOf (pipeline {
          imports.n = imp (c.prop "isInt");
          bindings.n = plainB "not-an-int";
        })
      )).success;
    expected = true;
  };
}

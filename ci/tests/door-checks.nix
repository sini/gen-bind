# THE DOORS (den-hoag-7gp66 P1, then P2 — `prelude.door`) — every published step of gen-bind taking a
# record catches its own violations.
#
# A native closed formal (`{ class, module, identity }:`) aborts UNCATCHABLY on an unknown or a
# missing argument — not even `builtins.tryEval` sees it, which is ADR-0025 item 1's named defect.
# Every record step in `_door-table.nix` is a `prelude.door`, so the same violations are NAMED and
# CATCHABLE. Each cell `seq`s the STEP applied to its argument and nothing else (no later argument,
# no field read), so a refusal is observed where the step is applied — which is also the whole of
# what the P1 lazy-door fix (`door-application-strictness`) pinned for seven doors one by one: the
# door construction forces its check at application, for every row. Covered, per row:
#   - an OPTIONS step admits `{ }`, and refuses an unknown option and a non-attrset (G1/G4)
#   - a RECORD step admits its good record, refuses a missing field (D2) and a non-attrset, and
#     admits a field no step names (G2, R5's stated price; G10-ctl on the guarded rows)
#   - a record behind an options step refuses each of that step's own names (`optionsStep`, G10)
#   - every step publishes its row as its contract, as data and through the functor-aware reader (D3)
#   - a non-default option reaches the partially applied door and moves the answer (G3)
#   - a record whose row carries `typo` refuses that misspelling written in place of a field (den-hoag-ekum1)
#   - a CLOSED record step (den-hoag-ekum1) admits its good record, and refuses a field outside its closed
#     set and a non-attrset — each of which its native closed formal aborted on uncatchably — and, where
#     it has required fields (den-hoag-54al9), refuses each one missing
#
# `tests` pins what each step ADMITS/REFUSES and that every refusal is catchable; `testsError` pins
# WHICH refusal fired and that it names the door first (R6).
{
  genBind,
  genScope,
  prelude,
  lib,
  ...
}:
let
  F = import ./_door-table.nix { inherit genBind genScope lib; };

  applied = step: r: (builtins.tryEval (builtins.seq (step r) true)).success;
  unknown = {
    unknownField = 1;
  };
  each = f: builtins.mapAttrs (_: f);
  flag = v: names: lib.genAttrs names (_: v);
  guarded = lib.filterAttrs (_: r: r ? guardedBy) F.records;
  misspellable = lib.filterAttrs (_: r: r ? typo) F.records;
  closedRequiring = lib.filterAttrs (_: r: r ? required) F.closed;

  # Every options door on the published surface (depth <= 2), read off its `__contract` rather than
  # a hand list, so a new one is seen whether or not a row was written for it.
  isDoor = v: builtins.isAttrs v && v ? __contract && v ? __functor;
  isOptionsDoor = v: isDoor v && !v.__contract.open && v.__contract.required == [ ];
  surfaceOptionDoors =
    builtins.filter (n: isOptionsDoor genBind.${n}) (builtins.attrNames genBind)
    ++
      builtins.concatMap
        (
          ns:
          map (n: "${ns}.${n}") (
            builtins.filter (n: isOptionsDoor genBind.${ns}.${n}) (builtins.attrNames genBind.${ns})
          )
        )
        [
          "contract"
          "crossing"
        ];

  # The bytes. `[.]`, `[(]` and `[)]` neutralise the metacharacters, as in gen-prelude's goldens.
  quoted = names: lib.concatMapStringsSep ", " (n: "'${n}'") names;
  name = key: "gen-bind[.]${builtins.replaceStrings [ "." ] [ "[.]" ] key}";
  pin = key: msg: {
    type = "ThrownError";
    msg = "^${name key}: ${msg}$";
  };
  optionGoldens = key: row: {
    "test-${key}-unknown-option-message" = {
      expr = row.door unknown;
      expectedError = pin key "'unknownField' is not an option of this door; the options are closed [(]accepted: ${quoted row.optional}[)] [(]in prelude[.]checkOptions[)]";
    };
  };
  recordGoldens =
    key: row:
    let
      req = "[(]required: ${quoted row.required}[)] [(]in prelude[.]checkRequired[)]";
    in
    {
      "test-${key}-missing-required-field-message" = {
        expr = row.step (builtins.removeAttrs row.good [ row.drop ]);
        expectedError = pin key "required field '${row.drop}' is missing ${req}";
      };
      "test-${key}-non-attrset-argument-message" = {
        expr = row.step 1;
        expectedError = pin key "the argument must be an attrset, not a int ${req}";
      };
    }
    // lib.optionalAttrs (row ? typo) {
      "test-${key}-misspelt-field-message" = {
        expr = row.step (builtins.removeAttrs row.good [ row.drop ] // { ${row.typo} = 1; });
        expectedError = pin key "required field '${row.drop}' is missing ${req}";
      };
    }
    // lib.optionalAttrs (row ? guardedBy) (
      let
        o = builtins.head F.options.${row.guardedBy}.optional;
      in
      {
        "test-${key}-misplaced-option-message" = {
          expr = row.step (row.good // { ${o} = null; });
          expectedError = pin key "'${o}' is an option of ${name row.guardedBy}, not a field of this record [(]in prelude[.]checkGuarded[)]";
        };
      }
    );
  closedGoldens =
    key: row:
    {
      "test-${key}-extra-field-message" = {
        expr = row.step (row.good // { ${row.extra} = 1; });
        expectedError = pin key "'${row.extra}' is not an option of this door; the options are closed [(]accepted: ${quoted row.accepted}[)] [(]in prelude[.]checkOptions[)]";
      };
    }
    // lib.optionalAttrs (row ? required) (
      lib.listToAttrs (
        map (f: {
          name = "test-${key}-missing-${f}-message";
          value = {
            expr = row.step (builtins.removeAttrs row.good [ f ]);
            expectedError = pin key "required field '${f}' is missing [(]required: ${quoted row.required}[)] [(]in prelude[.]checkRequired[)]";
          };
        }) row.required
      )
    );
in
{
  flake.tests.door-checks = {
    # ★ LIVE CONTROLS FOR THE WHOLE SUITE: `tryEval` catches an ordinary throw, a non-throwing value
    # answers, and a deliberately LAZY door — its check in a `let` behind a value that never reads it
    # — reads as admitting, so the `false` cells below are not vacuously strict.
    test-control-tryeval-catches-an-ordinary-throw = {
      expr = applied (_: throw "control probe, not this suite's subject") null;
      expected = false;
    };
    test-control-tryeval-answers-a-non-throwing-value = {
      expr = applied (x: x) 1;
      expected = true;
    };
    test-control-a-lazy-construction-reads-as-admitting = {
      expr = applied (
        args:
        let
          _checked = if args ? a then args else throw "missing a";
        in
        {
          x = 1;
        }
      ) { };
      expected = true;
    };
    # The table is the subject; a row dropped from it would drop its cells silently.
    test-door-table-rows = {
      expr = {
        closed = builtins.attrNames F.closed;
        options = builtins.attrNames F.options;
        records = builtins.attrNames F.records;
      };
      expected = {
        options = [
          "buildSignature"
          "configGate"
          "contract.mk"
          "crossEval"
          "resolveThunks"
          "wrap"
          "wrapAll"
          "wrapIdentity"
        ];
        closed = [
          "composeWith"
          "crossing.mkHostedTerminal.adapter"
        ];
        records = [
          "buildSignature"
          "crossing.binding.plain"
          "crossing.binding.scoped"
          "crossing.binding.termed"
          "crossing.binding.wrapped"
          "crossing.coherence"
          "crossing.environment"
          "crossing.linked"
          "crossing.mkHostedTerminal"
          "crossing.placement"
          "mkMergeValidator"
          "resolveThunks"
        ];
      };
    };

    test-the-empty-options-are-admitted-at-every-options-step = {
      expr = each (d: applied d.door { }) F.options;
      expected = each (_: true) F.options;
    };
    # G1/G4: refused when the options are applied, before any operand or record.
    test-an-unknown-option-is-refused-catchably-at-every-options-step = {
      expr = each (d: applied d.door unknown) F.options;
      expected = each (_: false) F.options;
    };
    test-a-non-attrset-options-argument-is-refused-catchably = {
      expr = each (d: applied d.door 1) F.options;
      expected = each (_: false) F.options;
    };
    # D3: the contract is published as data, and the functor-aware reader reads the same map.
    test-every-options-step-publishes-the-row-as-its-contract = {
      expr = each (d: {
        inherit (d.door.__contract) optional required open;
        functionArgs = prelude.functionArgs d.door;
      }) F.options;
      expected = each (d: {
        inherit (d) optional;
        required = [ ];
        open = false;
        functionArgs = flag true d.optional;
      }) F.options;
    };
    # G3: a non-default option reaches the partially applied door (agrees with the full call) and
    # moves the answer (differs from `{ }`).
    test-a-non-default-option-reaches-the-partial-application = {
      expr = each (
        d:
        let
          f1 = d.door d.on;
        in
        {
          agrees = d.run f1 == d.run (d.door d.on);
          differs = d.run f1 != d.run (d.door { });
        }
      ) F.options;
      expected = each (_: {
        agrees = true;
        differs = true;
      }) F.options;
    };

    test-the-good-record-is-admitted-at-every-record-step = {
      expr = each (d: applied d.step d.good) F.records;
      expected = each (_: true) F.records;
    };
    # D2, at the step's own application.
    test-a-missing-field-is-refused-catchably = {
      expr = each (d: applied d.step (builtins.removeAttrs d.good [ d.drop ])) F.records;
      expected = each (_: false) F.records;
    };
    test-an-empty-record-is-refused-catchably = {
      expr = each (d: applied d.step { }) F.records;
      expected = each (_: false) F.records;
    };
    test-a-non-attrset-record-is-refused-catchably = {
      expr = each (d: applied d.step 1) F.records;
      expected = each (_: false) F.records;
    };
    # G2 / R5, and G10-ctl on the guarded rows: a field no step names is admitted.
    test-an-extra-field-is-admitted-at-every-record-step = {
      expr = each (d: applied d.step (d.good // unknown)) F.records;
      expected = each (_: true) F.records;
    };
    # G10: each of the options step's own names (from that step's `__contract`), given on the record
    # instead, is refused. The answer is the names ADMITTED.
    test-every-option-is-refused-at-every-guarded-record-step = {
      expr = each (
        d:
        builtins.filter (o: applied d.step (d.good // { ${o} = null; })) (
          F.options.${d.guardedBy}.door.__contract.optional
        )
      ) guarded;
      expected = each (_: [ ]) guarded;
    };
    # PARITY (den-hoag-ak8va, gate C1; gating): every guarded record step is published AS DATA by
    # its options step, `__contract.next` (past a positional node), and the nest, read without
    # application, equals the contract the record step answers with.
    test-every-guarded-record-step-is-its-options-step-next = {
      expr = each (
        d:
        let
          recordNext = c: if c != null && c ? positional then recordNext c.next else c;
        in
        recordNext (F.options.${d.guardedBy}.door.__contract.next or null) == d.step.__contract
      ) guarded;
      expected = each (_: true) guarded;
    };
    # Every options door on the surface is classified: a chained one has a guarded record row, and
    # the rest are named as not chained. `surfaceOptionDoors` is pinned as the enumerator's live
    # control: a walk that found nothing would leave `unclassified` empty too.
    test-every-options-door-on-the-surface-is-classified = {
      expr = {
        unclassified = builtins.filter (
          n: !(guarded ? ${n}) && !(builtins.elem n F.notChained)
        ) surfaceOptionDoors;
        inherit surfaceOptionDoors;
      };
      expected = {
        unclassified = [ ];
        surfaceOptionDoors = [
          "buildSignature"
          "configGate"
          "crossEval"
          "resolveThunks"
          "wrap"
          "wrapAll"
          "wrapIdentity"
          "contract.mk"
        ];
      };
    };
    test-every-record-step-publishes-the-row-as-its-contract = {
      expr = each (d: {
        inherit (d.step.__contract) required open;
        functionArgs = prelude.functionArgs d.step;
      }) F.records;
      expected = each (d: {
        inherit (d) required;
        open = true;
        functionArgs = flag false d.required;
      }) F.records;
    };
    # den-hoag-ekum1: each refusal below was an UNCATCHABLE abort under the native closed formal
    # (`called with unexpected argument` / `called without required argument`). A misspelling written
    # IN PLACE of a required field leaves that field missing, so an open record refuses it.
    test-a-misspelling-in-place-of-a-field-is-refused-catchably-at-every-record-step = {
      expr = each (
        d: applied d.step (builtins.removeAttrs d.good [ d.drop ] // { ${d.typo} = 1; })
      ) misspellable;
      expected = each (_: false) misspellable;
    };
    # The closed steps' closure oracle: a field outside the closed set, beside good ones, is refused.
    test-the-good-record-is-admitted-at-every-closed-step = {
      expr = each (d: applied d.step d.good) F.closed;
      expected = each (_: true) F.closed;
    };
    test-an-extra-field-is-refused-catchably-at-every-closed-step = {
      expr = each (d: applied d.step (d.good // { ${d.extra} = 1; })) F.closed;
      expected = each (_: false) F.closed;
    };
    test-a-non-attrset-record-is-refused-catchably-at-every-closed-step = {
      expr = each (d: applied d.step 1) F.closed;
      expected = each (_: false) F.closed;
    };
    # den-hoag-54al9: each required field of a closed step, dropped in turn, is refused. The answer is
    # the fields whose absence was ADMITTED; each was an uncatchable native abort before the door.
    test-each-missing-required-field-is-refused-catchably-at-every-closed-step = {
      expr = each (
        d: builtins.filter (f: applied d.step (builtins.removeAttrs d.good [ f ])) d.required
      ) closedRequiring;
      expected = each (_: [ ]) closedRequiring;
    };
  };

  flake.testsError.door-checks =
    lib.concatMapAttrs optionGoldens F.options
    // lib.concatMapAttrs recordGoldens F.records
    // lib.concatMapAttrs closedGoldens F.closed;
}

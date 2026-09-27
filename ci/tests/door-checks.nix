# Door checks (den-hoag-7gp66, P1 unit 7) — every closed door this unit converted
# (identity.nix, strip.nix, arg-env.nix, signature.nix, contract.nix,
# merge-strategy.nix, thunk.nix, crossing-linkset.nix, crossing-adapter.nix,
# crossing-adapter-set.nix) now takes `prelude.checkOptions`/`checkRequired`
# (gen-prelude 0ac7b66) instead of a bare `{ ... }:` destructure, so an unknown
# option or a missing field is a NAMED, CATCHABLE refusal rather than Nix's own
# uncatchable "called with unexpected argument".
#
# `tests` pins what each door ADMITS/REFUSES and that every refusal is catchable
# (`tryEval`, ADR-0025 item 1) — the same split gen-prelude's own `ci/tests/door.nix`
# uses for `checkOptions`/`checkRequired` themselves. `testsError` pins WHICH
# refusal fired and that it names the door first (R6).
#
# A MIXED door (required + optional fields, closed overall, §v1.2) gets a
# missing-field cell and an unknown-option cell. A RECORD door (all fields
# required, open — R5's width subtyping) gets an extra-field-admitted cell and a
# missing-field cell; it has no `checkOptions` layer, so there is no "unknown
# option" for it to refuse. A door never gets both halves: it is either open or
# closed, never both, so a door that refused every fixture here would red the
# admission cells and one that admitted every fixture would red the refusal
# cells (mirroring `door.nix`'s own header note).
#
# Out of scope, by the same depth-<=2 top-level-export census the build report
# for this unit used: `composeWith` (`wrap.nix`, positional, no attrset door),
# `crossing.linked` (delegates to `environment` unmodified — see that door's own
# comment in `crossing-linkset.nix`), and `mkHostedTerminal`'s nested `.adapter`
# (depth 3+, its own pre-existing hand-rolled catchable `unknownCarriageMembers`
# check).
{ genBind, lib, ... }:
let
  inherit (genBind)
    wrapIdentity
    stripBindingArgs
    adaptArgs
    crossEval
    configGate
    buildSignature
    resolveThunks
    mkMergeValidator
    ;
  inherit (genBind.contract) mk;
  inherit (genBind.crossing)
    environment
    coherence
    placement
    mkHostedTerminal
    mkFlakeTerminal
    ;

  refused = v: !(builtins.tryEval (builtins.deepSeq v v)).success;

  pin = door: msg: {
    type = "ThrownError";
    msg = "^${door}: ${msg}$";
  };
  missingPin =
    door: field: required:
    pin door "required field '${field}' is missing [(]required: ${required}[)] [(]in prelude[.]checkRequired[)]";
  unknownPin =
    door: accepted:
    pin door "'colr' is not an option of this door; the options are closed [(]accepted: ${accepted}[)] [(]in prelude[.]checkOptions[)]";
in
{
  flake.tests = {
    # ── mixed doors: missing field / unknown option, both refused catchably ──
    wrapIdentity = {
      test-missing-required-field-refused-catchably = {
        expr = refused (wrapIdentity {
          class = "nixos";
          module = { };
        });
        expected = true;
      };
      test-unknown-option-refused-catchably = {
        expr = refused (wrapIdentity {
          class = "nixos";
          module = { };
          identity = "x";
          colr = 1;
        });
        expected = true;
      };
    };

    crossEval = {
      test-missing-required-field-refused-catchably = {
        expr = refused (crossEval { inherit lib; }).config;
        expected = true;
      };
      test-unknown-option-refused-catchably = {
        expr =
          refused
            (crossEval {
              inherit lib;
              module = { };
              colr = 1;
            }).config;
        expected = true;
      };
    };

    configGate = {
      test-missing-required-field-refused-catchably = {
        expr = refused ((configGate { gate = _: true; }) { inherit lib; }).config;
        expected = true;
      };
      test-unknown-option-refused-catchably = {
        expr =
          refused
            (
              (configGate {
                gate = _: true;
                module = { };
                colr = 1;
              })
                { inherit lib; }
            ).config;
        expected = true;
      };
    };

    buildSignature = {
      test-missing-required-field-refused-catchably = {
        expr = refused (buildSignature {
          module = { };
          bindings = { };
          defaultMergeStrategy = "bind-wins";
        });
        expected = true;
      };
      test-unknown-option-refused-catchably = {
        expr = refused (buildSignature {
          module = { };
          bindings = { };
          defaultMergeStrategy = "bind-wins";
          mergeStrategies = { };
          colr = 1;
        });
        expected = true;
      };
    };

    contract-mk = {
      test-missing-required-field-refused-catchably = {
        expr = refused (mk {
          message = "x";
        });
        expected = true;
      };
      test-unknown-option-refused-catchably = {
        expr = refused (mk {
          check = _: true;
          colr = 1;
        });
        expected = true;
      };
    };

    resolveThunks = {
      test-missing-required-field-refused-catchably = {
        expr = refused (resolveThunks {
          config = { };
          ctx = { };
          thunkArgNames = [ ];
        });
        expected = true;
      };
      test-unknown-option-refused-catchably = {
        expr = refused (resolveThunks {
          config = { };
          ctx = { };
          thunkArgNames = [ ];
          bindings = { };
          colr = 1;
        });
        expected = true;
      };
    };

    mkFlakeTerminal = {
      test-missing-required-field-refused-catchably = {
        expr = refused (
          (mkFlakeTerminal {
            evalFlakeModule = a: m: {
              config.flake = {
                seen = a;
                inherit (m) systems;
              };
            };
            self = "s";
          }).adapter.wrapUnit
            [ ]
            [ ]
        );
        expected = true;
      };
      test-unknown-option-refused-catchably = {
        expr = refused (
          (mkFlakeTerminal {
            evalFlakeModule = a: m: {
              config.flake = {
                seen = a;
                inherit (m) systems;
              };
            };
            inputs = { };
            self = "s";
            colr = 1;
          }).adapter.wrapUnit
            [ ]
            [ ]
        );
        expected = true;
      };
    };

    # ── record doors: extra field admitted, missing field refused catchably ──
    stripBindingArgs = {
      test-extra-field-on-a-record-is-admitted = {
        expr = stripBindingArgs {
          module = { };
          bindingNames = [ ];
          colr = 1;
        };
        expected = { };
      };
      test-missing-required-field-refused-catchably = {
        expr = refused (stripBindingArgs {
          module = { };
        });
        expected = true;
      };
    };

    adaptArgs = {
      test-extra-field-on-a-record-is-admitted = {
        expr = builtins.isFunction (adaptArgs {
          adapt = _: { };
          module = { };
          colr = 1;
        });
        expected = true;
      };
      test-missing-required-field-refused-catchably = {
        expr = refused ((adaptArgs { adapt = _: { }; }) { }).imports;
        expected = true;
      };
    };

    mkMergeValidator = {
      test-extra-field-on-a-record-is-admitted = {
        expr = builtins.isFunction (mkMergeValidator {
          resolvePolicy = _: "bind-wins";
          boundArgNames = [ ];
          provenance = { };
          colr = 1;
        });
        expected = true;
      };
      test-missing-required-field-refused-catchably = {
        expr =
          refused
            (
              (mkMergeValidator {
                resolvePolicy = _: "bind-wins";
                boundArgNames = [ "a" ];
              })
                {
                  config._module.args = {
                    a = 1;
                  };
                }
            ).warnings;
        expected = true;
      };
    };

    crossing-environment = {
      test-extra-field-on-a-record-is-admitted = {
        expr = environment {
          unit = "igloo";
          crossings = [ ];
          projection = { };
          colr = 1;
        };
        expected = [ ];
      };
      test-missing-required-field-refused-catchably = {
        expr = refused (environment {
          unit = "igloo";
          crossings = [ ];
        });
        expected = true;
      };
    };

    crossing-coherence = {
      test-extra-field-on-a-record-is-admitted = {
        expr = coherence {
          unit = "igloo";
          crossings = [ ];
          projection = { };
          linkset = {
            members = [ ];
          };
          colr = 1;
        };
        expected = {
          __crossingResult = "ok";
          value = [ ];
        };
      };
      test-missing-required-field-refused-catchably = {
        expr = refused (coherence {
          unit = "igloo";
          crossings = [ ];
          projection = { };
        });
        expected = true;
      };
    };

    crossing-placement = {
      test-extra-field-on-a-record-is-admitted = {
        expr = placement {
          staticityAdmissible = true;
          deltaExact = "EXACT";
          adapter = {
            bindFormals = _: _: { };
          };
          name = "db";
          colr = 1;
        };
        expected = {
          __crossingResult = "ok";
          value = {
            channel = "Formals";
            time = "Substrate";
          };
        };
      };
      test-missing-required-field-refused-catchably = {
        expr = refused (placement {
          staticityAdmissible = true;
          deltaExact = "EXACT";
          adapter = {
            bindFormals = _: _: { };
          };
        });
        expected = true;
      };
    };

    crossing-mkHostedTerminal = {
      test-extra-field-on-a-record-is-admitted = {
        expr =
          builtins.isFunction
            (mkHostedTerminal {
              evaluator = _: { };
              locateConfig = _: { };
              class = "host";
              colr = 1;
            }).adapter;
        expected = true;
      };
      test-missing-required-field-refused-catchably = {
        expr = refused (mkHostedTerminal {
          evaluator = _: { };
          locateConfig = _: { };
        });
        expected = true;
      };
    };
  };

  # Every refusal names the door first and the construct last (R6).
  flake.testsError = {
    door-checks-mixed = {
      test-wrapIdentity-missing-field-named = {
        expr = wrapIdentity {
          class = "nixos";
          module = { };
        };
        expectedError = missingPin "gen-bind[.]wrapIdentity" "identity" "'class', 'module', 'identity'";
      };
      test-wrapIdentity-unknown-option-named = {
        expr = wrapIdentity {
          class = "nixos";
          module = { };
          identity = "x";
          colr = 1;
        };
        expectedError = unknownPin "gen-bind[.]wrapIdentity" "'class', 'module', 'identity', 'isAnon'";
      };

      test-crossEval-missing-field-named = {
        expr = (crossEval { inherit lib; }).config;
        expectedError = missingPin "gen-bind[.]crossEval" "module" "'lib', 'module'";
      };
      test-crossEval-unknown-option-named = {
        expr =
          (crossEval {
            inherit lib;
            module = { };
            colr = 1;
          }).config;
        expectedError = unknownPin "gen-bind[.]crossEval" "'lib', 'module', 'specialArgs', 'moduleArgs', 'absorb'";
      };

      test-configGate-missing-field-named = {
        expr = ((configGate { gate = _: true; }) { inherit lib; }).config;
        expectedError = missingPin "gen-bind[.]configGate" "module" "'gate', 'module'";
      };
      test-configGate-unknown-option-named = {
        expr =
          (
            (configGate {
              gate = _: true;
              module = { };
              colr = 1;
            })
              { inherit lib; }
          ).config;
        expectedError = unknownPin "gen-bind[.]configGate" "'gate', 'module', 'adapt', 'absorb'";
      };

      test-buildSignature-missing-field-named = {
        expr = buildSignature {
          module = { };
          bindings = { };
          defaultMergeStrategy = "bind-wins";
        };
        expectedError =
          missingPin "gen-bind[.]buildSignature" "mergeStrategies"
            "'module', 'bindings', 'defaultMergeStrategy', 'mergeStrategies'";
      };
      test-buildSignature-unknown-option-named = {
        expr = buildSignature {
          module = { };
          bindings = { };
          defaultMergeStrategy = "bind-wins";
          mergeStrategies = { };
          colr = 1;
        };
        expectedError = unknownPin "gen-bind[.]buildSignature" "'module', 'bindings', 'defaultMergeStrategy', 'mergeStrategies', 'provenance', 'vocabulary'";
      };

      test-contractMk-missing-field-named = {
        expr = mk { message = "x"; };
        expectedError = missingPin "gen-bind[.]contract[.]mk" "check" "'check'";
      };
      test-contractMk-unknown-option-named = {
        expr = mk {
          check = _: true;
          colr = 1;
        };
        expectedError = unknownPin "gen-bind[.]contract[.]mk" "'check', 'message', 'blame'";
      };

      test-resolveThunks-missing-field-named = {
        expr = resolveThunks {
          config = { };
          ctx = { };
          thunkArgNames = [ ];
        };
        expectedError =
          missingPin "gen-bind[.]resolveThunks" "bindings"
            "'config', 'ctx', 'thunkArgNames', 'bindings'";
      };
      test-resolveThunks-unknown-option-named = {
        expr = resolveThunks {
          config = { };
          ctx = { };
          thunkArgNames = [ ];
          bindings = { };
          colr = 1;
        };
        expectedError = unknownPin "gen-bind[.]resolveThunks" "'config', 'ctx', 'thunkArgNames', 'bindings', 'producerConfigs'";
      };

      test-mkFlakeTerminal-missing-field-named = {
        expr =
          (mkFlakeTerminal {
            evalFlakeModule = a: m: {
              config.flake = {
                seen = a;
                inherit (m) systems;
              };
            };
            self = "s";
          }).adapter.wrapUnit
            [ ]
            [ ];
        expectedError =
          missingPin "gen-bind[.]crossing[.]mkFlakeTerminal" "inputs"
            "'evalFlakeModule', 'inputs', 'self'";
      };
      test-mkFlakeTerminal-unknown-option-named = {
        expr =
          (mkFlakeTerminal {
            evalFlakeModule = a: m: {
              config.flake = {
                seen = a;
                inherit (m) systems;
              };
            };
            inputs = { };
            self = "s";
            colr = 1;
          }).adapter.wrapUnit
            [ ]
            [ ];
        expectedError = unknownPin "gen-bind[.]crossing[.]mkFlakeTerminal" "'evalFlakeModule', 'inputs', 'self', 'systems'";
      };
    };

    door-checks-record = {
      test-stripBindingArgs-missing-field-named = {
        expr = stripBindingArgs { module = { }; };
        expectedError = missingPin "gen-bind[.]stripBindingArgs" "bindingNames" "'module', 'bindingNames'";
      };
      test-adaptArgs-missing-field-named = {
        expr = ((adaptArgs { adapt = _: { }; }) { }).imports;
        expectedError = missingPin "gen-bind[.]adaptArgs" "module" "'adapt', 'module'";
      };
      test-mkMergeValidator-missing-field-named = {
        expr =
          (
            (mkMergeValidator {
              resolvePolicy = _: "bind-wins";
              boundArgNames = [ "a" ];
            })
              {
                config._module.args = {
                  a = 1;
                };
              }
          ).warnings;
        expectedError =
          missingPin "gen-bind[.]mkMergeValidator" "provenance"
            "'resolvePolicy', 'boundArgNames', 'provenance'";
      };
      test-environment-missing-field-named = {
        expr = environment {
          unit = "igloo";
          crossings = [ ];
        };
        expectedError =
          missingPin "gen-bind[.]crossing[.]environment" "projection"
            "'unit', 'crossings', 'projection'";
      };
      test-coherence-missing-field-named = {
        expr = coherence {
          unit = "igloo";
          crossings = [ ];
          projection = { };
        };
        expectedError =
          missingPin "gen-bind[.]crossing[.]coherence" "linkset"
            "'unit', 'crossings', 'projection', 'linkset'";
      };
      test-placement-missing-field-named = {
        expr = placement {
          staticityAdmissible = true;
          deltaExact = "EXACT";
          adapter = {
            bindFormals = _: _: { };
          };
        };
        expectedError =
          missingPin "gen-bind[.]crossing[.]placement" "name"
            "'staticityAdmissible', 'deltaExact', 'adapter', 'name'";
      };
      test-mkHostedTerminal-missing-field-named = {
        expr = mkHostedTerminal {
          evaluator = _: { };
          locateConfig = _: { };
        };
        expectedError =
          missingPin "gen-bind[.]crossing[.]mkHostedTerminal" "class"
            "'evaluator', 'locateConfig', 'class'";
      };
    };
  };
}

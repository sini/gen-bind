{
  lib,
  genBind,
  genScope,
  ...
}:
let
  inherit (genBind)
    wrap
    wrapAll
    contract
    mkThunk
    isThunk
    ;

  # Does forcing this value to normal form succeed? A contract that fires is a
  # `throw`, so `okD v == false` means "something forced a violating binding".
  okD = v: (builtins.tryEval (builtins.deepSeq v v)).success;

  # THE POLICY DOOR (den-hoag-bvpuo) fixtures: `host` is bound and, in `called`, also supplied by the
  # module system, so `"SYSTEM"` is the system-wins answer and `"BOUND"` the binding.
  onHost = { host, config, ... }: { out = host; };
  called =
    opts:
    ((wrap ({ bindings.host = "BOUND"; } // opts) onHost).module {
      config = { };
      host = "SYSTEM";
    }).out;
  annotated = s: {
    bindings.host = {
      _mergeStrategy = s;
      v = "BOUND";
    };
  };
  # the hosted terminal: the per-value annotation is the only policy spelling that reaches it
  hosted =
    value:
    let
      t = genBind.crossing.mkHostedTerminal {
        evaluator = a: { config.built = a.modules; };
        locateConfig = u: u.config;
        class = "host";
      };
    in
    (
      (builtins.head (
        (t.adapter {
          extent = { };
          extraModules = [ ];
          peersOf = _: [ ];
          engine = genScope;
          marksOf = _: [ ];
          readerId = "fixture";
        }).bindFormals
          { host = value; }
          [ onHost ]
      ))
        {
          config = { };
          host = "SYSTEM";
        }
    ).out;
in
{

  flake.tests.wrap.test-function-partial-application = {
    expr =
      (wrap
        {
          bindings = {
            host = {
              name = "igloo";
            };
          };
        }
        (
          { host, config, ... }:
          {
            networking.hostName = host.name;
          }
        )
      ).wrapped;
    expected = true;
  };

  flake.tests.wrap.test-function-passthrough-no-match = {
    expr =
      (wrap {
        bindings = {
          host = { };
        };
      } ({ config, ... }: { })).wrapped;
    expected = false;
  };

  flake.tests.wrap.test-function-fully-applied = {
    expr =
      let
        result =
          wrap
            {
              bindings = {
                host = {
                  name = "igloo";
                };
              };
            }
            (
              { host }:
              {
                networking.hostName = host.name;
              }
            );
      in
      {
        wrapped = result.wrapped;
        # A function of the module system's call args alone, even with every formal bound
        # (den-hoag-34i06): applied to `{ }`, as a hand caller with no module system does.
        isFunction = builtins.isFunction result.module;
        noFormals = builtins.functionArgs result.module == { };
        applied = result.module { };
      };
    expected = {
      wrapped = true;
      isFunction = true;
      noFormals = true;
      applied.networking.hostName = "igloo";
    };
  };

  # Fully-applied path is thunk-aware. A channel-only consumer `{ ch, ... }`
  # (ellipsis absent from functionArgs; the single named formal `ch` is bound ⇒
  # allMatched) carries a producer-emitted config-thunk in `ch`. The fully-applied
  # branch resolves it against producerConfigs BEFORE calling the module.
  flake.tests.wrap.test-fully-applied-config-thunk-producer-scoped = {
    expr =
      (
        (wrap
          {
            bindings = {
              ch = [
                (genBind.mkThunkFrom "host=iceberg" ({ config, ... }: [ "h-${config.networking.hostName}" ]))
              ];
            };
            producerConfigs = {
              "host=iceberg" = {
                networking.hostName = "iceberg";
              };
            };
            thunkBindings = [ "ch" ];
          }
          (
            { ch, ... }:
            {
              out = builtins.head ch;
            }
          )
        ).module
          { }
      ).out;
    expected = "h-iceberg";
  };

  # Back-compat: a fully-applied module with NO thunks is unchanged even when a
  # non-empty producerConfigs is supplied — resolveThunks is never invoked
  # (hasThunks = false), so the bound args apply byte-identically.
  flake.tests.wrap.test-fully-applied-no-thunk-byte-identical = {
    expr =
      (
        (wrap
          {
            bindings = {
              host = {
                name = "igloo";
              };
            };
            producerConfigs = {
              "host=iceberg" = {
                networking.hostName = "iceberg";
              };
            };
          }
          (
            { host }:
            {
              networking.hostName = host.name;
            }
          )
        ).module
          { }
      ).networking.hostName;
    expected = "igloo";
  };

  # Documented edge: a null-scope thunk on the fully-applied path has no
  # evalModules `config` (that would require `config` as an UNBOUND formal, which
  # routes to the partial-app path). If a `config` arg is BOUND, the thunk resolves
  # against it; otherwise it would see `{}`. Here `config` is bound ⇒ used.
  flake.tests.wrap.test-fully-applied-null-scope-thunk-uses-bound-config = {
    expr =
      (
        (wrap
          {
            bindings = {
              ch = [
                (genBind.mkThunk ({ config, ... }: [ config.networking.hostName ]))
              ];
              config = {
                networking.hostName = "bound-cfg";
              };
            };
            thunkBindings = [ "ch" ];
          }
          (
            { ch, config, ... }:
            {
              out = builtins.head ch;
            }
          )
        ).module
          { }
      ).out;
    expected = "bound-cfg";
  };

  flake.tests.wrap.test-attrset-passthrough = {
    expr =
      (wrap { } {
        services.nginx.enable = true;
      }).wrapped;
    expected = false;
  };

  flake.tests.wrap.test-imports-recursion = {
    expr =
      (wrap
        {
          bindings = {
            host = {
              name = "igloo";
            };
          };
        }
        {
          imports = [
            (
              { host, config, ... }:
              {
                networking.hostName = host.name;
              }
            )
          ];
        }
      ).wrapped;
    expected = true;
  };

  flake.tests.wrap.test-consistent-shape-wrapped = {
    expr =
      let
        result = wrap {
          bindings = {
            host = { };
          };
        } ({ host, config, ... }: { });
      in
      builtins.attrNames result;
    expected = [
      "advertisedArgs"
      "module"
      "signature"
      "validator"
      "wrapped"
    ];
  };

  flake.tests.wrap.test-consistent-shape-passthrough = {
    expr =
      let
        result = wrap { } {
          services.nginx.enable = true;
        };
      in
      builtins.attrNames result;
    expected = [
      "advertisedArgs"
      "module"
      "signature"
      "validator"
      "wrapped"
    ];
  };

  flake.tests.wrap.test-signature-populated = {
    expr =
      let
        result =
          wrap
            {
              bindings = {
                host = { };
              };
            }
            (
              {
                host,
                config,
                lib,
                ...
              }:
              { }
            );
      in
      result.signature.bound ? host;
    expected = true;
  };

  flake.tests.wrap.test-validator-null-on-passthrough = {
    expr =
      (wrap {
        bindings = {
          host = { };
        };
      } ({ config, ... }: { })).validator;
    expected = null;
  };

  flake.tests.wrap.test-wrapAll-module-count = {
    expr =
      let
        result =
          wrapAll
            {
              bindings = {
                host = {
                  name = "igloo";
                };
              };
            }
            [
              (
                { host, config, ... }:
                {
                  networking.hostName = host.name;
                }
              )
              { services.nginx.enable = true; }
              (
                { host }:
                {
                  x = host.name;
                }
              )
            ];
      in
      builtins.length result.modules;
    expected = 3;
  };

  flake.tests.wrap.test-wrapAll-all-length-equals-modules-plus-validators = {
    expr =
      let
        result =
          wrapAll
            {
              bindings = {
                host = { };
              };
            }
            [
              ({ host, config, ... }: { })
            ];
      in
      builtins.length result.all == builtins.length result.modules + builtins.length result.validators;
    expected = true;
  };
  # ── Laziness of binding contracts (Chitil 2012 §2) ──
  # A contract is a partial identity wrapped around the binding value; it fires
  # only when the consuming module demands the arg it guards. The per-key value
  # thunk in `wrapFunctionModule` is what makes that hold — membership in the
  # injected attrset is value-free, so an undemanded binding is never forced.

  # Cell 1 — the defect these cells were written for.
  flake.tests.wrap.test-undemanded-contract-does-not-fire = {
    expr = okD (
      (wrap
        {
          bindings.a = "BAD";
          contracts.a = contract.isType "set";
        }
        (
          { a, config, ... }:
          {
            out = "no-read";
          }
        )
      ).module
        { config = { }; }
    );
    expected = true;
  };

  # Cell 2 — control for cell 1: laziness must not be bought by disarming contracts.
  flake.tests.wrap.test-control-demanded-contract-still-fires = {
    expr = okD (
      (wrap
        {
          bindings.a = "BAD";
          contracts.a = contract.isType "set";
        }
        (
          { a, config, ... }:
          {
            out = a;
          }
        )
      ).module
        { config = { }; }
    );
    expected = false;
  };

  # Cell 3 — the fully-applied branch fails the same way and is in scope.
  flake.tests.wrap.test-fully-applied-undemanded-contract-does-not-fire = {
    expr = okD (
      (wrap
        {
          bindings.a = "BAD";
          contracts.a = contract.isType "set";
        }
        (
          { a, ... }:
          {
            out = "no-read";
          }
        )
      ).module
        { }
    );
    expected = true;
  };

  # Cell 4 — control for cell 3.
  flake.tests.wrap.test-control-fully-applied-demanded-contract-still-fires = {
    expr = okD (
      (wrap
        {
          bindings.a = "BAD";
          contracts.a = contract.isType "set";
        }
        (
          { a, ... }:
          {
            out = a;
          }
        )
      ).module
        { }
    );
    expected = false;
  };

  # Cell 5 — per-key granularity: demanding `b` must not force `a`.
  flake.tests.wrap.test-sibling-binding-contract-not-forced = {
    expr =
      (
        (wrap
          {
            bindings = {
              a = "BAD";
              b = "READ-ME";
            };
            contracts.a = contract.isType "set";
          }
          (
            {
              a,
              b,
              config,
              ...
            }:
            {
              out = b;
            }
          )
        ).module
          { config = { }; }
      ).out;
    expected = "READ-ME";
  };

  # Cell 6 — control: the rewritten branch must keep the system-wins merge order.
  flake.tests.wrap.test-control-system-wins-yields-the-supplied-value = {
    expr =
      (
        (wrap
          {
            bindings.a = "BINDING";
            mergeStrategies.a = "system-wins";
          }
          (
            { a, config, ... }:
            {
              out = a;
            }
          )
        ).module
          {
            config = { };
            a = "SYSTEM";
          }
      ).out;
    expected = "SYSTEM";
  };

  # Cell 7 — control: same, through the `_mergeStrategy`-in-value annotation channel.
  flake.tests.wrap.test-control-system-wins-annotation-yields-the-supplied-value = {
    expr =
      (
        (wrap
          {
            bindings.a = {
              _mergeStrategy = "system-wins";
              v = 1;
            };
          }
          (
            { a, config, ... }:
            {
              out = a;
            }
          )
        ).module
          {
            config = { };
            a = "SYSTEM";
          }
      ).out;
    expected = "SYSTEM";
  };

  # Cell 8 — arms the boundary of the residual this change does NOT close:
  # `mkMergeValidator` still forces a COLLIDING binding when `config.warnings` is
  # demanded. Absent a collision it must force nothing.
  flake.tests.wrap.test-control-validator-forces-nothing-absent-a-collision = {
    expr =
      let
        w =
          (wrap
            {
              bindings.a = "BAD";
              contracts.a = contract.isType "set";
            }
            (
              { a, config, ... }:
              {
                out = "no-read";
              }
            )
          ).validator
            { config._module.args = { }; };
      in
      okD w.warnings;
    expected = true;
  };

  # Cell 9 — control: setting `thunkBindings` at all disables auto-detection.
  # Nothing else in the suite reaches the explicit branch of the per-key thunk
  # predicate, so this cell and cell 10 are the only ones that see it.
  flake.tests.wrap.test-control-empty-thunkBindings-disables-auto-detection = {
    expr =
      let
        r =
          wrap
            {
              bindings.ch = [ (mkThunk ({ config, ... }: [ 5 ])) ];
              thunkBindings = [ ];
            }
            (
              { ch, config, ... }:
              {
                out = ch;
              }
            );
      in
      isThunk (builtins.head (r.module { config = { }; }).out);
    expected = true;
  };

  # Cell 10 — control: naming a non-bound arg leaves a real thunk unresolved.
  flake.tests.wrap.test-control-thunkBindings-naming-an-unbound-arg-leaves-the-thunk = {
    expr =
      let
        r =
          wrap
            {
              bindings.ch = [ (mkThunk ({ config, ... }: [ 5 ])) ];
              thunkBindings = [ "notAnArg" ];
            }
            (
              { ch, config, ... }:
              {
                out = ch;
              }
            );
      in
      isThunk (builtins.head (r.module { config = { }; }).out);
    expected = true;
  };

  # THE POLICY DOOR (den-hoag-bvpuo): a merge strategy is one of the three declared values at every
  # field a caller writes it, and anything else is refused by name, catchably. WHAT A FAILING RUN
  # LOOKS LIKE: without the door every shape below binds `"BOUND"` (or serves the annotated value)
  # and each `success` reads `true`.
  flake.tests.wrap.test-policy-door-refuses-every-non-declared-value-catchably = {
    expr = builtins.map (v: (builtins.tryEval (builtins.deepSeq v v)).success) [
      (called { mergeStrategies.host = "sytem-wins"; })
      (called { mergeStrategies.host = 5; })
      (called { mergeStrategies.host = null; })
      (called { mergeStrategies.host = { }; })
      (called { mergeStrategies.host = [ "system-wins" ]; })
      (called { mergeStrategies.host = x: x; })
      (called { mergeStrategies = "system-wins"; })
      (called { defaultMergeStrategy = "sytem-wins"; })
      (called { defaultMergeStrategy = null; })
      (called (annotated "sytem-wins"))
      (called (annotated 5))
      (
        (builtins.head
          (wrapAll {
            bindings.host = "BOUND";
            mergeStrategies.host = "sytem-wins";
          } [ onHost ]).modules
        )
          {
            config = { };
            host = "SYSTEM";
          }
      ).out
      (hosted {
        _mergeStrategy = "sytem-wins";
        v = "BOUND";
      })
    ];
    expected = builtins.genList (_: false) 13;
  };

  # Every declared value behaves as before, at every field: a door that refused one would turn its
  # answer into a refusal.
  flake.tests.wrap.test-policy-door-every-declared-value-behaves-as-before = {
    expr = [
      (called { mergeStrategies.host = "bind-wins"; })
      (called { mergeStrategies.host = "system-wins"; })
      (called { mergeStrategies.host = "error"; })
      (called { defaultMergeStrategy = "system-wins"; })
      (called (annotated "system-wins"))
      (hosted {
        _mergeStrategy = "system-wins";
        v = "BOUND";
      })
    ];
    expected = [
      "BOUND"
      "SYSTEM"
      "BOUND"
      "SYSTEM"
      "SYSTEM"
      "SYSTEM"
    ];
  };

  # The cfg-level fields are decoded with the door's keys, when `wrap opts` is formed: an entry for
  # a name no formal binds, a typo the module never demands, and a bad default beside a per-key entry
  # that wins are all refused. Binding values stay unforced.
  flake.tests.wrap.test-policy-door-decodes-cfg-fields-when-wrap-opts-is-formed = {
    expr = {
      unknownKey =
        (builtins.tryEval (builtins.seq (wrap { mergeStrategies.zz = "sytem-wins"; }) null)).success;
      # `host` is bound and a formal, and the module never demands it: its policy is never read
      notDemanded =
        (builtins.tryEval (
          builtins.deepSeq
            (
              (wrap {
                bindings.host = "BOUND";
                mergeStrategies.host = "sytem-wins";
              } ({ host, config, ... }: { out = "IGNORED"; })).module
                { config = { }; }
            ).out
            null
        )).success;
      shadowedDefault =
        (builtins.tryEval (
          builtins.seq (wrap {
            mergeStrategies.host = "system-wins";
            defaultMergeStrategy = "sytem-wins";
          }) null
        )).success;
      valueUnforced = (wrap { bindings.host = throw "value-forced"; } onHost).wrapped;
    };
    expected = {
      unknownKey = false;
      notDemanded = false;
      shadowedDefault = false;
      valueUnforced = true;
    };
  };

  # A value's own `_mergeStrategy` is decoded where it is read, never when `wrap opts` is formed:
  # shadowed by a per-key entry it is not read, and on an arg the module never demands it is not read.
  flake.tests.wrap.test-policy-door-reads-an-annotation-only-where-it-is-read = {
    expr = {
      shadowed = called ({ mergeStrategies.host = "system-wins"; } // annotated "sytem-wins");
      notDemanded =
        ((wrap (annotated "sytem-wins") ({ host, config, ... }: { out = "IGNORED"; })).module {
          config = { };
        }).out;
    };
    expected = {
      shadowed = "SYSTEM";
      notDemanded = "IGNORED";
    };
  };

  flake.testsError.wrap = {
    test-policy-door-names-a-misspelt-mergeStrategies-entry = {
      expr = called { mergeStrategies.host = "sytem-wins"; };
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]wrap: `mergeStrategies[.]host` is \"sytem-wins\", not one of \"bind-wins\", \"system-wins\", \"error\"$";
      };
    };
    test-policy-door-names-a-non-string-default-by-type = {
      expr = called { defaultMergeStrategy = null; };
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]wrap: `defaultMergeStrategy` is a null, not one of \"bind-wins\", \"system-wins\", \"error\"$";
      };
    };
    test-policy-door-names-a-non-attrset-mergeStrategies = {
      expr = called { mergeStrategies = "system-wins"; };
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]wrap: `mergeStrategies` must be an attrset of policies, not a string$";
      };
    };
    test-policy-door-names-the-annotation-it-read = {
      expr = called (annotated "sytem-wins");
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind: binding 'host' has `_mergeStrategy` \"sytem-wins\", not one of \"bind-wins\", \"system-wins\", \"error\"$";
      };
    };
    test-policy-door-wrapAll-names-its-own-door = {
      expr = wrapAll { mergeStrategies.host = "sytem-wins"; } [ onHost ];
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]wrapAll: `mergeStrategies[.]host` is \"sytem-wins\", not one of \"bind-wins\", \"system-wins\", \"error\"$";
      };
    };
    test-policy-door-wrapAll-names-its-own-door-for-a-non-attrset = {
      expr = wrapAll { mergeStrategies = "system-wins"; } [ onHost ];
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]wrapAll: `mergeStrategies` must be an attrset of policies, not a string$";
      };
    };
    # The validator a wrap caller reaches names the field the caller wrote, not `resolvePolicy`.
    test-policy-door-the-validator-route-names-the-wrap-field = {
      expr =
        (
          (wrap {
            bindings.host = "BOUND";
            mergeStrategies.host = "sytem-wins";
          } onHost).validator
            {
              config._module.args.host = "SYSTEM";
            }
        ).warnings;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]wrap: `mergeStrategies[.]host` is \"sytem-wins\", not one of \"bind-wins\", \"system-wins\", \"error\"$";
      };
    };
    test-policy-door-the-hosted-terminal-names-the-annotation = {
      expr = hosted {
        _mergeStrategy = "sytem-wins";
        v = "BOUND";
      };
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind: binding 'host' has `_mergeStrategy` \"sytem-wins\", not one of \"bind-wins\", \"system-wins\", \"error\"$";
      };
    };
    # RESIDUE: what a policy thunk itself throws reaches the caller unchanged; the door decodes a
    # value, and a throw is not one.
    test-policy-door-residue-a-throwing-policy-throws-its-own-message = {
      expr = wrap { mergeStrategies.host = throw "policy-thrown"; };
      expectedError = {
        type = "ThrownError";
        msg = "^policy-thrown$";
      };
    };
  };
}

{ lib, genBind, ... }:
let
  inherit (genBind)
    mkThunk
    mkThunkFrom
    isThunk
    resolveThunks
    ;

  onHost = { host, config, ... }: host;
  resolveOne =
    t:
    (resolveThunks { } {
      config = { };
      ctx.host = "h";
      thunkArgNames = [ "t" ];
      bindings.t = [ t ];
    }).t;
  refused = v: !(builtins.tryEval (builtins.deepSeq v v)).success;
  # nixpkgs' `lib.isFunction` reads none of these as a function.
  outOfDomain = [
    5
    "s"
    { a = 1; }
    { __functor = 5; }
    {
      __functor = 5;
      __functionArgs.config = false;
    }
    { __functor = _: 5; }
    { __functor = _: { __functor = _: onHost; }; }
    { __functor.__functor = _: _: onHost; }
  ];
  # nixpkgs' `lib.isFunction` reads both as a function, but `functionArgs` returns the published
  # map verbatim, and neither is the attrset of booleans `setFunctionArgs` publishes.
  malformedMap = [
    {
      __functor = _: a: a.host;
      __functionArgs = [
        "host"
        "config"
      ];
    }
    {
      __functor = _: a: a.host;
      __functionArgs = {
        host = "required";
        config = false;
      };
    }
  ];
in
{

  flake.tests.thunk.test-mkThunk-creates-marker = {
    expr = (mkThunk ({ config, ... }: config.x)) ? __configThunk;
    expected = true;
  };

  flake.tests.thunk.test-isThunk-positive = {
    expr = isThunk (mkThunk ({ config, ... }: config.x));
    expected = true;
  };

  flake.tests.thunk.test-isThunk-negative-null = {
    expr = isThunk null;
    expected = false;
  };

  flake.tests.thunk.test-isThunk-negative-attrset = {
    expr = isThunk { foo = 1; };
    expected = false;
  };

  flake.tests.thunk.test-mkThunkFrom-attaches-scope = {
    expr = (mkThunkFrom "host=igloo" ({ config, ... }: config.x)).__sourceScope;
    expected = "host=igloo";
  };

  flake.tests.thunk.test-resolveThunks-resolves-list = {
    expr = resolveThunks { } {
      config = {
        networking.hostName = "igloo";
      };
      ctx = {
        host = {
          name = "igloo";
        };
      };
      thunkArgNames = [ "data" ];
      bindings = {
        data = [
          (mkThunk ({ config, ... }: [ config.networking.hostName ]))
          "static"
        ];
      };
    };
    expected = {
      data = [
        "igloo"
        "static"
      ];
    };
  };

  flake.tests.thunk.test-resolveThunks-passes-ctx-args = {
    expr = resolveThunks { } {
      config = { };
      ctx = {
        host = {
          name = "igloo";
        };
      };
      thunkArgNames = [ "data" ];
      bindings = {
        data = [
          (mkThunk ({ host, ... }: [ host.name ]))
        ];
      };
    };
    expected = {
      data = [ "igloo" ];
    };
  };

  flake.tests.thunk.test-resolveThunks-skips-non-thunk-args = {
    expr = resolveThunks { } {
      config = { };
      ctx = { };
      thunkArgNames = [ "data" ];
      bindings = {
        data = [
          "a"
          "b"
        ];
        other = "untouched";
      };
    };
    expected = {
      data = [
        "a"
        "b"
      ];
      other = "untouched";
    };
  };

  # Producer-scoped resolution (CHORAG §5.1). A thunk stamped with __sourceScope
  # resolves against the PRODUCER's config supplied in producerConfigs, NOT the
  # consumer's config. Here the producer (iceberg) and consumer (igloo) disagree
  # on networking.hostName; with producerConfigs the thunk reads the producer's.
  flake.tests.thunk.test-resolveThunks-producer-scoped-reads-producer-config = {
    expr =
      resolveThunks
        {
          producerConfigs = {
            "host=iceberg" = {
              networking.hostName = "iceberg";
            };
          };
        }
        {
          config = {
            networking.hostName = "igloo";
          };
          ctx = { };
          thunkArgNames = [ "data" ];
          bindings = {
            data = [
              (mkThunkFrom "host=iceberg" ({ config, ... }: [ "h-${config.networking.hostName}" ]))
            ];
          };
        };
    expected = {
      data = [ "h-iceberg" ];
    };
  };

  # Back-compat: default producerConfigs = {} ⇒ byte-identical to consumer
  # resolution. A __sourceScope-tagged thunk with NO producerConfigs supplied
  # resolves against the consumer config exactly as a plain mkThunk would.
  flake.tests.thunk.test-resolveThunks-default-empty-is-consumer-scoped = {
    # producerConfigs omitted ⇒ defaults to {}
    expr = resolveThunks { } {
      config = {
        networking.hostName = "igloo";
      };
      ctx = { };
      thunkArgNames = [ "data" ];
      bindings = {
        data = [
          (mkThunkFrom "host=iceberg" ({ config, ... }: [ "h-${config.networking.hostName}" ]))
        ];
      };
    };
    expected = {
      data = [ "h-igloo" ];
    };
  };

  # Back-compat: __sourceScope tagged but that scope is ABSENT from a non-empty
  # producerConfigs ⇒ fall back to the consumer config (byte-identical). Only a
  # scope the caller actually supplied redirects resolution.
  flake.tests.thunk.test-resolveThunks-unknown-scope-falls-back-to-consumer = {
    expr =
      resolveThunks
        {
          producerConfigs = {
            "host=other" = {
              networking.hostName = "other";
            };
          };
        }
        {
          config = {
            networking.hostName = "igloo";
          };
          ctx = { };
          thunkArgNames = [ "data" ];
          bindings = {
            data = [
              (mkThunkFrom "host=iceberg" ({ config, ... }: [ "h-${config.networking.hostName}" ]))
            ];
          };
        };
    expected = {
      data = [ "h-igloo" ];
    };
  };

  # A null-scope thunk (plain mkThunk) ignores producerConfigs entirely and
  # resolves against the consumer config, even when producerConfigs is non-empty.
  flake.tests.thunk.test-resolveThunks-null-scope-ignores-producerConfigs = {
    expr =
      resolveThunks
        {
          producerConfigs = {
            "host=iceberg" = {
              networking.hostName = "iceberg";
            };
          };
        }
        {
          config = {
            networking.hostName = "igloo";
          };
          ctx = { };
          thunkArgNames = [ "data" ];
          bindings = {
            data = [
              (mkThunk ({ config, ... }: [ config.networking.hostName ]))
            ];
          };
        };
    expected = {
      data = [ "igloo" ];
    };
  };

  # LOUD, not silent (unit granularity). When producer-scoped resolution reads a
  # producer-config field that itself throws, the error PROPAGATES to the
  # consumer — it is not swallowed and it is not silently substituted by the
  # consumer's (benign) config. tryEval catches the throw here, proving the
  # producer value is genuinely demanded. (A GENUINE cross-terminal *cycle*
  # surfaces as Nix's `infinite recursion encountered`, which is uncatchable by
  # tryEval by design — that IS the loud contract; it is exercised as a manual
  # lib.fix knot probe, not a forcing unit test, since forcing it would abort the
  # runner.)
  flake.tests.thunk.test-resolveThunks-producer-error-propagates-loud = {
    expr =
      (builtins.tryEval (
        builtins.deepSeq (resolveThunks
          {
            producerConfigs = {
              "host=iceberg" = {
                networking.hostName = throw "producer-config forced";
              };
            };
          }
          {
            config = {
              networking.hostName = "igloo"; # consumer value would resolve fine
            };
            ctx = { };
            thunkArgNames = [ "data" ];
            bindings = {
              data = [
                (mkThunkFrom "host=iceberg" ({ config, ... }: [ config.networking.hostName ]))
              ];
            };
          }
        ) null
      )).success;
    expected = false;
  };

  # Non-string __sourceScope degrades gracefully. A caller may stamp a structured
  # scope (an attrset) rather than a flat string key; indexing producerConfigs with
  # it would `cannot coerce a set to a string`. The isString guard makes such a
  # thunk fall back to the consumer config instead of throwing — the key SHAPE is
  # the caller's business, gen-bind only indexes a usable (string) key. deepSeq
  # forces the whole result to prove no latent coercion throw survives.
  flake.tests.thunk.test-resolveThunks-non-string-scope-falls-back = {
    expr = (
      builtins.tryEval (
        let
          r =
            resolveThunks
              {
                producerConfigs = {
                  "host=iceberg" = {
                    networking.hostName = "iceberg";
                  };
                };
              }
              {
                config = {
                  networking.hostName = "igloo";
                };
                ctx = { };
                thunkArgNames = [ "data" ];
                bindings = {
                  data = [
                    (mkThunkFrom { host = "iceberg"; } ({ config, ... }: [ config.networking.hostName ]))
                  ];
                };
              };
        in
        builtins.deepSeq r r
      )
    );
    # Succeeds (no coercion throw) AND resolves against the consumer config.
    expected = {
      success = true;
      value = {
        data = [ "igloo" ];
      };
    };
  };

  # ══ A FUNCTOR `fn` IS SERVED AS ITS LAMBDA TWIN (den-hoag-pcfmm) ═══════════
  #
  # WHAT A FAILING RUN LOOKS LIKE: the runner aborts UNCATCHABLY on the first functor with Nix's
  # `'functionArgs' requires a function`, and no cell in this file reports. `published` reads `host`
  # from `__functionArgs` alone (its lambda has no formals), so a reader that ignores the published
  # map serves it `config` only and it throws on `a.host`.
  flake.tests.thunk.test-a-functor-fn-is-served-as-its-lambda-twin = {
    expr = map (fn: resolveOne (mkThunk fn)) [
      onHost
      { __functor = _: onHost; }
      (lib.setFunctionArgs (a: a.host) {
        host = false;
        config = false;
      })
    ];
    expected = [
      [ "h" ]
      [ "h" ]
      [ "h" ]
    ];
  };

  # Outside `functionArgs`' domain, at both doors: `mkThunk` and a marker built by hand.
  flake.tests.thunk.test-an-fn-outside-the-reader-domain-is-refused-catchably = {
    expr = map (fn: {
      mk = refused (mkThunk fn);
      raw = refused (resolveOne {
        __configThunk = true;
        __fn = fn;
      });
    }) outOfDomain;
    expected = map (_: {
      mk = true;
      raw = true;
    }) outOfDomain;
  };

  flake.tests.thunk.test-a-malformed-published-map-is-refused-catchably = {
    expr = map (fn: {
      mk = refused (mkThunk fn);
      raw = refused (resolveOne {
        __configThunk = true;
        __fn = fn;
      });
    }) malformedMap;
    expected = map (_: {
      mk = true;
      raw = true;
    }) malformedMap;
  };

  # The door is at intake, so a route that never resolves the marker refuses it too, once forced:
  # a marker's only meaning is that it resolves (Findler–Felleisen blame at the supplier's call).
  # A non-list binding is passed through, and here it is refused rather than carried.
  flake.tests.thunk.test-an-out-of-domain-fn-is-refused-on-the-passthrough-route = {
    expr =
      refused
        (resolveThunks { } {
          config = { };
          ctx = { };
          thunkArgNames = [ "p" ];
          bindings.p = mkThunk { __functor = _: { __functor = _: onHost; }; };
        }).p;
    expected = true;
  };

  flake.tests.thunk.test-a-required-formal-ctx-does-not-supply-is-refused-catchably = {
    expr = refused (resolveOne (mkThunk ({ missing, config }: missing)));
    expected = true;
  };

  flake.testsError.thunk = {
    test-mkThunk-refuses-a-functor-yielding-no-function-by-name = {
      expr = mkThunk { __functor = 5; };
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]mkThunk: `fn` must be a function, or a functor whose `__functor` yields one, not a functor that does not yield a function$";
      };
    };
    test-mkThunkFrom-refuses-a-non-function-by-name = {
      expr = mkThunkFrom "s" "s";
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]mkThunkFrom: `fn` must be a function, or a functor whose `__functor` yields one, not a string$";
      };
    };
    test-resolveThunks-refuses-a-hand-built-marker-by-name = {
      expr = resolveOne {
        __configThunk = true;
        __fn = 5;
      };
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]resolveThunks: `fn` must be a function, or a functor whose `__functor` yields one, not a int$";
      };
    };
    test-mkThunk-refuses-a-published-map-that-is-a-list-by-name = {
      expr = mkThunk (builtins.head malformedMap);
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]mkThunk: `fn`'s published `__functionArgs` must be an attrset of booleans, not a list$";
      };
    };
    test-resolveThunks-refuses-a-published-map-with-a-non-boolean-by-name = {
      expr = resolveOne {
        __configThunk = true;
        __fn = builtins.elemAt malformedMap 1;
      };
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]resolveThunks: `fn`'s published `__functionArgs` must be an attrset of booleans, not one whose 'host' is a string$";
      };
    };
    test-resolveThunks-names-the-unmet-formal = {
      expr = resolveOne (mkThunk ({ missing, config }: missing));
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]resolveThunks: a thunk in binding 't' requires 'missing', which ctx does not supply$";
      };
    };
    # THE RESIDUE, NOT A DOOR: a published `__functionArgs` is the reader's whole answer (nixpkgs'
    # `setFunctionArgs` convention), so a map that omits a formal its body requires cannot be seen
    # before the application, which aborts inside it. Pinned so the bound is measured, not claimed.
    test-resolveThunks-residue-a-published-map-omitting-a-required-formal-aborts = {
      expr = resolveOne (
        mkThunk (
          lib.setFunctionArgs ({ host, missing, ... }: host) {
            host = false;
            config = false;
          }
        )
      );
      expectedError = {
        type = "TypeError";
        msg = "called without required argument 'missing'";
      };
    };
  };
}

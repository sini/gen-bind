{ lib, genBind, ... }:
let
  inherit (genBind)
    mkThunk
    mkThunkFrom
    isThunk
    resolveThunks
    ;
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
    expr = resolveThunks {
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
    expr = resolveThunks {
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
    expr = resolveThunks {
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
    expr = resolveThunks {
      config = {
        networking.hostName = "igloo";
      };
      ctx = { };
      thunkArgNames = [ "data" ];
      producerConfigs = {
        "host=iceberg" = {
          networking.hostName = "iceberg";
        };
      };
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
    expr = resolveThunks {
      config = {
        networking.hostName = "igloo";
      };
      ctx = { };
      thunkArgNames = [ "data" ];
      # producerConfigs omitted ⇒ defaults to {}
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
    expr = resolveThunks {
      config = {
        networking.hostName = "igloo";
      };
      ctx = { };
      thunkArgNames = [ "data" ];
      producerConfigs = {
        "host=other" = {
          networking.hostName = "other";
        };
      };
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
    expr = resolveThunks {
      config = {
        networking.hostName = "igloo";
      };
      ctx = { };
      thunkArgNames = [ "data" ];
      producerConfigs = {
        "host=iceberg" = {
          networking.hostName = "iceberg";
        };
      };
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
        builtins.deepSeq (resolveThunks {
          config = {
            networking.hostName = "igloo"; # consumer value would resolve fine
          };
          ctx = { };
          thunkArgNames = [ "data" ];
          producerConfigs = {
            "host=iceberg" = {
              networking.hostName = throw "producer-config forced";
            };
          };
          bindings = {
            data = [
              (mkThunkFrom "host=iceberg" ({ config, ... }: [ config.networking.hostName ]))
            ];
          };
        }) null
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
          r = resolveThunks {
            config = {
              networking.hostName = "igloo";
            };
            ctx = { };
            thunkArgNames = [ "data" ];
            producerConfigs = {
              "host=iceberg" = {
                networking.hostName = "iceberg";
              };
            };
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
}

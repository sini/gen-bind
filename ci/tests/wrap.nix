{ lib, genBind, ... }:
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
in
{

  flake.tests.wrap.test-function-partial-application = {
    expr =
      (wrap {
        module =
          { host, config, ... }:
          {
            networking.hostName = host.name;
          };
        bindings = {
          host = {
            name = "igloo";
          };
        };
      }).wrapped;
    expected = true;
  };

  flake.tests.wrap.test-function-passthrough-no-match = {
    expr =
      (wrap {
        module = { config, ... }: { };
        bindings = {
          host = { };
        };
      }).wrapped;
    expected = false;
  };

  flake.tests.wrap.test-function-fully-applied = {
    expr =
      let
        result = wrap {
          module =
            { host }:
            {
              networking.hostName = host.name;
            };
          bindings = {
            host = {
              name = "igloo";
            };
          };
        };
      in
      {
        wrapped = result.wrapped;
        isAttrs = builtins.isAttrs result.module;
      };
    expected = {
      wrapped = true;
      isAttrs = true;
    };
  };

  # Fully-applied path is thunk-aware. A channel-only consumer `{ ch, ... }`
  # (ellipsis absent from functionArgs; the single named formal `ch` is bound ⇒
  # allMatched) carries a producer-emitted config-thunk in `ch`. The fully-applied
  # branch resolves it against producerConfigs BEFORE calling the module.
  flake.tests.wrap.test-fully-applied-config-thunk-producer-scoped = {
    expr =
      (wrap {
        module =
          { ch, ... }:
          {
            out = builtins.head ch;
          };
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
      }).module.out;
    expected = "h-iceberg";
  };

  # Back-compat: a fully-applied module with NO thunks is unchanged even when a
  # non-empty producerConfigs is supplied — resolveThunks is never invoked
  # (hasThunks = false), so the bound args apply byte-identically.
  flake.tests.wrap.test-fully-applied-no-thunk-byte-identical = {
    expr =
      (wrap {
        module =
          { host }:
          {
            networking.hostName = host.name;
          };
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
      }).module.networking.hostName;
    expected = "igloo";
  };

  # Documented edge: a null-scope thunk on the fully-applied path has no
  # evalModules `config` (that would require `config` as an UNBOUND formal, which
  # routes to the partial-app path). If a `config` arg is BOUND, the thunk resolves
  # against it; otherwise it would see `{}`. Here `config` is bound ⇒ used.
  flake.tests.wrap.test-fully-applied-null-scope-thunk-uses-bound-config = {
    expr =
      (wrap {
        module =
          { ch, config, ... }:
          {
            out = builtins.head ch;
          };
        bindings = {
          ch = [
            (genBind.mkThunk ({ config, ... }: [ config.networking.hostName ]))
          ];
          config = {
            networking.hostName = "bound-cfg";
          };
        };
      }).module.out;
    expected = "bound-cfg";
  };

  flake.tests.wrap.test-attrset-passthrough = {
    expr =
      (wrap {
        module = {
          services.nginx.enable = true;
        };
      }).wrapped;
    expected = false;
  };

  flake.tests.wrap.test-imports-recursion = {
    expr =
      (wrap {
        module = {
          imports = [
            (
              { host, config, ... }:
              {
                networking.hostName = host.name;
              }
            )
          ];
        };
        bindings = {
          host = {
            name = "igloo";
          };
        };
      }).wrapped;
    expected = true;
  };

  flake.tests.wrap.test-consistent-shape-wrapped = {
    expr =
      let
        result = wrap {
          module = { host, config, ... }: { };
          bindings = {
            host = { };
          };
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

  flake.tests.wrap.test-consistent-shape-passthrough = {
    expr =
      let
        result = wrap {
          module = {
            services.nginx.enable = true;
          };
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
        result = wrap {
          module =
            {
              host,
              config,
              lib,
              ...
            }:
            { };
          bindings = {
            host = { };
          };
        };
      in
      result.signature.bound ? host;
    expected = true;
  };

  flake.tests.wrap.test-validator-null-on-passthrough = {
    expr =
      (wrap {
        module = { config, ... }: { };
        bindings = {
          host = { };
        };
      }).validator;
    expected = null;
  };

  flake.tests.wrap.test-wrapAll-module-count = {
    expr =
      let
        result = wrapAll {
          modules = [
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
          bindings = {
            host = {
              name = "igloo";
            };
          };
        };
      in
      builtins.length result.modules;
    expected = 3;
  };

  flake.tests.wrap.test-wrapAll-all-length-equals-modules-plus-validators = {
    expr =
      let
        result = wrapAll {
          modules = [
            ({ host, config, ... }: { })
          ];
          bindings = {
            host = { };
          };
        };
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
      (wrap {
        module =
          { a, config, ... }:
          {
            out = "no-read";
          };
        bindings.a = "BAD";
        contracts.a = contract.isType "set";
      }).module
        { config = { }; }
    );
    expected = true;
  };

  # Cell 2 — control for cell 1: laziness must not be bought by disarming contracts.
  flake.tests.wrap.test-control-demanded-contract-still-fires = {
    expr = okD (
      (wrap {
        module =
          { a, config, ... }:
          {
            out = a;
          };
        bindings.a = "BAD";
        contracts.a = contract.isType "set";
      }).module
        { config = { }; }
    );
    expected = false;
  };

  # Cell 3 — the fully-applied branch fails the same way and is in scope.
  flake.tests.wrap.test-fully-applied-undemanded-contract-does-not-fire = {
    expr = okD (
      (wrap {
        module =
          { a, ... }:
          {
            out = "no-read";
          };
        bindings.a = "BAD";
        contracts.a = contract.isType "set";
      }).module
    );
    expected = true;
  };

  # Cell 4 — control for cell 3.
  flake.tests.wrap.test-control-fully-applied-demanded-contract-still-fires = {
    expr = okD (
      (wrap {
        module =
          { a, ... }:
          {
            out = a;
          };
        bindings.a = "BAD";
        contracts.a = contract.isType "set";
      }).module
    );
    expected = false;
  };

  # Cell 5 — per-key granularity: demanding `b` must not force `a`.
  flake.tests.wrap.test-sibling-binding-contract-not-forced = {
    expr =
      (
        (wrap {
          module =
            {
              a,
              b,
              config,
              ...
            }:
            {
              out = b;
            };
          bindings = {
            a = "BAD";
            b = "READ-ME";
          };
          contracts.a = contract.isType "set";
        }).module
        { config = { }; }
      ).out;
    expected = "READ-ME";
  };

  # Cell 6 — control: the rewritten branch must keep the system-wins merge order.
  flake.tests.wrap.test-control-system-wins-yields-the-supplied-value = {
    expr =
      (
        (wrap {
          module =
            { a, config, ... }:
            {
              out = a;
            };
          bindings.a = "BINDING";
          mergeStrategies.a = "system-wins";
        }).module
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
        (wrap {
          module =
            { a, config, ... }:
            {
              out = a;
            };
          bindings.a = {
            _mergeStrategy = "system-wins";
            v = 1;
          };
        }).module
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
          (wrap {
            module =
              { a, config, ... }:
              {
                out = "no-read";
              };
            bindings.a = "BAD";
            contracts.a = contract.isType "set";
          }).validator
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
        r = wrap {
          module =
            { ch, config, ... }:
            {
              out = ch;
            };
          bindings.ch = [ (mkThunk ({ config, ... }: [ 5 ])) ];
          thunkBindings = [ ];
        };
      in
      isThunk (builtins.head (r.module { config = { }; }).out);
    expected = true;
  };

  # Cell 10 — control: naming a non-bound arg leaves a real thunk unresolved.
  flake.tests.wrap.test-control-thunkBindings-naming-an-unbound-arg-leaves-the-thunk = {
    expr =
      let
        r = wrap {
          module =
            { ch, config, ... }:
            {
              out = ch;
            };
          bindings.ch = [ (mkThunk ({ config, ... }: [ 5 ])) ];
          thunkBindings = [ "notAnArg" ];
        };
      in
      isThunk (builtins.head (r.module { config = { }; }).out);
    expected = true;
  };
}

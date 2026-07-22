{ lib, genBind, ... }:
let
  inherit (genBind) wrap wrapAll;
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
}

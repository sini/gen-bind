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

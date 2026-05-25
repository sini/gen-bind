{ lib, bindLib, ... }:
let
  inherit (bindLib) wrap wrapAll;
in
{
  wrap.test-function-partial-application = {
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

  wrap.test-function-passthrough-no-match = {
    expr =
      (wrap {
        module = { config, ... }: { };
        bindings = {
          host = { };
        };
      }).wrapped;
    expected = false;
  };

  wrap.test-function-fully-applied = {
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

  wrap.test-attrset-passthrough = {
    expr =
      (wrap {
        module = {
          services.nginx.enable = true;
        };
      }).wrapped;
    expected = false;
  };

  wrap.test-imports-recursion = {
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

  wrap.test-consistent-shape-wrapped = {
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

  wrap.test-consistent-shape-passthrough = {
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

  wrap.test-signature-populated = {
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

  wrap.test-validator-null-on-passthrough = {
    expr =
      (wrap {
        module = { config, ... }: { };
        bindings = {
          host = { };
        };
      }).validator;
    expected = null;
  };

  wrap.test-wrapAll-module-count = {
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

  wrap.test-wrapAll-all-includes-validators = {
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
      builtins.length result.all >= builtins.length result.modules;
    expected = true;
  };
}

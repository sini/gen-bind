{ lib, bindLib, ... }:
let
  inherit (bindLib)
    wrap
    wrapAll
    wrapIdentity
    mkThunk
    ;

  # Minimal evalModules with networking options for round-trip testing.
  evalWith =
    modules:
    lib.evalModules {
      modules = [
        (
          { lib, ... }:
          {
            options.networking.hostName = lib.mkOption {
              type = lib.types.str;
              default = "";
            };
            options.networking.domain = lib.mkOption {
              type = lib.types.str;
              default = "";
            };
            options.x = lib.mkOption {
              type = lib.types.anything;
              default = null;
            };
          }
        )
      ]
      ++ modules;
    };
in
{
  integration.test-wrap-evalmodules-roundtrip = {
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
            {
              networking.hostName = host.name;
            };
          bindings = {
            host = {
              name = "igloo";
            };
          };
        };
        evaluated = evalWith [ result.module ];
      in
      evaluated.config.networking.hostName;
    expected = "igloo";
  };

  integration.test-fully-applied-in-evalmodules = {
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
              name = "iceberg";
            };
          };
        };
        evaluated = evalWith [ result.module ];
      in
      evaluated.config.networking.hostName;
    expected = "iceberg";
  };

  integration.test-thunk-resolution = {
    expr =
      let
        thunkValue = mkThunk ({ config, ... }: config.networking.hostName);
        result = wrap {
          module =
            { mydata, config, ... }:
            {
              networking.domain = builtins.head mydata;
            };
          bindings = {
            mydata = [ thunkValue ];
          };
        };
        evaluated = evalWith [
          result.module
          { networking.hostName = "igloo"; }
        ];
      in
      evaluated.config.networking.domain;
    expected = "igloo";
  };

  # NixOS deduplicates modules with the same key — the second module with a
  # duplicate key is silently dropped. This test verifies that dedup fires:
  # mod1 contributes x = 1, mod2 (same key) is dropped so hostName stays "".
  integration.test-identity-dedup = {
    expr =
      let
        mod1 = wrapIdentity {
          class = "nixos";
          module = {
            x = 1;
          };
          identity = "test";
        };
        mod2 = wrapIdentity {
          class = "nixos";
          module = {
            networking.hostName = "deduped-away";
          };
          identity = "test";
        };
        evaluated = evalWith [
          mod1
          mod2
        ];
      in
      {
        # mod1 contributes x = 1
        x = evaluated.config.x;
        # mod2 is dropped by dedup — hostName stays at default ""
        nameIsDefault = evaluated.config.networking.hostName == "";
      };
    expected = {
      x = 1;
      nameIsDefault = true;
    };
  };

  integration.test-wrapAll-batch = {
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
            { networking.domain = "local"; }
          ];
          bindings = {
            host = {
              name = "igloo";
            };
          };
        };
        evaluated = evalWith result.modules;
      in
      {
        name = evaluated.config.networking.hostName;
        domain = evaluated.config.networking.domain;
      };
    expected = {
      name = "igloo";
      domain = "local";
    };
  };

  # Thunk accessing binding args (not just config) through full wrap pipeline
  integration.test-thunk-with-binding-ctx = {
    expr =
      let
        thunkValue = mkThunk ({ host, ... }: [ host.name ]);
        result = wrap {
          module =
            { mydata, config, ... }:
            {
              networking.domain = builtins.head mydata;
            };
          bindings = {
            host = {
              name = "igloo";
            };
            mydata = [ thunkValue ];
          };
        };
        evaluated = evalWith [ result.module ];
      in
      evaluated.config.networking.domain;
    expected = "igloo";
  };
}

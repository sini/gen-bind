{ lib, genBind, ... }:
let
  inherit (genBind)
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

  flake.tests.integration.test-wrap-evalmodules-roundtrip = {
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
              {
                host,
                config,
                lib,
                ...
              }:
              {
                networking.hostName = host.name;
              }
            );
        evaluated = evalWith [ result.module ];
      in
      evaluated.config.networking.hostName;
    expected = "igloo";
  };

  flake.tests.integration.test-fully-applied-in-evalmodules = {
    expr =
      let
        result =
          wrap
            {
              bindings = {
                host = {
                  name = "iceberg";
                };
              };
            }
            (
              { host }:
              {
                networking.hostName = host.name;
              }
            );
        evaluated = evalWith [ result.module ];
      in
      evaluated.config.networking.hostName;
    expected = "iceberg";
  };

  flake.tests.integration.test-thunk-resolution = {
    expr =
      let
        thunkValue = mkThunk ({ config, ... }: config.networking.hostName);
        result =
          wrap
            {
              bindings = {
                mydata = [ thunkValue ];
              };
              thunkBindings = [ "mydata" ];
            }
            (
              { mydata, config, ... }:
              {
                networking.domain = builtins.head mydata;
              }
            );
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
  flake.tests.integration.test-identity-dedup = {
    expr =
      let
        mod1 = wrapIdentity { } "nixos" "test" {
          x = 1;
        };
        mod2 = wrapIdentity { } "nixos" "test" {
          networking.hostName = "deduped-away";
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

  flake.tests.integration.test-wrapAll-batch = {
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
              { networking.domain = "local"; }
            ];
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
  flake.tests.integration.test-thunk-with-binding-ctx = {
    expr =
      let
        thunkValue = mkThunk ({ host, ... }: [ host.name ]);
        result =
          wrap
            {
              bindings = {
                host = {
                  name = "igloo";
                };
                mydata = [ thunkValue ];
              };
              thunkBindings = [ "mydata" ];
            }
            (
              { mydata, config, ... }:
              {
                networking.domain = builtins.head mydata;
              }
            );
        evaluated = evalWith [ result.module ];
      in
      evaluated.config.networking.domain;
    expected = "igloo";
  };
}

{ lib, bindLib, ... }:
let
  inherit (bindLib) mergeStrategy mkMergeValidator;
in
{

  flake.tests.merge-strategy.test-constants = {
    expr = {
      bw = mergeStrategy.bindWins;
      sw = mergeStrategy.systemWins;
      err = mergeStrategy.error;
    };
    expected = {
      bw = "bind-wins";
      sw = "system-wins";
      err = "error";
    };
  };

  flake.tests.merge-strategy.test-fromBindings-detects-mergeStrategy = {
    expr = mergeStrategy.fromBindings {
      host = {
        _mergeStrategy = "system-wins";
        name = "igloo";
      };
      user = {
        name = "tux";
      };
    };
    expected = {
      host = "system-wins";
      user = null;
    };
  };

  flake.tests.merge-strategy.test-validator-no-collision-no-warnings = {
    expr =
      let
        validator = mkMergeValidator {
          resolvePolicy = _: "bind-wins";
          boundArgNames = [ "host" ];
          provenance = { };
        };
        result = validator { config._module.args = { }; };
      in
      result.warnings;
    expected = [ ];
  };

  flake.tests.merge-strategy.test-validator-bind-wins-warning = {
    expr =
      let
        validator = mkMergeValidator {
          resolvePolicy = _: "bind-wins";
          boundArgNames = [ "host" ];
          provenance = {
            host = {
              source = "test";
            };
          };
        };
        result = validator {
          config._module.args = {
            host = "something";
          };
        };
      in
      builtins.length result.warnings;
    expected = 1;
  };

  flake.tests.merge-strategy.test-validator-error-throws = {
    expr =
      let
        validator = mkMergeValidator {
          resolvePolicy = _: "error";
          boundArgNames = [ "host" ];
          provenance = { };
        };
      in
      !(builtins.tryEval (validator {
        config._module.args = {
          host = "x";
        };
      })).success;
    expected = true;
  };
}

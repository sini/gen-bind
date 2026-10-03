{ lib, genBind, ... }:
let
  inherit (genBind) mergeStrategy mkMergeValidator;
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

  # error-strategy throws on collision — lazily, when `.warnings` is demanded (the
  # validator is now evalModules-safe: no eager `seq`, so the throw surfaces on access,
  # not at module-collection WHNF). Force `.warnings` to observe it.
  flake.tests.merge-strategy.test-validator-error-throws = {
    expr =
      let
        validator = mkMergeValidator {
          resolvePolicy = _: "error";
          boundArgNames = [ "host" ];
          provenance = { };
        };
      in
      !(builtins.tryEval (
        (validator {
          config._module.args = {
            host = "x";
          };
        }).warnings
      )).success;
    expected = true;
  };

  # THE RESULT DOOR (den-hoag-d65u4): `resolvePolicy`'s codomain is the three declared policies, so a
  # result outside them is refused by name, catchably, where a collision reads it. WHAT A FAILING RUN
  # LOOKS LIKE: without the door, every shape below is read as `bind-wins` and the validator returns
  # the bind-wins warning, so each `success` reads `true`.
  flake.tests.merge-strategy.test-validator-refuses-a-non-policy-result-catchably = {
    expr =
      builtins.map
        (
          r:
          (builtins.tryEval (
            builtins.deepSeq
              (mkMergeValidator {
                resolvePolicy = _: r;
                boundArgNames = [ "host" ];
                provenance = { };
              } { config._module.args.host = "x"; }).warnings
              null
          )).success
        )
        [
          "sytem-wins"
          ""
          null
          5
          { }
          [ "bind-wins" ]
          (x: x)
        ];
    expected = [
      false
      false
      false
      false
      false
      false
      false
    ];
  };

  # Every declared policy behaves as before, each pinned by its own text: a door that refused a
  # declared value would turn its warning into a refusal, and `error`'s own message would change.
  flake.tests.merge-strategy.test-validator-every-declared-policy-behaves-as-before = {
    expr =
      builtins.map
        (
          r:
          let
            w =
              (mkMergeValidator {
                resolvePolicy = _: r;
                boundArgNames = [ "host" ];
                provenance = { };
              } { config._module.args.host = "x"; }).warnings;
            t = builtins.tryEval (builtins.deepSeq w w);
          in
          if t.success then t.value else "refused"
        )
        [
          mergeStrategy.bindWins
          mergeStrategy.systemWins
          mergeStrategy.error
        ];
    expected = [
      [ "gen-bind: binding 'host' collision — bind-wins, module-system value shadowed" ]
      [ "gen-bind: binding 'host' collision — system-wins, binding value dropped" ]
      "refused"
    ];
  };

  # The door is where a collision READS the policy, and only there: absent a collision `resolvePolicy`
  # is never applied, so even a throwing one is not reached and nothing is forced.
  flake.tests.merge-strategy.test-validator-reads-no-policy-absent-a-collision = {
    expr =
      (mkMergeValidator {
        resolvePolicy = _: throw "never read";
        boundArgNames = [ "host" ];
        provenance = { };
      } { config._module.args = { }; }).warnings;
    expected = [ ];
  };

  # The wrap route: a misspelled `mergeStrategies` entry reaches the validator through gen-bind's own
  # policy reader and is refused there, where it used to warn `bind-wins`.
  flake.tests.merge-strategy.test-wrap-misspelled-strategy-is-refused-at-a-collision = {
    expr =
      (builtins.tryEval (
        builtins.deepSeq
          (
            (genBind.wrap {
              bindings.host = "bound";
              mergeStrategies.host = "sytem-wins";
            } ({ host, config, ... }: { })).validator
              { config._module.args.host = "x"; }
          ).warnings
          null
      )).success;
    expected = false;
  };

  flake.testsError.merge-strategy = {
    test-validator-names-a-non-policy-string = {
      expr =
        (mkMergeValidator {
          resolvePolicy = _: "sytem-wins";
          boundArgNames = [ "host" ];
          provenance = { };
        } { config._module.args.host = "x"; }).warnings;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]mkMergeValidator: `resolvePolicy` returned \"sytem-wins\" for 'host', not one of \"bind-wins\", \"system-wins\", \"error\"$";
      };
    };
    test-validator-names-a-non-string-result-by-type = {
      expr =
        (mkMergeValidator {
          resolvePolicy = _: { };
          boundArgNames = [ "host" ];
          provenance = { };
        } { config._module.args.host = "x"; }).warnings;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]mkMergeValidator: `resolvePolicy` returned a set for 'host', not one of \"bind-wins\", \"system-wins\", \"error\"$";
      };
    };
    # `error` keeps its own refusal: a door that read `error` as a non-policy would still throw, and
    # only the text tells the two apart.
    test-validator-error-strategy-keeps-its-own-message = {
      expr =
        (mkMergeValidator {
          resolvePolicy = _: mergeStrategy.error;
          boundArgNames = [ "host" ];
          provenance = { };
        } { config._module.args.host = "x"; }).warnings;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind: binding 'host' collides with module-system arg — set mergeStrategy to resolve$";
      };
    };
    # RESIDUE: what `resolvePolicy` itself throws reaches the caller unchanged; the door decodes a
    # result, and a throw is not one.
    test-validator-residue-a-throwing-policy-throws-its-own-message = {
      expr =
        (mkMergeValidator {
          resolvePolicy = _: throw "policy-thrown";
          boundArgNames = [ "host" ];
          provenance = { };
        } { config._module.args.host = "x"; }).warnings;
      expectedError = {
        type = "ThrownError";
        msg = "^policy-thrown$";
      };
    };
  };
}

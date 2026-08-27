{ lib, genBind, ... }:
let
  inherit (genBind) buildSignature;
in
{

  flake.tests.signature.test-basic-structure = {
    expr =
      let
        sig = buildSignature {
          module =
            {
              host,
              config,
              lib,
              ...
            }:
            { };
          bindings = {
            host = {
              name = "igloo";
            };
          };
          defaultMergeStrategy = "bind-wins";
          mergeStrategies = { };
        };
      in
      {
        hasConfig = sig.requires ? config;
        hasLib = sig.requires ? lib;
        hostBound = sig.bound ? host;
        hostOptional = sig.bound.host.optional;
        unsatisfied = sig.unsatisfied;
      };
    expected = {
      hasConfig = true;
      hasLib = true;
      hostBound = true;
      hostOptional = false;
      unsatisfied = [ ];
    };
  };

  flake.tests.signature.test-optional-arg-marked = {
    expr =
      let
        sig = buildSignature {
          module =
            {
              host ? null,
              config,
              ...
            }:
            { };
          bindings = {
            host = {
              name = "igloo";
            };
          };
          defaultMergeStrategy = "bind-wins";
          mergeStrategies = { };
        };
      in
      sig.bound.host.optional;
    expected = true;
  };

  flake.tests.signature.test-merge-strategies-populated = {
    expr =
      let
        sig = buildSignature {
          module =
            {
              host,
              user,
              config,
              ...
            }:
            { };
          bindings = {
            host = { };
            user = { };
          };
          defaultMergeStrategy = "bind-wins";
          mergeStrategies = {
            host = "system-wins";
          };
        };
      in
      {
        hostStrat = sig.mergeStrategies.host;
        userStrat = sig.mergeStrategies.user;
      };
    expected = {
      hostStrat = "system-wins";
      userStrat = "bind-wins";
    };
  };

  # Prior defect: inVocabulary and isBound both tested `bindings`, so the
  # conjunction was unsatisfiable and this field was structurally always [].
  # `vocabulary` gives inVocabulary an independent source — a name the caller
  # declares forthcoming that this call's bindings didn't supply.
  flake.tests.signature.test-unsatisfied-reports-missing-vocabulary-key = {
    expr =
      let
        sig = buildSignature {
          module =
            {
              host,
              user,
              config,
              ...
            }:
            { };
          bindings = {
            host = {
              name = "igloo";
            };
          };
          defaultMergeStrategy = "bind-wins";
          mergeStrategies = { };
          vocabulary = [
            "host"
            "user"
          ];
        };
      in
      sig.unsatisfied;
    expected = [ "user" ];
  };

  flake.tests.signature.test-control-fully-satisfied-vocabulary-stays-empty = {
    expr =
      let
        sig = buildSignature {
          module =
            {
              host,
              user,
              config,
              ...
            }:
            { };
          bindings = {
            host = {
              name = "igloo";
            };
            user = {
              name = "tux";
            };
          };
          defaultMergeStrategy = "bind-wins";
          mergeStrategies = { };
          vocabulary = [
            "host"
            "user"
          ];
        };
      in
      sig.unsatisfied;
    expected = [ ];
  };

  flake.tests.signature.test-unsatisfied-excludes-optional-missing-vocabulary-key = {
    expr =
      let
        sig = buildSignature {
          module =
            {
              host,
              user ? null,
              config,
              ...
            }:
            { };
          bindings = {
            host = {
              name = "igloo";
            };
          };
          defaultMergeStrategy = "bind-wins";
          mergeStrategies = { };
          vocabulary = [
            "host"
            "user"
          ];
        };
      in
      sig.unsatisfied;
    expected = [ ];
  };

  flake.tests.signature.test-non-function-empty-signature = {
    expr =
      let
        sig = buildSignature {
          module = {
            services.nginx.enable = true;
          };
          bindings = {
            host = { };
          };
          defaultMergeStrategy = "bind-wins";
          mergeStrategies = { };
        };
      in
      {
        requires = sig.requires;
        bound = sig.bound;
      };
    expected = {
      requires = { };
      bound = { };
    };
  };
}

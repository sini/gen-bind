{ lib, bindLib, ... }:
let
  inherit (bindLib) buildSignature;
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

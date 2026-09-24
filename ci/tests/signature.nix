{ lib, genBind, ... }:
let
  inherit (genBind) buildSignature;

  # Collision fixtures: one bound arg `a` colliding with a module-system
  # `a` on the partial path (`config` stays unbound, so the module is not
  # called at wrap time and the call below plays the module-system side).
  collideMod =
    { a, config, ... }:
    {
      out = a;
    };
  annotated = {
    _mergeStrategy = "system-wins";
    v = "BINDING";
  };
  fixtures = {
    F0-plain.bindings.a.v = "BINDING";
    F1-annotation-only.bindings.a = annotated;
    F2-cfg-over-annotation = {
      bindings.a = annotated;
      mergeStrategies.a = "bind-wins";
    };
    F3-cfg-system = {
      bindings.a.v = "BINDING";
      mergeStrategies.a = "system-wins";
    };
  };
  # The signature of `cfg` through all three publishing routes.
  sigsOf = cfg: {
    wrap = (genBind.wrap ({ module = collideMod; } // cfg)).signature;
    wrapAll = builtins.head (genBind.wrapAll ({ modules = [ collideMod ]; } // cfg)).signatures;
    buildSignature = buildSignature {
      module = collideMod;
      inherit (cfg) bindings;
      defaultMergeStrategy = "bind-wins";
      mergeStrategies = cfg.mergeStrategies or { };
    };
  };
  runtimeWinner =
    cfg:
    let
      v =
        ((genBind.wrap ({ module = collideMod; } // cfg)).module {
          a = "SYSTEM";
          config = { };
        }).out;
    in
    if v == "SYSTEM" then "SYSTEM" else "BINDING";
  declaredVsAnnotation = cfg: {
    declared = builtins.mapAttrs (_: sig: sig.declaredMergeStrategies.a) (sigsOf cfg);
    annotation = (genBind.mergeStrategy.fromBindings cfg.bindings).a;
    runtime = runtimeWinner cfg;
  };
in
{
  # G1: the signature reports the strategy DECLARED AT THE CALL (cfg entry,
  # else default), not the effective one. The binding's own `_mergeStrategy`
  # wins at runtime and is read only through `fromBindings`.
  flake.tests.signature.test-declared-strategy-excludes-annotation = {
    expr = declaredVsAnnotation fixtures.F1-annotation-only;
    expected = {
      declared = {
        wrap = "bind-wins";
        wrapAll = "bind-wins";
        buildSignature = "bind-wins";
      };
      annotation = "system-wins";
      runtime = "SYSTEM";
    };
  };

  # G2: precedence pin — the cfg entry beats the annotation at runtime, so
  # `fromBindings` alone is not the effective strategy either.
  flake.tests.signature.test-cfg-strategy-outranks-annotation = {
    expr = declaredVsAnnotation fixtures.F2-cfg-over-annotation;
    expected = {
      declared = {
        wrap = "bind-wins";
        wrapAll = "bind-wins";
        buildSignature = "bind-wins";
      };
      annotation = "system-wins";
      runtime = "BINDING";
    };
  };

  # Live control for G1/G2's runtime reading: both winners are reachable.
  flake.tests.signature.test-runtime-winner-control = {
    expr = builtins.mapAttrs (_: runtimeWinner) fixtures;
    expected = {
      F0-plain = "BINDING";
      F1-annotation-only = "SYSTEM";
      F2-cfg-over-annotation = "BINDING";
      F3-cfg-system = "SYSTEM";
    };
  };

  # G3: the old output name is ABSENT (no tombstone) on every route.
  flake.tests.signature.test-old-strategy-field-absent = {
    expr = builtins.mapAttrs (
      _: cfg:
      builtins.mapAttrs (_: sig: {
        old = sig ? mergeStrategies;
        new = sig ? declaredMergeStrategies;
      }) (sigsOf cfg)
    ) fixtures;
    expected =
      let
        row = {
          old = false;
          new = true;
        };
        routes = {
          wrap = row;
          wrapAll = row;
          buildSignature = row;
        };
      in
      {
        F0-plain = routes;
        F1-annotation-only = routes;
        F2-cfg-over-annotation = routes;
        F3-cfg-system = routes;
      };
  };

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
        hostStrat = sig.declaredMergeStrategies.host;
        userStrat = sig.declaredMergeStrategies.user;
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

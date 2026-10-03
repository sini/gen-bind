# THE APPLICABILITY DOOR (den-hoag-k0whn) — every intake that APPLIES a caller's value, fed every
# shape. What Nix can apply is served as its lambda twin is; what it cannot, a functor whose chain
# does not reach a function within 32 `__functor` steps included, is refused by name, catchably.
#
# WHAT A FAILING RUN LOOKS LIKE: without the door, the refusal cell aborts UNCATCHABLY with Nix's own
# `attempt to call something which is not a function` (or `stack overflow; max-call-depth exceeded`
# on a self-returning `__functor`), naming neither the site nor the field.
{
  lib,
  genBind,
  graph,
  ...
}:
let
  X = genBind.crossing;
  mkDeep = n: f: if n == 0 then f else { __functor = _: mkDeep (n - 1) f; };
  # Every shape Nix applies: the value each site gives must be the lambda's.
  applicableOf = f: [
    f
    { __functor = _: f; }
    {
      __functor = _: f;
      __functionArgs = { };
    }
    { __functor = _: { __functor = _: f; }; }
    { __functor.__functor = _: _: f; }
    (mkDeep 32 f)
  ];
  notApplicable = f: [
    (mkDeep 33 f)
    { __functor = self: self; }
    { __functor = 5; }
    { __functor = _: 5; }
    { a = 1; }
    5
  ];
  modArgs = {
    inherit lib;
    config = { };
  };
  carriage = {
    extent = { };
    extraModules = [ ];
    peerGraph = graph.labeledFrom { peer = _id: [ ]; } [ ];
    marksOf = _id: [ ];
    readerId = "fixture";
  };
  hosted =
    evaluator: locateConfig:
    X.mkHostedTerminal {
      inherit evaluator locateConfig;
      class = "c";
    };
  validator =
    resolvePolicy:
    genBind.mkMergeValidator {
      inherit resolvePolicy;
      boundArgNames = [ "a" ];
      provenance = { };
    };
  # Each site: the lambda it is fed, and the value its first application gives.
  sites = {
    mkOutputsTerminal = {
      f = b: b.n;
      use = x: (X.mkOutputsTerminal x).adapter.wrapUnit { n = 1; } [ ];
    };
    mintIdentity = {
      f =
        k: _ls: _get:
        "id-${k}";
      # The refusal is a value here (pinned below); the generic cells read it as refused.
      use =
        x:
        let
          r = X.mintIdentity x "k" { a = "r"; };
        in
        if X.isRefusal r then throw r.refusal.code else r.value;
    };
    configGate-gate = {
      f = _args: true;
      use = x: (genBind.configGate { } x { } modArgs).config.condition;
    };
    configGate-adapt = {
      f = _args: { tag = 1; };
      use = x: (genBind.configGate { adapt = x; } (_: true) { } modArgs).config.content;
    };
    adaptArgs = {
      f = _args: { tag = 1; };
      use = x: (genBind.adaptArgs x { } modArgs)._module.args;
    };
    contract-mk = {
      f = v: v == 1;
      use = x: genBind.contract.apply (genBind.contract.mk { } x) 1 null;
    };
    contract-apply = {
      f = v: v == 1;
      use =
        x:
        genBind.contract.apply {
          __contract = true;
          check = x;
          message = "m";
        } 1 null;
    };
    mkMergeValidator = {
      f = _n: "system-wins";
      use = x: ((validator x) { config._module.args.a = 1; }).warnings;
    };
    mkHostedTerminal-evaluator = {
      f = a: a.specialArgs.nodes;
      use = x: ((hosted x (u: u)).adapter carriage).wrapUnit [ ] [ ];
    };
    mkHostedTerminal-locateConfig = {
      f = u: u.config;
      use = x: (hosted (_: { }) x).locateConfig { config = 1; };
    };
  };
  answers = s: map (x: builtins.deepSeq (s.use x) (s.use x)) (applicableOf s.f);
  refused =
    s: x:
    let
      r = builtins.tryEval (builtins.deepSeq (s.use x) null);
    in
    !r.success;
in
{
  flake.tests.applicable.test-every-applicable-shape-is-served-as-its-lambda-twin = {
    expr = builtins.mapAttrs (_: s: answers s) sites;
    expected = builtins.mapAttrs (_: s: map (_: s.use s.f) (applicableOf s.f)) sites;
  };

  flake.tests.applicable.test-every-shape-nix-cannot-apply-is-refused-catchably = {
    expr = builtins.mapAttrs (_: s: map (refused s) (notApplicable s.f)) sites;
    expected = builtins.mapAttrs (_: s: map (_: true) (notApplicable s.f)) sites;
  };

  # `mintIdentity` refuses as `mkOperations` refuses its mint: as a value, not a throw.
  flake.tests.applicable.test-mintIdentity-refuses-a-non-applicable-mint-as-a-value = {
    expr =
      map
        (
          x:
          let
            r = X.mintIdentity x "k" { a = "r"; };
          in
          [
            r.refusal.code
            r.refusal.witness.got
          ]
        )
        [
          { __functor = 5; }
          { __functor = self: self; }
          5
        ];
    expected = [
      [
        "declaration-missing-field"
        "a functor that does not reach a function"
      ]
      [
        "declaration-missing-field"
        "a functor that reaches no function within 32 `__functor` steps"
      ]
      [
        "declaration-missing-field"
        "a int"
      ]
    ];
  };

  # `locateConfig` is carried, not applied, so the Terminal field's documented `null` arm is served.
  flake.tests.applicable.test-mkHostedTerminal-carries-a-null-locateConfig = {
    expr = (hosted (_: { }) null).locateConfig;
    expected = null;
  };

  # The door fires where the value is applied, never at construction: these laziness contracts are
  # stated in `arg-env.nix` and `contract.nix`, and a never-applied value stays unforced.
  flake.tests.applicable.test-a-never-applied-value-is-not-refused = {
    expr = [
      (builtins.seq (genBind.adaptArgs 5 { }) true)
      (builtins.seq (genBind.configGate { adapt = 5; } 5 { }) true)
      (builtins.seq (genBind.contract.mk { } 5) true)
      (builtins.seq (genBind.mkMergeValidator {
        resolvePolicy = 5;
        boundArgNames = [ ];
        provenance = { };
      }) true)
      (builtins.seq (hosted 5 5).adapter true)
      ((genBind.configGate { adapt = 5; } (_: false) { } modArgs).config.condition)
    ];
    expected = [
      true
      true
      true
      true
      true
      false
    ];
  };

  flake.testsError.applicable = {
    test-mkOutputsTerminal-names-a-functor-that-reaches-no-function = {
      expr = (X.mkOutputsTerminal { __functor = 5; }).adapter;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]crossing[.]mkOutputsTerminal: `evaluate` must be a function from the Body to the outputs, or a functor whose `__functor` reaches one, not a functor that does not reach a function$";
      };
    };
    test-configGate-names-gate = {
      expr = (genBind.configGate { } { __functor = 5; } { } modArgs).config.condition;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]configGate: `gate` must be a function, or a functor whose `__functor` reaches one, not a functor that does not reach a function$";
      };
    };
    test-configGate-names-adapt = {
      expr = (genBind.configGate { adapt = 5; } (_: true) { } modArgs).config.content;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]configGate: `adapt` must be a function, or a functor whose `__functor` reaches one, not a int$";
      };
    };
    test-adaptArgs-names-adapt = {
      expr = (genBind.adaptArgs { a = 1; } { } modArgs)._module.args;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]adaptArgs: `adapt` must be a function, or a functor whose `__functor` reaches one, not a set$";
      };
    };
    test-contract-mk-names-check = {
      expr = genBind.contract.apply (genBind.contract.mk { } 5) 1 null;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]contract[.]mk: `check` must be a function, or a functor whose `__functor` reaches one, not a int$";
      };
    };
    test-contract-apply-names-check-on-a-hand-built-record = {
      expr = genBind.contract.apply {
        __contract = true;
        check = {
          __functor = _: 5;
        };
        message = "m";
      } 1 null;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]contract[.]apply: `check` must be a function, or a functor whose `__functor` reaches one, not a functor that does not reach a function$";
      };
    };
    test-mkMergeValidator-names-resolvePolicy = {
      expr = ((validator 5) { config._module.args.a = 1; }).warnings;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]mkMergeValidator: `resolvePolicy` must be a function, or a functor whose `__functor` reaches one, not a int$";
      };
    };
    test-mkHostedTerminal-names-evaluator-past-the-fuel = {
      expr = ((hosted { __functor = self: self; } (u: u)).adapter carriage).wrapUnit [ ] [ ];
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]crossing[.]mkHostedTerminal: `evaluator` must be a function, or a functor whose `__functor` reaches one, not a functor that reaches no function within 32 `__functor` steps$";
      };
    };
    test-mkHostedTerminal-names-locateConfig = {
      expr = (hosted (_: { }) 5).locateConfig;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]crossing[.]mkHostedTerminal: `locateConfig` must be a function, or a functor whose `__functor` reaches one, not a int$";
      };
    };
    # THE RESIDUE, pinned (den-hoag-g8lo): the door runs the caller's `__functor` on the set itself,
    # as Nix's own call does first, so a `__functor` that cannot take its set aborts inside the door
    # exactly as the application would. It is the caller's code failing, not a shape the door can
    # decide without running it.
    test-residue-a-functor-that-cannot-take-its-own-set-aborts-in-the-door = {
      expr = (genBind.adaptArgs { __functor = { missing }: _: { }; } { } modArgs)._module.args;
      expectedError = {
        type = "TypeError";
        msg = "called without required argument 'missing'";
      };
    };
  };
}

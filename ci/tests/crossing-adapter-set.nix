# The ADAPTER SET's acceptance oracles — ADR-0031 F2's migration of gen-flake's
# `inject.nix` and `terminals.nix` into the crossing.
#
# Oracle: specs/2026-08-24-gen-flake-crossing-adapter-spec.md §3. Ten oracles,
# every one CELL-SCOPED by the standing oracle rule: no cell here reads a whole
# suite, in any repository — a whole-suite read cannot register a genuine pass
# and would attribute an unrelated red to this subject.
#
# ★ EVERY ORACLE NAMES WHAT A FAILING RUN LOOKS LIKE. An oracle whose
# seeded-defect arm produces the same reading as its pass arm has measured
# nothing, so where a seed is constructible inline it is present as a LIVE CELL
# rather than as a claim about a run someone once did.
#
# ★★ A7 — WHAT IS ALREADY LANDED IS CITED, NOT RE-WRITTEN. Per oracle:
#   O-REF-1  `crossing-operations.nix:672` test-close-refuses-an-incoherent-fleet
#            already exercises the containment refusal THROUGH `close` and
#            asserts `codeOf` only. THE DELTA HERE IS THE WITNESS CONTENT
#            THROUGH `close` — the witness assertion existed only at the
#            `coherence` level (`crossing-linkset.nix:200`).
#   O-TRM-2  the acceptance half and both refusal rows are landed against a
#            synthesised adapter (`crossing-adapter.nix:91`, `:98`, `:127`,
#            `:137`, `:204`). The delta is three things: the flake adapter
#            INSTANCE, the no-crossings control, and the seeded defect.
#   O-TRM-3  `merge-strategy.nix:75` test-validator-error-throws is the shipped
#            path's throw. The delta is the wrapAll-append vs crossing-path
#            comparison, which that cell does not make.
#   O-TRM-4  AUDITED, and there is NO transfer to take: the predicate `config`
#            over all seven `crossing-*` suites returns 5 hits, none of them an
#            evaluated-config locator (they are a `TargetId -> config` carrier
#            string, a `functionArgs` probe and a `readFrom` path cell).
#            Positive control on the same instrument in the same run: `adapter`
#            ⇒ 56 hits. Negative control: `zurbin-q41x` ⇒ 0, rc=1.
#   O-INJ-1  none available — no cell in the ecosystem demonstrates that a
#            `Substrate`-placed value is determined before the target's fixpoint
#            runs. Every landed `Time` assertion is a label comparison on
#            `placement`'s output. These are the first cells of their kind.
#
# ★★★ O-INJ-2 IS NOT HERE, AND ITS ABSENCE IS A DECISION. It requires a real
# `composed.values` produced by `compose`, which gen-bind cannot reach —
# gen-bind depends on gen-prelude and nothing else. It was RUN as an evaluation
# and its verdict is recorded at the site it governs, in
# `lib/crossing-adapter-set.nix`'s ADR-0023 declaration. Its nearest landed
# neighbour is gen-flake's `ci/tests/flake-module.nix`
# `test-invariant-type-is-data-not-option`, which already proves END-TO-END that a
# gen TYPE object is carried as data inside the injected values — but it asserts
# `isAttrs` and a type NAME, never that a FUNCTION is transitively reachable,
# which is the predicate ADR-0023 actually gates on. Its permanent cell belongs
# in the hub's suite once the inject site re-points there; it is NOT manufactured
# a home in a repository scheduled for orphaning.
{
  genBind,
  lib,
  ...
}:
let
  f = import ./_crossing-fixtures.nix { inherit genBind; };
  inherit (f)
    x
    t
    sig
    imp
    proj
    supply
    plainB
    termedB
    wrappedB
    codeOf
    blameOf
    pipeline
    ;

  c = x.contractTerm;

  inherit (genBind.crossing) injectAdapter mkSystemTerminal mkFlakeTerminal;

  # ── inject fixtures ──────────────────────────────────────────────────────────

  # A stand-in for `composed.values`: substrate-resolved, plain, and nothing
  # about it is read from a target's config.
  resolvedValues = {
    hosts.igloo.addr = "10.0.0.1";
    id_hash = "cafebabe";
    probe = "probe-value";
  };

  # ★ THE INSTRUMENT FOR PRE-FIXPOINT-NESS (O-INJ-1). The Body carries a `throw`
  # at the position the consuming target's fixpoint would force. A cell that only
  # compared values would pass whether or not that fixpoint was entered — a label
  # read wearing a behavioural description. Forcing the BOUND VALUE successfully
  # while this sits in the Body is positive evidence the poisoned position was
  # never demanded.
  poisonedBody = {
    config.poison = throw "O-INJ-1: the consuming target's fixpoint was entered";
  };

  injectClosed = pipeline {
    imports.genValues = imp c.any;
    bindings.genValues = plainB resolvedValues;
    withAdapter = injectAdapter;
    body = poisonedBody;
  };

  # ── the O-INJ-3 module set. `unseenModule` is reached ONLY by a target-side
  #    `imports` computed inside a FUNCTION module's body, so no substrate-side
  #    walk of the Body can find it — which is exactly the population that
  #    discriminates an arg-environment writer from a formal partial-application.
  #
  # ★ IT NAMES `genValues` AS A FORMAL, AND THAT IS FORCED RATHER THAN
  #   STYLISTIC. Measured while building this cell: nixpkgs delivers
  #   `_module.args` entries ONLY for the formals a module NAMES —
  #   `applyModuleArgs` builds them from `builtins.functionArgs f` — so a module
  #   written `{ ... }@args:` receives nothing from the arg environment at all
  #   and reads `UNREACHED` under BOTH implementations. An earlier draft of this
  #   cell used that shape to keep the failing arm total, and it measured
  #   nothing.
  unseenModule =
    { genValues, ... }:
    {
      config.unseenReached = genValues.probe;
    };

  carrierModule =
    { ... }:
    {
      imports = [ unseenModule ];
    };

  seenReaderModule =
    { genValues, ... }:
    {
      config.seenReached = genValues.probe;
    };

  optionsModule = {
    options.unseenReached = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    options.seenReached = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    options.result = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    options.other = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
  };

  reachBody = {
    imports = [
      seenReaderModule
      carrierModule
    ];
  };

  # ★ THE RIVAL'S BODY CARRIES ONLY THE SEEN READER, AND THE OMISSION IS THE
  #   MEASUREMENT'S OWN CONSTRAINT rather than a convenience. Under a partial
  #   application the unseen module's `genValues` formal has no satisfying
  #   argument anywhere, and an absent module argument is an evaluation ERROR,
  #   not a `throw` — `builtins.tryEval` does not catch it, so a cell written to
  #   observe that failure aborts the suite instead of reporting. The failure is
  #   therefore measured one step earlier, at the channel: the rival writes NO
  #   arg environment, and `_module.args` is the only channel by which a module
  #   the substrate never saw can receive a name at all.
  rivalBody = {
    imports = [ seenReaderModule ];
  };

  reachClosed = pipeline {
    imports.genValues = imp c.any;
    bindings.genValues = plainB resolvedValues;
    withAdapter = injectAdapter;
    body = reachBody;
  };

  reachEval = lib.evalModules {
    modules = [
      optionsModule
      reachClosed.value
    ];
  };

  # The rival implementation, built here so the two can be run side by side:
  # `bindFormals` as `wrapAll`'s partial application into module formals. It is
  # the reading §2.2.2 argues AGAINST, and the cell below is what makes that
  # argument falsifiable rather than rhetorical.
  partialApplicationAdapter = injectAdapter // {
    bindFormals = values: body: {
      imports =
        (genBind.wrapAll {
          modules = [ body ];
          bindings = values;
        }).modules;
    };
  };

  partialApplicationClosed = pipeline {
    imports.genValues = imp c.any;
    bindings.genValues = plainB resolvedValues;
    withAdapter = partialApplicationAdapter;
    body = rivalBody;
  };

  partialApplicationEval = lib.evalModules {
    modules = [
      optionsModule
      partialApplicationClosed.value
    ];
  };

  # ── the system terminal ──────────────────────────────────────────────────────

  classModule =
    { host, ... }:
    {
      config.result = host.name;
    };

  unrelatedModule =
    { ... }:
    {
      config.other = "untouched";
    };

  extraModule = {
    config.seenReached = "from-extraModules";
  };

  systemTerminal = mkSystemTerminal {
    evaluator = a: {
      config = {
        built = a.modules;
        inherit (a) specialArgs;
      };
    };
    locateConfig = u: u.config;
  };

  systemAdapter = systemTerminal.adapter {
    extent = {
      peer.config.addr = "10.0.0.2";
    };
    extraModules = [ extraModule ];
  };

  systemClosed = pipeline {
    imports.host = imp c.any;
    bindings.host = plainB { name = "alpha"; };
    withAdapter = systemAdapter;
    body = [
      classModule
      unrelatedModule
    ];
  };

  # ★ THE SECOND CARRIAGE, and its asymmetry with the first is load-bearing. The
  # target-owned field is a CONDITIONAL splice, and until this fixture existed no
  # cell in this suite entered its true branch: every carriage above omits the
  # field. A defect in that branch was invisible, and an equality taken over a
  # carriage that never carries one measures half the contract.
  systemAdapterOwned = systemTerminal.adapter {
    extent = {
      peer.config.addr = "10.0.0.2";
    };
    extraModules = [ extraModule ];
    # The channel's CONTENT is the consumer's own vocabulary. `osConfig` is
    # home-manager's arg name and is correct HERE — framework naming is surface
    # vocabulary at the surface; what was wrong was pinning it as a carriage field.
    passthrough.osConfig.marker = "target-owned";
  };

  systemClosedOwned = pipeline {
    imports.host = imp c.any;
    bindings.host = plainB { name = "alpha"; };
    withAdapter = systemAdapterOwned;
    body = [
      classModule
      unrelatedModule
    ];
  };

  specialArgsOf = closed: (systemTerminal.locateConfig closed.value).specialArgs;
  specialArgKeysOf =
    closed: builtins.sort builtins.lessThan (builtins.attrNames (specialArgsOf closed));

  # ★ THE SWEEP-PRODUCED ADAPTER, kept live as O-WELD-2's seeded defect rather
  # than performed once. This is step 2 done WITHOUT step 1: the rename followed
  # the `inherit`, so the carriage name reaches straight through to the target
  # key and every class module reading `nodes.<peer>` breaks inside the target's
  # own evaluation.
  weldFollowingSpecialArgs =
    carriage:
    {
      inherit (carriage) extent;
    }
    // (carriage.passthrough or { });

  # A class module written the way class modules are written: it NAMES `nodes` as
  # a formal and reads a peer's resolved config through it. This is the reader
  # O-WELD-2 exists for, and it is evaluated THROUGH the module system rather than
  # inspected as data — the target-facing contract is only real at the target.
  peerReaderModule =
    { nodes, ... }:
    {
      options.peerAddr = lib.mkOption {
        type = lib.types.str;
        default = "";
      };
      config.peerAddr = nodes.peer.config.addr;
    };

  targetEval =
    closed:
    lib.evalModules {
      modules = [
        optionsModule
        peerReaderModule
      ]
      ++ (systemTerminal.locateConfig closed.value).built;
      specialArgs = specialArgsOf closed;
    };

  systemEval = lib.evalModules {
    modules = [ optionsModule ] ++ (systemTerminal.locateConfig systemClosed.value).built;
  };

  # ── the flake terminal ───────────────────────────────────────────────────────

  # The flake-module evaluator, INJECTED exactly as the system evaluator is. A
  # stub is the right instrument: the adapter's whole contract at this position
  # is that it hands the Body and the systems to the evaluator it was given.
  flakeTerminal = mkFlakeTerminal {
    evalFlakeModule = argsIn: mod: {
      config.flake = {
        modulesSeen = mod.imports;
        inherit (mod) systems;
        inputsSeen = builtins.attrNames argsIn.inputs;
      };
    };
    inputs = {
      upstream = "an-input";
    };
    self = "the-self";
    systems = [ "x86_64-linux" ];
  };

  flakeModuleBody = [ { config.packages = { }; } ];

  flakeSubstrateName = pipeline {
    imports.v = imp c.any;
    bindings.v = plainB 1;
    withAdapter = flakeTerminal.adapter;
    body = flakeModuleBody;
  };

  flakeInvokedName = pipeline {
    imports.v = imp c.any;
    bindings.v = termedB (t.readFrom "igloo" [ "x" ]);
    withAdapter = flakeTerminal.adapter;
    body = flakeModuleBody;
  };

  flakeNoCrossings = pipeline {
    imports = { };
    bindings = { };
    withAdapter = flakeTerminal.adapter;
    body = flakeModuleBody;
  };

  # ★ THE SEEDED DEFECT §2.3.3(a) NAMES: grow `bindFormals` onto the flake
  #   adapter. Present as a live cell so the normative rule is ARMED rather than
  #   stated — the census's by-construction zero would otherwise become an
  #   as-authored one with every fixture still green.
  grownFlakeAdapter = flakeTerminal.adapter // {
    bindFormals = _values: body: body;
  };

  flakeSeeded = pipeline {
    imports.v = imp c.any;
    bindings.v = plainB 1;
    withAdapter = grownFlakeAdapter;
    body = flakeModuleBody;
  };

  # ── the merge-collision residue ──────────────────────────────────────────────

  collidingValue = {
    _mergeStrategy = "error";
    name = "alpha";
  };

  collisionModules = [ classModule ];

  crossingPathModules =
    (systemTerminal.adapter {
      extent = { };
      extraModules = [ ];
    }).bindFormals
      { host = collidingValue; }
      collisionModules;

  shippedPath = genBind.wrapAll {
    modules = collisionModules;
    bindings = {
      host = collidingValue;
    };
  };

  collisionClosed = pipeline {
    imports.host = imp c.any;
    bindings.host = plainB collidingValue;
    withAdapter = systemAdapter;
    body = collisionModules;
  };

  # ── the per-terminal evaluated-config locator ────────────────────────────────

  # Two terminals over the SAME crossing. The first's artifact HOLDS its config
  # at `.config`; the second's artifact IS the config — the shape the gen-aspects
  # demo terminal has, where `realized.<class>.<host>` is already the config.
  dotConfigTerminal = mkSystemTerminal {
    evaluator = a: {
      config = {
        built = a.modules;
      };
    };
    locateConfig = u: u.config;
  };

  isConfigTerminal = mkSystemTerminal {
    evaluator = a: {
      built = a.modules;
    };
    locateConfig = u: u;
  };

  locatorArgs = {
    imports.host = imp c.any;
    bindings.host = plainB { name = "alpha"; };
    body = [ classModule ];
  };

  dotConfigClosed = pipeline (
    locatorArgs
    // {
      withAdapter = dotConfigTerminal.adapter {
        extent = { };
        extraModules = [ ];
      };
    }
  );

  isConfigClosed = pipeline (
    locatorArgs
    // {
      withAdapter = isConfigTerminal.adapter {
        extent = { };
        extraModules = [ ];
      };
    }
  );
in
{
  # ══ O-REF-1 — the containment refusal, unqualified, THROUGH `close` ══════════
  #
  # A7: the CODE-through-`close` arm is landed at
  # `crossing-operations.nix:672` (`test-close-refuses-an-incoherent-fleet`),
  # which asserts `codeOf` and nothing else. The delta is the WITNESS.
  #
  # WHAT A FAILING RUN LOOKS LIKE: the refusal fires but its witness omits the
  # offending member or the member list, so the fleet is told that something
  # refused without being told WHO to blame or WHAT was out of bounds. That is
  # the seeded defect the oracle turns on, and asserting the witness set exactly
  # is what makes the cell fail on it rather than on the code.
  flake.tests.crossing-adapter-set.test-o-ref-1-close-containment-witness-names-the-offender-and-the-members = {
    expr =
      (pipeline {
        imports.peer = imp c.any;
        bindings.peer = termedB (t.readFrom "iceberg" [ "x" ]);
        members = [ "igloo" ];
      }).refusal.witness;
    expected = {
      offending = [ "iceberg" ];
      environment = [ "iceberg" ];
      members = [ "igloo" ];
    };
  };

  flake.tests.crossing-adapter-set.test-o-ref-1-close-containment-blames-the-declarer = {
    expr = blameOf (pipeline {
      imports.peer = imp c.any;
      bindings.peer = termedB (t.readFrom "iceberg" [ "x" ]);
      members = [ "igloo" ];
    });
    expected = "declarer";
  };

  # ★ THE CONTROL, AND IT IS NOT THE ONE THE SPEC SKETCHED. §3's O-REF-1 says
  #   "the same fleet with that target added to `members` closes". Measured: it
  #   does NOT — a `readFrom` is unobtainable substrate-side at ANY membership,
  #   so containment is not what stands between that fleet and a close. The
  #   control that actually discriminates is that the refusal CHANGES: with the
  #   target contained, the containment row stops firing and the obtainability
  #   row takes over. A control that could not distinguish the two would leave
  #   the cell asserting only that something refused.
  flake.tests.crossing-adapter-set.test-control-o-ref-1-containment-refusal-is-about-containment = {
    expr = {
      outside = codeOf (pipeline {
        imports.peer = imp c.any;
        bindings.peer = termedB (t.readFrom "iceberg" [ "x" ]);
        members = [ "igloo" ];
      });
      contained = codeOf (pipeline {
        imports.peer = imp c.any;
        bindings.peer = termedB (t.readFrom "iceberg" [ "x" ]);
        members = [
          "igloo"
          "iceberg"
        ];
      });
    };
    expected = {
      outside = "linkset-incoherent";
      contained = "value-not-obtainable";
    };
  };

  flake.tests.crossing-adapter-set.test-control-o-ref-1-an-empty-environment-closes = {
    expr = x.isOk (pipeline {
      imports.plain = imp c.any;
      bindings.plain = plainB 1;
      members = [ "igloo" ];
    });
    expected = true;
  };

  # ══ O-REF-2 — the F6 LOUD ceiling, re-expressed at the crossing's altitude ═══
  #
  # den-hoag already refuses this class by name: "a config-dependent (deferred)
  # emission on a collected channel aborts at the consumer's gather — never a
  # silent wrong value". The crossing's analogue is a binding whose δ names a
  # PRODUCER: the demand set is APPROX, so the congruence predicate passed over a
  # set that under-approximates and a substrate placement on it would substitute
  # a value before the fixpoint determining it had run.
  #
  # WHAT A FAILING RUN LOOKS LIKE: the binding is admitted at `(Formals,
  # Substrate)` and the fleet gets a value computed from an under-approximated
  # demand set — the silent wrong value the F6 ceiling exists to convert.
  flake.tests.crossing-adapter-set.test-o-ref-2-a-deferred-emission-refuses-by-name-at-close = {
    expr = codeOf (pipeline {
      imports.emitted = imp c.any;
      bindings.emitted = wrappedB "iceberg" (_targetArgs: "deferred");
      members = [ "igloo" ];
    });
    expected = "substrate-placement-inexact-demand";
  };

  flake.tests.crossing-adapter-set.test-o-ref-2-the-refusal-names-the-analysis-limit-that-caused-it = {
    expr =
      (pipeline {
        imports.emitted = imp c.any;
        bindings.emitted = wrappedB "iceberg" (_targetArgs: "deferred");
        members = [ "igloo" ];
      }).refusal.witness.deltaExact;
    expected = "APPROX";
  };

  # ★ THE CONTROL IS THE COMPANION PATH den-hoag MEASURES AS LIVE AND PASSING:
  #   resolution at the PRODUCER rather than at the consumer's gather. Its
  #   crossing analogue is a value already resolved when it crosses — a `Plain`
  #   binding — and it must close cleanly IN THE SAME RUN. Without it the suite
  #   has shown that something refuses, not that the refusal discriminates.
  flake.tests.crossing-adapter-set.test-control-o-ref-2-producer-side-resolution-closes-cleanly = {
    expr = x.isOk (pipeline {
      imports.emitted = imp c.any;
      bindings.emitted = plainB "resolved-at-the-producer";
      members = [ "igloo" ];
    });
    expected = true;
  };

  # ══ O-INJ-1 — `Substrate` MEANS PRE-FIXPOINT, AND THIS MEASURES IT ══════════
  #
  # ★★ NOTHING IN THE ECOSYSTEM DEMONSTRATED THIS BEFORE. Every landed `Time`
  # assertion is a label comparison on `placement`'s output, and `placement` is a
  # pure two-branch read: for a `Plain` binding against a `bindFormals`-offering
  # adapter it CANNOT return anything but `(Formals, Substrate)`. A cell
  # asserting that label has a pass arm and a seeded arm that read identically.
  # These cells measure the property the coordinate NAMES instead.
  #
  # WHAT A FAILING RUN LOOKS LIKE: forcing the bound value reaches the poisoned
  # position and the cell throws — which is what would happen if the successor's
  # `bindFormals` produced anything requiring the consuming target's fixpoint.
  flake.tests.crossing-adapter-set.test-o-inj-1-a-substrate-placed-value-forces-with-the-targets-fixpoint-poisoned = {
    expr = (builtins.tryEval (builtins.deepSeq injectClosed.value._module.args true)).success;
    expected = true;
  };

  # ★ WITHOUT THIS THE PASS ARM IS VACUOUS. A successful force is evidence the
  #   poisoned position was never demanded ONLY IF the poison would actually have
  #   thrown. This arm forces it and observes the throw, in the same run.
  flake.tests.crossing-adapter-set.test-control-o-inj-1-the-poison-is-live = {
    expr =
      (builtins.tryEval (builtins.deepSeq (builtins.head injectClosed.value.imports) true)).success;
    expected = false;
  };

  flake.tests.crossing-adapter-set.test-o-inj-1-the-value-the-target-observes-is-the-substrates = {
    expr = injectClosed.value._module.args.genValues;
    expected = resolvedValues;
  };

  # ★ THE SEEDED ARM, AND IT GENUINELY FAILS. The same name made
  #   fixpoint-dependent — its resolution requires the CONSUMING target's config
  #   — must not reach a `Substrate` placement. Under the landed rule it becomes
  #   `staticityAdmissible = false` and, this adapter offering neither `wrapFn`
  #   nor `bindArgEnv`, is refused by name. A run in which both arms produced a
  #   `Substrate` placement would have re-read a label rather than tested the
  #   coordinate.
  flake.tests.crossing-adapter-set.test-o-inj-1-seed-a-fixpoint-dependent-value-never-reaches-substrate = {
    expr = codeOf (pipeline {
      imports.genValues = imp c.any;
      bindings.genValues = termedB (t.readFrom "igloo" [ "cfg" ]);
      withAdapter = injectAdapter;
      body = poisonedBody;
    });
    expected = "adapter-missing-target-invoked-channel";
  };

  # ★ THE SECOND CONTROL, ON THE EXACTNESS AXIS: a non-empty but APPROX demand
  #   set is REFUSED rather than admitted, which is what discriminates "proved
  #   safe" from "could not prove" — the distinction the landed comment says
  #   collapsing would lose the witness.
  flake.tests.crossing-adapter-set.test-control-o-inj-1-an-approx-demand-is-refused-not-admitted = {
    expr = codeOf (pipeline {
      imports.genValues = imp c.any;
      bindings.genValues = wrappedB "iceberg" (_targetArgs: resolvedValues);
      withAdapter = injectAdapter;
      body = poisonedBody;
    });
    expected = "substrate-placement-inexact-demand";
  };

  # ══ O-INJ-3 — THE REACH OF `bindFormals` AT THE INJECT SITE ═════════════════
  #
  # This is the cell that decides §2.2.2's extension. `_module.args` propagates
  # to every module in the target's evaluation, including modules the substrate
  # never saw; a `wrapAll`-style partial application reaches only the wrapped
  # set. `unseenModule` is reached ONLY through an `imports` computed inside a
  # function module's body, so no substrate-side walk can find it.
  #
  # WHAT A FAILING RUN LOOKS LIKE: the unseen module's `genValues` formal is
  # unsatisfied and `evalModules` aborts — which is precisely what the rival
  # implementation does, one cell down.
  flake.tests.crossing-adapter-set.test-o-inj-3-an-unseen-module-reads-the-bound-name = {
    expr = reachEval.config.unseenReached;
    expected = "probe-value";
  };

  # ★ THE CONTROL. If only the unseen arm were present the cell could not tell
  #   the two implementations apart — BOTH satisfy a module the substrate saw.
  #   It is the pair that discriminates, not either arm.
  flake.tests.crossing-adapter-set.test-control-o-inj-3-a-seen-module-reads-the-bound-name = {
    expr = reachEval.config.seenReached;
    expected = "probe-value";
  };

  # ★★ THE DISCRIMINATOR, LIVE, AND IT DECIDES §2.2.2's EXTENSION. Measured at
  #    the CHANNEL, because that is where the difference is total: the
  #    arg-environment writer puts the name in the target's `_module.args`, which
  #    is the only channel reaching a module the substrate never saw; the rival
  #    partial-application writes no arg environment at all, so the unseen module
  #    has nowhere to read from. Both implementations satisfy the SEEN module —
  #    that pair is the measurement, not either arm, and it is why an
  #    unseen-only cell could not tell the two apart.
  flake.tests.crossing-adapter-set.test-o-inj-3-a-partial-application-bindFormals-writes-no-arg-environment = {
    expr = {
      argEnvWriter = reachEval._module.args ? genValues;
      partialApplication = partialApplicationEval._module.args ? genValues;
      bothReachTheSeenModule = {
        argEnvWriter = reachEval.config.seenReached;
        partialApplication = partialApplicationEval.config.seenReached;
      };
    };
    expected = {
      argEnvWriter = true;
      partialApplication = false;
      bothReachTheSeenModule = {
        argEnvWriter = "probe-value";
        partialApplication = "probe-value";
      };
    };
  };

  # ══ O-INJ-4 — parity at the live consumer shape ═════════════════════════════
  #
  # Both live `injectArgs` consumers read `._module.args` straight back out. The
  # successor must produce exactly what they unwrap today.
  #
  # WHAT A FAILING RUN LOOKS LIKE: the arg name or the payload shape moved, and
  # every consumer module writing `{ genValues, ... }: …` silently stops
  # receiving it.
  flake.tests.crossing-adapter-set.test-o-inj-4-the-successor-produces-the-live-consumer-shape = {
    expr = injectClosed.value._module.args;
    expected = {
      genValues = resolvedValues;
    };
  };

  # ★ Without this the cell compares something to itself: a deliberately renamed
  #   key must make the comparison fail.
  flake.tests.crossing-adapter-set.test-control-o-inj-4-a-renamed-key-fails-the-comparison = {
    expr =
      (pipeline {
        imports.genSchema = imp c.any;
        bindings.genSchema = plainB resolvedValues;
        withAdapter = injectAdapter;
        body = poisonedBody;
      }).value._module.args == {
        genValues = resolvedValues;
      };
    expected = false;
  };

  # ══ O-TRM-1 — the system adapter binds formals ══════════════════════════════
  #
  # WHAT A FAILING RUN LOOKS LIKE: the class module's `host` formal is
  # unsatisfied and `evalModules` aborts, or it is satisfied with something other
  # than the crossing's resolved value.
  flake.tests.crossing-adapter-set.test-o-trm-1-a-class-module-reads-the-binding-from-its-formals = {
    expr = systemEval.config.result;
    expected = "alpha";
  };

  # ★★ THE CONTROL, AND IT IS THE §2.2.2 DELTA MEASURED FROM THE TERMINAL SIDE.
  #    Without an arm like this the cell cannot distinguish "bound correctly"
  #    from "bound everywhere" — a value reaching the module that named it is
  #    equally consistent with an arg environment that reached every module in
  #    the evaluation. The system terminal realizes `Formals` as `wrapAll`'s
  #    PARTIAL APPLICATION, so the binding must NOT appear in the target's arg
  #    environment; the inject adapter realizes it as an arg-environment WRITER,
  #    where it must. Same coordinate, two admissible constructions, and the two
  #    are told apart here.
  flake.tests.crossing-adapter-set.test-control-o-trm-1-the-binding-is-bound-into-formals-not-into-the-arg-environment = {
    expr = {
      readByTheModuleThatNamesIt = systemEval.config.result;
      presentInTheTargetsArgEnvironment = systemEval._module.args ? host;
      unrelatedModuleIsUntouched = systemEval.config.other;
      # The other construction, in the same run: there it IS in the arg
      # environment, which is what makes the line above a measurement rather
      # than an accident of this fixture.
      presentUnderTheInjectAdapter = injectClosed.value._module.args ? genValues;
    };
    expected = {
      readByTheModuleThatNamesIt = "alpha";
      presentInTheTargetsArgEnvironment = false;
      unrelatedModuleIsUntouched = "untouched";
      presentUnderTheInjectAdapter = true;
    };
  };

  # `extraModules` is CARRIAGE — closure-captured, never a `TargetUnit`.
  # `subUnits` is fed exclusively by `bindArgEnv`, which this adapter sets to
  # `null`, so the `[TargetUnit]` argument is `[ ]` by construction.
  flake.tests.crossing-adapter-set.test-o-trm-1-extraModules-rides-the-closure-not-the-target-unit-list = {
    expr = {
      appended = builtins.elem extraModule (systemTerminal.locateConfig systemClosed.value).built;
      count = builtins.length (systemTerminal.locateConfig systemClosed.value).built;
    };
    expected = {
      appended = true;
      count = 3;
    };
  };

  # `nodes` is the CARRIAGE RESIDUE §2.3.4 names — it reaches the target through
  # `specialArgs`, not as a placed `Binding`, so δ cannot see it and `E(u)`
  # cannot count it. The cell asserts the residue rather than pretending it is
  # governed.
  flake.tests.crossing-adapter-set.test-o-trm-1-nodes-reaches-the-target-as-carriage-outside-the-governed-surface = {
    expr = (systemTerminal.locateConfig systemClosed.value).specialArgs.nodes.peer.config.addr;
    expected = "10.0.0.2";
  };

  # ══ THE WELD, SPLIT ═════════════════════════════════════════════════════════
  #
  # `inherit nodes;` made ONE identifier serve two contracts — the carriage formal
  # the fold supplies and the target-facing key a class module reads. Splitting is
  # behaviour-neutral and changes no name on either side; what it buys is that a
  # later rename of the carriage cannot reach the target key through an `inherit`.
  #
  # WHAT A FAILING RUN LOOKS LIKE: the target-facing key set changes, or the
  # emitted key takes a different field of the carriage than the one it names.
  flake.tests.crossing-adapter-set.test-weld-split-target-args-without-the-passthrough = {
    expr = specialArgKeysOf systemClosed;
    expected = [ "nodes" ];
  };
  # The other arm of the conditional, over the same terminal in the same run.
  flake.tests.crossing-adapter-set.test-weld-split-target-args-with-the-passthrough = {
    expr = specialArgKeysOf systemClosedOwned;
    expected = [
      "nodes"
      "osConfig"
    ];
  };
  flake.tests.crossing-adapter-set.test-weld-split-passthrough-rides-verbatim = {
    expr = (specialArgsOf systemClosedOwned).osConfig;
    expected = {
      marker = "target-owned";
    };
  };
  # CONTROL against a blind cell — the emitted key is paired with the carriage
  # field it NAMES, not with whatever else the carriage happens to hold. The same
  # comparison against a different field of the same carriage is false.
  flake.tests.crossing-adapter-set.test-weld-split-emitted-key-is-paired-with-its-own-field = {
    expr = {
      pairedWithItsOwnField =
        (specialArgsOf systemClosedOwned).osConfig == {
          marker = "target-owned";
        };
      pairedWithAnotherField = (specialArgsOf systemClosedOwned).nodes == [ extraModule ];
    };
    expected = {
      pairedWithItsOwnField = true;
      pairedWithAnotherField = false;
    };
  };

  # ══ O-NAME-1b — THE CARRIAGE FORMAL ═════════════════════════════════════════
  #
  # ★ SITE-SCOPED BY CONSTRUCTION, AND THAT IS THE WHOLE POINT. The predicate is
  # `functionArgs` over the adapter itself, so its domain is exactly the carriage
  # formal set and nothing else. A token-scoped version of this claim goes GREEN
  # by renaming `nodes` anywhere in this repository — and 21 of the 28 bare-token
  # sites here are the crossing's OWN minted nodes and the `Lit` node budget,
  # which are the ruled substrate term used CORRECTLY. Renaming those is the
  # broken outcome, and a token sweep passes on it.
  #
  # WHAT A FAILING RUN LOOKS LIKE: `nodes` reappears as a carriage formal — the
  # delivery surface's rename reverted or half-applied.
  flake.tests.crossing-adapter-set.test-o-name-1b-carriage-formals-carry-no-framework-name = {
    expr = builtins.sort builtins.lessThan (
      builtins.attrNames (builtins.functionArgs systemTerminal.adapter)
    );
    expected = [
      "extent"
      "extraModules"
    ];
  };
  # CONTROL, same predicate, same run — `nodes` is genuinely absent from the
  # carriage formals while being genuinely PRESENT one contract over, in the
  # target args. An absence read over an unreachable formal set would look
  # identical to the row above.
  flake.tests.crossing-adapter-set.test-o-name-1b-control-nodes-absent-here-present-at-the-target = {
    expr = {
      inCarriageFormals = builtins.functionArgs systemTerminal.adapter ? nodes;
      inTargetArgs = specialArgsOf systemClosed ? nodes;
    };
    expected = {
      inCarriageFormals = false;
      inTargetArgs = true;
    };
  };

  # ══ O-WELD-2 — THE TARGET-FACING KEY SURVIVED ═══════════════════════════════
  #
  # THE ONLY CELL THAT DISTINGUISHES THE CORRECT MIGRATION FROM THE SWEEP-PRODUCED
  # ONE. From the carriage side the two are identical — both rename the formal to
  # `extent`. They differ only in what the TARGET receives.
  #
  # WHAT A FAILING RUN LOOKS LIKE: the target arg set carries `extent` instead of
  # `nodes`, and every class module reading `nodes.<peer>.config` dies inside the
  # target's own evaluation, far from the edit that caused it.
  flake.tests.crossing-adapter-set.test-o-weld-2-target-args-still-carry-the-peer-key = {
    expr = builtins.elem "nodes" (specialArgKeysOf systemClosed);
    expected = true;
  };
  # …and a class module whose formals NAME `nodes` really does receive the peer
  # set, measured THROUGH the module system rather than by reading the arg set as
  # data. The target-facing contract is only real at the target.
  flake.tests.crossing-adapter-set.test-o-weld-2-a-module-naming-nodes-receives-the-peer-set = {
    expr = (targetEval systemClosed).config.peerAddr;
    expected = "10.0.0.2";
  };
  # THE SEEDED DEFECT — step 2 without step 1, live in the suite. It is measured
  # AT THE CHANNEL rather than by watching the module break, for the reason this
  # file already records for the arg-environment rival: an absent module argument
  # is an evaluation ERROR, not a `throw`, so `tryEval` does not catch it and a
  # cell written to observe the break would ABORT the suite instead of reporting
  # it. The two arg sets differ, and that difference is the discrimination.
  flake.tests.crossing-adapter-set.test-o-weld-2-control-the-sweep-produced-adapter-loses-the-peer-key = {
    expr = builtins.sort builtins.lessThan (
      builtins.attrNames (weldFollowingSpecialArgs {
        extent = {
          peer.config.addr = "10.0.0.2";
        };
        extraModules = [ ];
        passthrough.osConfig.marker = "target-owned";
      })
    );
    expected = [
      "extent"
      "osConfig"
    ];
  };
  # The passthrough's keys reach the target under the CONSUMER's own names, which
  # is the whole content of "target-owned": this adapter names none of them.
  flake.tests.crossing-adapter-set.test-o-weld-2-passthrough-keys-are-the-consumers-own = {
    expr = (specialArgsOf systemClosedOwned).osConfig.marker;
    expected = "target-owned";
  };

  # ══ O-TRM-2 — THE NULL-POSITION ADAPTER REFUSES BY NAME ═════════════════════
  #
  # A7: the acceptance half and both refusal rows are landed against a
  # synthesised adapter. THE DELTA IS THREE THINGS — the flake adapter INSTANCE,
  # the no-crossings control, and the seeded defect.
  #
  # WHAT A FAILING RUN LOOKS LIKE: the crossing is ADMITTED, and a flake fleet
  # silently receives a value at a position its contract has nowhere to put.
  flake.tests.crossing-adapter-set.test-o-trm-2-a-substrate-name-over-the-flake-adapter-refuses-by-name = {
    expr = {
      code = codeOf flakeSubstrateName;
      blamed = blameOf flakeSubstrateName;
      witness = flakeSubstrateName.refusal.witness;
    };
    expected = {
      code = "adapter-missing-bind-formals";
      blamed = "adapter-selector";
      witness = {
        name = "v";
        offered = [
          "wrapUnit"
          "interpret"
        ];
      };
    };
  };

  flake.tests.crossing-adapter-set.test-o-trm-2-a-target-invoked-name-over-the-flake-adapter-refuses-by-name = {
    expr = {
      code = codeOf flakeInvokedName;
      blamed = blameOf flakeInvokedName;
      witness = flakeInvokedName.refusal.witness;
    };
    expected = {
      code = "adapter-missing-target-invoked-channel";
      blamed = "adapter-selector";
      witness = {
        name = "v";
        offered = [
          "wrapUnit"
          "interpret"
        ];
      };
    };
  };

  # ★ DELTA ITEM (b) — the whole point: a collect-only flake fleet STILL BUILDS.
  #   The adapter is well-formed with three null positions, and a crossing-free
  #   close produces the flake outputs.
  flake.tests.crossing-adapter-set.test-control-o-trm-2-a-flake-fleet-with-no-crossings-still-builds = {
    expr = {
      ok = x.isOk flakeNoCrossings;
      modulesSeen = flakeNoCrossings.value.modulesSeen;
      systems = flakeNoCrossings.value.systems;
      inputsSeen = flakeNoCrossings.value.inputsSeen;
    };
    expected = {
      ok = true;
      modulesSeen = flakeModuleBody;
      systems = [ "x86_64-linux" ];
      inputsSeen = [
        "self"
        "upstream"
      ];
    };
  };

  # ★★ DELTA ITEM (c) — THE SEEDED DEFECT, AND IT IS THE ONE THAT MATTERS.
  #    §2.3.3(a) forbids growing an offered position onto the flake adapter
  #    because doing so converts a BY-CONSTRUCTION zero into an AS-AUTHORED one
  #    with nothing downstream noticing. This cell is that mutation: with
  #    `bindFormals` grown, the name the null-position adapter refuses is
  #    silently ADMITTED. It is what makes the two refusal cells above
  #    green-to-red under the mutation, i.e. what arms the normative rule.
  flake.tests.crossing-adapter-set.test-o-trm-2-seed-a-grown-bindFormals-admits-the-name-the-null-position-refuses = {
    expr = {
      nullPositionRefuses = x.isRefusal flakeSubstrateName;
      grownAdmits = x.isOk flakeSeeded;
    };
    expected = {
      nullPositionRefuses = true;
      grownAdmits = true;
    };
  };

  # ══ O-TRM-3 — the validator-append is a DECLARED residue ════════════════════
  #
  # A CAPABILITY residue, not a carriage one: `wrapAll`'s `.all` is
  # `mods ++ vals`, and those validators raise a `throw` INSIDE the target's own
  # evaluation. This surface cannot express that — a `Refusal` here is a tagged
  # VALUE, never a throw — so the successor returns `.modules` and the
  # validator-append is a residue rather than a relocation.
  #
  # WHAT A FAILING RUN LOOKS LIKE: the counts match, meaning the successor is
  # carrying validators after all and this comment is false.
  flake.tests.crossing-adapter-set.test-o-trm-3-the-crossing-path-returns-modules-only = {
    expr = {
      crossingPath = builtins.length crossingPathModules;
      shippedPathAll = builtins.length shippedPath.all;
      shippedPathValidators = builtins.length shippedPath.validators;
    };
    expected = {
      crossingPath = 1;
      shippedPathAll = 2;
      shippedPathValidators = 1;
    };
  };

  # The residue asserted directly: a collision `wrapAll`'s appended validators
  # would have caught is NOT refused by the crossing.
  flake.tests.crossing-adapter-set.test-o-trm-3-the-crossing-does-not-refuse-a-merge-collision = {
    expr = x.isOk collisionClosed;
    expected = true;
  };

  # ★ THE CONTROL, IN THE SAME RUN: the collision under the SHIPPED `wrapAll`
  #   path still throws. A residue asserted without this is an assumption; with
  #   it, it is a measured difference between two live paths.
  flake.tests.crossing-adapter-set.test-control-o-trm-3-the-shipped-path-validator-still-throws = {
    expr =
      (builtins.tryEval
        (builtins.head shippedPath.validators {
          config._module.args = {
            host = "supplied-by-the-module-system";
          };
        }).warnings
      ).success;
    expected = false;
  };

  # ══ O-TRM-4 — THE LOCATOR IS PER-TERMINAL, NEVER A FIXED `.config` PATH ═════
  #
  # A7: AUDITED — no transfer exists (see the header). Two terminals over the
  # same crossing: one whose artifact HOLDS its config at `.config`, one whose
  # artifact IS the config.
  #
  # WHAT A FAILING RUN LOOKS LIKE: the second terminal's config is read through
  # a fixed `.config` path, reaching for `.config` of something that already is
  # one — which is the silent misread §2.3.3(b) forbids.
  flake.tests.crossing-adapter-set.test-o-trm-4-both-terminals-resolve-their-evaluated-config = {
    expr = {
      dotConfig = (dotConfigTerminal.locateConfig dotConfigClosed.value).built;
      isConfig = (isConfigTerminal.locateConfig isConfigClosed.value).built;
    };
    # `classModule`'s only named formal is the bound one, so `wrapAll` applies it
    # FULLY and the module list carries the applied attrset rather than a lambda
    # — which is also why this comparison can be an equality at all.
    expected = {
      dotConfig = [ { config.result = "alpha"; } ];
      isConfig = [ { config.result = "alpha"; } ];
    };
  };

  # ★ THE CONTROL, WITHOUT WHICH §2.3.3(b) IS A STATEMENT RATHER THAN A
  #   CONSTRAINT: a FIXED `.config` path must fail the second arm in the same
  #   run. It finds nothing there — the artifact carries `built` directly.
  flake.tests.crossing-adapter-set.test-control-o-trm-4-a-fixed-config-path-misreads-the-second-terminal = {
    expr = {
      fixedPathWorksOnTheFirst = dotConfigClosed.value ? config;
      fixedPathMisreadsTheSecond = isConfigClosed.value ? config;
    };
    expected = {
      fixedPathWorksOnTheFirst = true;
      fixedPathMisreadsTheSecond = false;
    };
  };

  # A flake terminal produces outputs, not an evaluated config, and it says so
  # VISIBLY — the same discipline the Adapter's `Maybe` fields use for a position
  # that is not offered.
  flake.tests.crossing-adapter-set.test-o-trm-4-a-terminal-with-no-evaluated-config-says-so-visibly = {
    expr = flakeTerminal.locateConfig;
    expected = null;
  };
}

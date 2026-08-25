# The crossing's ADAPTER SET — the concrete, target-shaped adapters the substrate
# ships, and the destination ADR-0031 F2 fixes for gen-flake's `inject.nix` and
# `terminals.nix`.
#
# Spec: specs/2026-08-24-gen-flake-crossing-adapter-spec.md §2.2 (inject at
# `(Formals, Substrate)`), §2.3 (the terminals at the Adapter set), §2.3.3 (the
# two normative constraints the corpus census imposes), §2.3.4 (the carriage
# residues). Design of record: specs/2026-08-18-gen-crossing-rederivation-spec.md
# §2.5, §2.10, §2.11.
#
# `crossing-adapter.nix` defines the Adapter TYPE and resolves PLACEMENT. This
# file defines the INSTANCES: what an Adapter actually is for a module-system
# target, for a system evaluator, and for a flake-parts output crossing.
#
# ★ A `Body` IS WHATEVER ITS ADAPTER SAYS IT IS. The design of record enumerates
# `Body` among the four opaque target-owned types and the substrate never reads
# one, so each adapter below DEFINES its own — a module for `injectAdapter`, a
# module LIST for `mkSystemTerminal`, a flake-module list for `mkFlakeTerminal`.
# The substrate carries them and nothing more.
#
# ★★ WHY EACH CONSTRUCTOR RETURNS A `Terminal` RECORD `{ adapter, locateConfig }`
# RATHER THAN A BARE `Adapter`. `mkAdapter` is TOTAL over its five fields and
# rebuilds its result from exactly those, so a sixth key does not survive it —
# a locator cannot ride the Adapter. And the construct being migrated is a
# TERMINAL, which is precisely "an Adapter plus how to read the artifact it
# produces". §2.3.3(b) is normative here: THE EVALUATED-CONFIG LOCATOR IS A
# PER-TERMINAL FIELD, NEVER A FIXED `.config` PATH — for `nixosSystem` the config
# sits at `.config` OF the artifact, while for a `lib.evalModules`-shaped data
# terminal the artifact IS the config, and a fixed path silently misreads the
# second. `locateConfig = null` says "this terminal produces no evaluated config"
# visibly, the same way the Adapter's `Maybe` fields say a position is not
# offered.
{ prelude, interpret }:
let
  wrapLib = import ./wrap.nix { inherit prelude; };

  # ── inject ───────────────────────────────────────────────────────────────────
  # The successor to gen-flake's `injectArgs`. Its payload is `composed.values` —
  # the resolved gen fixpoint, substrate-side rather than a target fixpoint — so
  # as a `Binding` it is `Plain Value`: no δ, no term, no algebra. δ of a `Plain`
  # binding is `(∅, EXACT)` (`crossing-delta.nix:191-192`), the congruence
  # predicate `target NOT IN ∅` therefore holds, and §2.5 step 2 resolves
  # `true × EXACT × offers bindFormals` to `(Formals, Substrate)`.
  #
  # ★ WHAT `Formals` MEANS HERE, BECAUSE IT IS AN ARGUMENT AND NOT A CITATION.
  # `Channel` and `Time` are placement coordinates of the SUBSTRATE's vocabulary,
  # not names of module-system channels. `Formals` says the name lands in the
  # formal-parameter position; `Substrate` says its value is determined before
  # the consuming target's fixpoint runs. An arg-environment writer satisfies
  # both: every module in the eval may write `{ genValues, ... }: …`, and nothing
  # about the value is read from the target's own config.
  #
  # ★★ NORMATIVE — `bindFormals` HERE MUST BE AN ARG-ENVIRONMENT WRITER, NOT A
  # FORMAL PARTIAL-APPLICATION, AND THE DIFFERENCE IS BEHAVIOURAL. An arg
  # environment reaches every module in the target's evaluation, INCLUDING modules
  # the substrate never saw; a partial application reaches only the wrapped set.
  # The narrowing would be invisible to every consumer whose readers happen to sit
  # inside that set. O-INJ-3 arms the difference — a module reached only by a
  # target-side `imports` from a module the substrate did see must still read the
  # bound name.
  #
  # ★★★ ADR-0023 (b) — A DECLARED OPT-OUT, WITH ITS PRICE, AND IT IS MEASURED
  # RATHER THAN ASSUMED.
  #
  # ADR-0023's target is the by-construction form: what crosses is
  # provably-plain-data, checked on the TARGET form rather than the documentation
  # form. THIS SITE DOES NOT MEET IT, and the measurement is the spec's O-INJ-2,
  # run over a real `composed.values` produced by `compose`:
  #
  #   values.schema.host.options.{addr,aspects,role}.type  ⇒ `check` and `merge`
  #   are both genuine FUNCTIONS at every one of the three; the payload-side
  #   predicate "no function is reachable, transitively" FAILS on the payload.
  #   Controls, same instrument same run: a payload known to be plain ⇒ clean, so
  #   the walk does not refuse everything; a planted closure at a
  #   substrate-written position ⇒ caught, so the predicate fires.
  #
  # So the disposition is ADR-0023 (b), THE DECLARED INTERIM: the opt-out is
  # stated here with its price rather than left unstated. Arm (i) — narrow the
  # payload — is not available to this unit: it turns on Q-U5-3 (is the schema
  # sub-tree narrowable at all?), which is out of scope, and the hub's own
  # invariant forbids reaching it by projecting `schema` out.
  #
  # THE PRICE, STATED SO IT IS NOT REDISCOVERED AS A SURPRISE: substrate-built
  # gen TYPE objects cross this boundary. They are inert HERE only because
  # `_module.args` is not type-walked by the consuming module system — a
  # consequence-based safety argument, which is exactly the "documented hole"
  # ADR-0023 (a) was rejected as. A consumer that routes any part of this payload
  # into an OPTIONS tree as a `type` leaves the condition under which it is safe.
  # This declaration is ITSELF a publishing surface for the interim condition,
  # and the standing sweep over publishing surfaces must count it — a sweep that
  # enumerated only the READMEs would leave the one statement of the price
  # outside its own domain.
  #
  # The `injectArgs` module wrapper is vestigial at every live consumer — both
  # read `._module.args` straight back out — so the `AttrsOf Value` is the real
  # interface, and `wrapUnit` returns the module itself: for a target whose module
  # set the substrate does not own, the TargetUnit IS the module to be spliced.
  injectAdapter = {
    bindFormals = values: body: {
      imports = [ body ];
      _module.args = values;
    };

    # No name at this site is target-invoked: the payload is a resolved
    # substrate-side fixpoint. `null` refuses such a name BY NAME rather than
    # falling back to a channel that would bind it at the wrong time.
    bindArgEnv = null;
    wrapFn = null;

    # `_units` is DEAD BY CONSTRUCTION: `subUnits` is fed only by `bindArgEnv`
    # (`crossing.nix:876`, `:762`), which is null above. Named to match the
    # Adapter signature; it must not be relied on.
    wrapUnit = body: _units: body;

    inherit interpret;
  };

  # ── the system terminal ──────────────────────────────────────────────────────
  # The successor to gen-flake's `mkSystemTerminal`. It names no system class and
  # touches no host builder: the `{ modules, specialArgs } -> artifact` evaluator
  # is the consumer's, threaded at TERMINAL CONSTRUCTION.
  #
  # ★ THE TWO CONSTRUCTIONS ARE DIFFERENT AND THE SPLIT IS STRUCTURAL HERE.
  # `evaluator` and `locateConfig` are captured when the terminal is built;
  # `nodes`, `extraModules` and `osConfig` arrive PER MEMBER INVOCATION, which is
  # why `adapter` below is a function of the carriage. ⇒ the Adapter is built per
  # member, not once per terminal.
  #
  # ★★ THE CARRIAGE RESIDUES (§2.3.4). `nodes`, `extraModules`, `evaluator` and
  # `osConfig` travel by CLOSURE, not as placed `Binding`s, so δ cannot see them
  # and `E(u)` cannot count them. Two of the three are scope residues —
  # `extraModules` is target-owned content the substrate never inspects, and
  # `evaluator`/`osConfig` carry no reach of their own. `nodes` IS a correctness
  # residue and it is SILENT: it is the realized peer set, so a missed edge to a
  # peer leaves the value correct and makes `E(u)` under-report, which can render
  # `linked(u)` wrongly true. It stays a raw attrset accessor OUTSIDE the
  # governed query surface — no mark, no narrowing, widening trivially
  # expressible. An ADR-0026-compatible SHAPE for peer access is commissioned
  # elsewhere and UNDELIVERED; this construction does not deliver it, and a
  # reading of this file that takes the move as discharging it has overclaimed.
  #
  # ★★ AND ONE CAPABILITY RESIDUE, WHICH IS A DIFFERENT KIND OF THING.
  # `wrapAll`'s `.all` is `mods ++ vals` — the wrapped modules PLUS merge
  # collision validators (`merge-strategy.nix:32`), which raise a `throw` INSIDE
  # the target's own evaluation. This surface cannot express that: a `Refusal`
  # here is a tagged VALUE, never a throw. ⇒ `bindFormals` below returns
  # `.modules`, NOT `.all`, and the validator-append is a RESIDUE rather than a
  # relocation. Whether §2.11 owes a refusal row for the collision class those
  # validators covered is the design of record's own open question, carried
  # forward and not settled here. O-TRM-3 asserts the residue; it does not decide
  # the row.
  mkSystemTerminal =
    { evaluator, locateConfig }:
    {
      inherit locateConfig;

      adapter =
        {
          nodes,
          extraModules,
          ...
        }@carriage:
        {
          # `Body` is the class module LIST. The design of record's amendment A
          # rules this identification by name: `wrapAll`'s partial
          # application into the module functions' formal parameters IS
          # `Adapter.bindFormals`.
          bindFormals =
            values: body:
            (wrapLib.wrapAllCore {
              modules = body;
              bindings = values;
            }).modules;

          # No system-terminal name is target-invoked. A `false` congruence
          # predicate meets `adapterMissingTargetInvoked` and is refused by name
          # rather than falling back to a channel that binds it at target time.
          bindArgEnv = null;
          wrapFn = null;

          # Amendment A: `Adapter.wrapUnit` performs the assembly `wrapAll`
          # returns as a list. `_units` is dead by construction (see
          # `injectAdapter` above).
          wrapUnit =
            body: _units:
            evaluator {
              modules = body ++ extraModules;
              specialArgs = {
                inherit nodes;
              }
              // (if carriage ? osConfig then { inherit (carriage) osConfig; } else { });
            };

          inherit interpret;
        };
    };

  # ── the flake terminal ───────────────────────────────────────────────────────
  # The successor to gen-flake's `mkFlakeTerminal`, and it is a NULL-POSITION
  # ADAPTER: every placement position is `null`.
  #
  # ★★★ NORMATIVE (§2.3.3(a)) — THIS ADAPTER MUST NOT GROW `bindFormals`,
  # `bindArgEnv`, `wrapFn`, `nodes` OR `bindings`. The corpus census's zero for a
  # flake fleet receiving a cross-unit deferred is a zero BY CONSTRUCTION at this
  # contract: the source signature had nowhere to put one. Growing an offered
  # position converts that into an as-authored zero, AND NOTHING DOWNSTREAM WOULD
  # NOTICE — every fixture would stay green and the count would stay zero. Any
  # change to the offered positions is a design change requiring its own ruling,
  # never an implementation detail. O-TRM-2's seeded defect is exactly this
  # mutation, and it must turn the refusal cells red.
  #
  # ★ THE MIGRATION STRICTLY CHANGES A SILENCE INTO A WITNESS. Today a flake
  # fleet cannot receive a crossing because the function signature has nowhere to
  # put one. Here it cannot receive one because the adapter DECLARES it offers no
  # position: a `Substrate`-admissible name meets `adapterMissingBindFormals`
  # (`crossing-adapter.nix:174-181`, and again at `crossing.nix:851-858` before
  # any body is built — two independent sites, so the safety does not depend on
  # `placement` being consulted first), a `TargetInvoked` name meets
  # `adapterMissingTargetInvoked` (`:192-199`). Each is blamed on the adapter
  # selector and witnessed by the name and the offered positions.
  #
  # ★ THE WHOLE MODULE LIST IS ONE `Body`, and that is forced rather than
  # stylistic: `close` takes `body0 = builtins.head fragment.bodies` and refuses a
  # fragment carrying more than one (`close-body-count`). Building a Body per
  # module meets a landed refusal, not a silent narrowing.
  #
  # `evalFlakeModule` is INJECTED, exactly as `evaluator` is for the system
  # terminal: the host that evaluates flake modules is the consumer's, and naming
  # it here would put a host boundary inside the substrate.
  #
  # `locateConfig = null` — a flake terminal produces outputs, not an evaluated
  # config, and saying so visibly is what §2.3.3(b) requires of the field.
  mkFlakeTerminal =
    {
      evalFlakeModule,
      inputs,
      self,
      systems ? [ ],
    }:
    {
      locateConfig = null;

      adapter = {
        bindFormals = null;
        bindArgEnv = null;
        wrapFn = null;

        wrapUnit =
          body: _units:
          (evalFlakeModule
            {
              inputs = inputs // {
                inherit self;
              };
            }
            {
              imports = body;
              inherit systems;
            }
          ).config.flake;

        inherit interpret;
      };
    };
in
{
  inherit
    injectAdapter
    mkSystemTerminal
    mkFlakeTerminal
    ;
}

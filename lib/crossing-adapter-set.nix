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

    # REQUIRED (§2.2 of the thunk-channel spec), and `null` for the same reason
    # `bindArgEnv`/`wrapFn` above are: this adapter never calls `wrapAllCore`, so
    # the member is dead by construction here — visibly, not by omission.
    thunkBindings = null;
  };

  # ── the system terminal ──────────────────────────────────────────────────────
  # The successor to gen-flake's `mkSystemTerminal`. It names no system class and
  # touches no host builder: the `{ modules, specialArgs } -> artifact` evaluator
  # is the consumer's, threaded at TERMINAL CONSTRUCTION.
  #
  # ★ THE TWO CONSTRUCTIONS ARE DIFFERENT AND THE SPLIT IS STRUCTURAL HERE.
  # `evaluator` and `locateConfig` are captured when the terminal is built;
  # `extent`, `extraModules` and `passthrough` arrive PER MEMBER INVOCATION, which
  # is why `adapter` below is a function of the carriage. ⇒ the Adapter is built
  # per member, not once per terminal.
  #
  # ★★ THE CARRIAGE RESIDUES (§2.3.4). `extent`, `extraModules`, `evaluator` and
  # `passthrough` travel by CLOSURE, not as placed `Binding`s, so δ cannot see them
  # and `E(u)` cannot count them. Two of the three are scope residues —
  # `extraModules` is target-owned content the substrate never inspects, and
  # `evaluator`/`passthrough` carry no reach of their own. `extent` IS a
  # correctness residue and it is SILENT: it is the realized peer set, so a missed edge to a
  # peer leaves the value correct and makes `E(u)` under-report, which can render
  # `linked(u)` wrongly true. It stays a raw attrset accessor OUTSIDE the
  # governed query surface — no mark, no narrowing, widening trivially
  # expressible. An ADR-0026-compatible SHAPE for peer access is commissioned
  # elsewhere and UNDELIVERED; this construction does not deliver it, and a
  # reading of this file that takes the move as discharging it has overclaimed.
  #
  # ★★ AND THE COLLISION CLASS, WHICH IS NAMED RATHER THAN REFUSED. A crossed
  # binding shadowing a value the target's module system supplies for the same
  # name is observable ONLY inside the target's evaluation — the substrate never
  # sees the target's arg environment — so the named surface is the retired
  # validator itself: `bindFormals` below returns `.all` (`mods ++ vals`,
  # `wrap.nix:314`), carrying the merge-collision validators
  # (`merge-strategy.nix:32`) into the target's module set, where a collision
  # lands in the `warnings` channel under the retired surface's own message
  # family ("gen-bind: binding '<name>' collision — bind-wins, module-system
  # value shadowed"). This is WARN-AND-PROCEED, not a refusal: the design of
  # record's §2.11 holds refusals only, and its sibling block names this class
  # as warned-at-the-target. A substrate `Refusal` stays a tagged VALUE, never a
  # throw — nothing here changes that; the one throw a validator can raise is
  # the per-value `_mergeStrategy = "error"` spelling, the consumer's own
  # opt-in, raised inside the consumer's own evaluation exactly as the retired
  # surface raised it. The price, stated: a validator DEFINES `warnings`, so a
  # target evaluation receiving a crossed binding must declare that option —
  # true of every NixOS-shaped target, and the same imposition the retired
  # surface made.
  #
  # ★★★ ADR-0023 (b) SITE 2 — GAINING THE PRICE ADR-0023 ACTUALLY ASKS FOR.
  # THE `warnings` SENTENCE ABOVE PRICES A DIFFERENT IMPOSITION; measured, the
  # closure-price predicate read 0 occurrences at every declaration surface in
  # the ecosystem while the comparison record that coined the phrase reads 4 —
  # naming a different imposition does not discharge this one.
  #
  # (i) THIS SITE DOES NOT MEET ADR-0023 (c) EITHER.
  #
  # (ii) THE PRICE, IN THE SITE'S OWN TERMS: a substrate closure — the validator
  # `mkMergeValidator` builds (`merge-strategy.nix`) — executes inside the target's
  # evaluation whenever a bound name collides with a module-system arg, reading
  # `provenance` and the resolved collision policy, and it throws on a
  # `_mergeStrategy = "error"` opt-in (O-3 measures the ground: the validator is
  # spliced into the target's module set at length 2, kinds
  # `[ "attrs" "FUNCTION" ]`; the trailing lambda names itself `mkMergeValidator`).
  #
  # (iii) THE ARGUED IMPOSSIBILITY: a by-construction fix would mean detecting the
  # collision substrate-side, before any target module set exists — not available
  # to this unit, because the module system a crossed binding can collide with is
  # the TARGET's, unknown until the target's own modules are collected. Closing
  # this here would have to change WHERE collision detection runs, not merely how
  # this validator prices it — the argued impossibility this declaration records
  # under ADR-0013, not a scope limit on the record itself.
  #
  # ★★ AND THE cfg-LEVEL CHANNEL, WHICH IS NOT A RESIDUE BUT A RETIREMENT — OVER
  # FIVE OF THE SIX MEMBERS. The retired `terminalBind` surface accepted a
  # call-level cfg and forwarded it whole into `wrapAllCore` — `contracts`,
  # `provenance`, `mergeStrategies`, `defaultMergeStrategy`, `producerConfigs`,
  # and (until §2.2 of the thunk-channel spec) `thunkBindings`. That channel
  # has NO position in this Adapter surface for the FIVE named above:
  # `bindFormals` below builds `{ modules; bindings; thunkBindings; }` and
  # nothing else drawn from the retired cfg, so each of those five holds its
  # default — a deliberate narrowing, by design of the Adapter contract, not an
  # omission awaiting a field. The surviving spelling for a merge strategy is
  # per value: `_mergeStrategy` INSIDE a binding value (`wrap.nix:58-61` reads
  # it there). A consumer that wants one strategy uniform across its values
  # spells it on each value.
  #
  # `thunkBindings` is the SIXTH member and it is retired FROM THIS LIST, not
  # from the narrowing's reasoning: of the six, it is the only one that decides
  # whether a substrate closure EXECUTES inside the target's fixpoint —
  # ADR-0023's own subject — where the other five select a value or a policy
  # OVER values. §2.2 makes it a required, carried Adapter member (see the
  # `let` above and `crossing-adapter.nix`'s `required`), read by `close`
  # (`crossing.nix`). The narrowing above was not wrong to keep the channel
  # shut for the five that remain; an execution authorization is not a
  # convenience member, and this is why it alone was reopened.
  mkSystemTerminal =
    { evaluator, locateConfig }:
    {
      inherit locateConfig;

      adapter =
        {
          extent,
          extraModules,
          ...
        }@carriage:
        let
          # ★★ ADR-0023 (b) SITE 3, §2.4 — SPELT ONCE, `inherit`ED TWICE. The
          # declaration necessarily reaches two places (the Adapter record below,
          # which `mkAdapter` validates and `close` reads; and `bindFormals`'s
          # `wrapAllCore` call, which operates on it) — spelling it once here and
          # inheriting it into both means a skew between the two is not a bug
          # that can be written.
          thunkBindings = carriage.thunkBindings or null;

          # ★★ THE CARRIAGE'S KEY SET IS TOTAL (the C4 repair). `{ ..., ... }@carriage`
          # otherwise swallows any unrecognised member silently, and with the
          # site-3 value-shape sniff retired (§2.5) a misspelt member
          # (`thunkBngings`) becomes a SILENT WRONG-DATA PATH: it resolves to
          # `null` here, `mkAdapter` sees a validly-`null` member, and the raw
          # marker crosses verbatim into the target with no refusal and no
          # warning — against ADR-0025 item 1. Named by name, matching the
          # `passthrough ? nodes` throw below; over the KEY SET only, forcing
          # nothing the adapter does not already force.
          knownCarriageMembers = [
            "extent"
            "extraModules"
            "passthrough"
            "thunkBindings"
          ];
          unknownCarriageMembers = builtins.filter (k: !(builtins.elem k knownCarriageMembers)) (
            builtins.attrNames carriage
          );
        in
        if unknownCarriageMembers != [ ] then
          throw "gen-bind: mkSystemTerminal: adapter invoked with unrecognised carriage member(s) [ ${builtins.concatStringsSep " " unknownCarriageMembers} ] — accepted members are extent, extraModules, passthrough, thunkBindings."
        else
          {
            inherit thunkBindings;

            # `Body` is the class module LIST. The design of record's amendment A
            # rules this identification by name: `wrapAll`'s partial
            # application into the module functions' formal parameters IS
            # `Adapter.bindFormals`. `.all` = the wrapped modules plus the
            # merge-collision validators — the collision class's named surface
            # (see the header block above).
            #
            # ★★★ ADR-0023 (b) SITE 6 — THE WRAPPING PLACEMENT ITSELF IS A
            # CROSSING, ON THE PARTIAL-APPLICATION BRANCH ONLY.
            #
            # (i) THIS SITE DOES NOT MEET ADR-0023 (c). `wrapAllCore`'s
            # partial-application branch (`wrap.nix`, `wrapFunctionModule`) places
            # `setFunctionArgs wrapper remainingArgs` — a SUBSTRATE-AUTHORED
            # `__functor` attrset carrying `__functionArgs` whose advertised formals
            # OMIT the bound name — into the target's module set, which then CALLS
            # it. The consumer handed a bare lambda; what crosses under
            # `bindFormals` is not it. Measured (O-2): stock head keys
            # `[ "__functionArgs" "__functor" ]`, advertising `[ "other" ]` with `x`
            # stripped; the discriminating predicate is AUTHORSHIP, not
            # `anyFunction`, which reads `true` on every function-shaped consumer
            # regardless and cannot discriminate (rejected, §2.7).
            #
            # ★ SCOPED TO ONE OF THREE PLACEMENT BRANCHES, NOT EVERY FUNCTION-SHAPED
            # MODULE. A consumer whose class module binds every formal
            # (`allMatched == true`) is CALLED and its own returned attrset is
            # placed (`wrap.nix`, head keys `[ "config" ]`, no substrate
            # authorship); a consumer with no formal bound at all is placed
            # unchanged (passthrough). The price below is owed only on the
            # partial-application branch; charging every function-shaped module
            # would overclaim two branches this site never touches.
            #
            # (ii) THE PRICE: a substrate closure — the `wrapper` `wrap.nix` builds
            # — executes inside the target's evaluation every time the target's
            # module system calls it, reading `moduleCallArgs` (whatever the
            # target's own evaluation supplies at that position) and the bound
            # `bindings`, and it can throw anything the wrapped consumer module
            # throws, plus `evalModules`'s own arity errors if the target calls it
            # with the wrong shape.
            #
            # (iii) THE ARGUED IMPOSSIBILITY: `injectAdapter` above shows an
            # alternative placement exists — an arg-environment writer
            # (`_module.args`) rather than a formal partial application — but
            # substituting it is NOT a (c)-preserving repair here: it is a REACH
            # WIDENING, measured (O-INJ-3): a module the substrate never saw,
            # reached only by a target-side `imports` from one it did see, FAILS
            # under stock formal partial application (`attribute 'x' missing`) and
            # READS THE BINDING under the seeded `_module.args` placement — the
            # substitution widens every binding's reach to modules never inspected.
            # Whether ADR-0023 (c) admits an Adapter that binds by PARTIAL
            # APPLICATION AT ALL is what would have to change, and that question is
            # out of scope for this record — it is `den-hoag-i546n`'s open question
            # (§4.2), not picked here.
            bindFormals =
              values: body:
              (wrapLib.wrapAllCore {
                modules = body;
                bindings = values;
                inherit thunkBindings;
              }).all;

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
                # ★ THE TWO SIDES ARE DIFFERENT CONTRACTS AND THE SPLIT IS WHAT
                # KEEPS THEM APART. `nodes` here is TARGET-FACING — what a class
                # module reads as `nodes.<peer>.config` — and it stays `nodes` by
                # construction, because after the split nothing derives it from the
                # carriage name. The carriage side is `extent`: the realized set for
                # this class, whose spine is the class's node keys.
                #
                # `passthrough` is the TARGET-OWNED channel and it splices WHOLE.
                # Its keys are the consumer's own — `osConfig` is home-manager's arg
                # name and is correct AT the surface — so this adapter names none of
                # them. Pinning one framework's field name in a substrate-facing
                # contract is the defect the carriage rename removed; re-reading it
                # here would put it straight back one layer down.
                #
                # ★ AND THE CHANNEL MAY NOT SHADOW A KEY THIS ADAPTER EMITS. `//`
                # gives the right operand priority, so a consumer key named `nodes`
                # would REPLACE the peer set — silently, because the target arg is
                # still present and still called `nodes`. The check reads the
                # channel's SPINE, never its contents, so the opacity above holds:
                # `?` forces nothing the `//` does not already force. Refusal is the
                # only non-silent option; merging the other way round would drop the
                # consumer's key instead.
                specialArgs =
                  let
                    passthrough = carriage.passthrough or { };
                  in
                  if passthrough ? nodes then
                    throw "gen-bind: mkSystemTerminal: the target-owned passthrough carries `nodes`, which this adapter emits itself — splicing it would silently replace the peer set. Rename that key in the passthrough."
                  else
                    { nodes = extent; } // passthrough;
              };

            inherit interpret;
          };
    };

  # ── the flake terminal ───────────────────────────────────────────────────────
  # The successor to gen-flake's `mkFlakeTerminal`, and it is a NULL-POSITION
  # ADAPTER: every placement position is `null`.
  #
  # ★★★ NORMATIVE (§2.3.3(a)) — THIS ADAPTER MUST NOT GROW `bindFormals`,
  # `bindArgEnv`, `wrapFn`, `extent` OR `bindings`. The corpus census's zero for a
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

        # REQUIRED (§2.2 of the thunk-channel spec). §2.6's REVERSAL: the
        # previous revision left this to the builder's judgment; the ground it
        # gave (the §2.3.3(a) bar above) does not reach `thunkBindings` — that
        # bar scopes to `bindFormals`/`bindArgEnv`/`wrapFn`/`extent`/`bindings`,
        # the flake adapter's OFFERED POSITIONS, and `thunkBindings` is not in
        # `fields` (`crossing-adapter.nix`), so it is not an offered position on
        # the bar's own text. `bindFormals = null` above means nothing crosses
        # and no thunk can be selected regardless of this value.
        thunkBindings = null;
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

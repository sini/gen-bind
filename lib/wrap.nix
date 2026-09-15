# Core wrap and wrapAll — partial application of external bindings into NixOS
# module functions.
#
# Academic: Reynolds 1972 — deferred evaluation via closure inspection.
# builtins.functionArgs inspects the module's formal parameters to determine
# which bindings to inject, achieving partial application without macros.
#
# Dependency injection: the wrapper function partially applies external
# bindings at construction time while preserving the module's ability to
# receive remaining args from evalModules. (This is plain DI, not Bracha-style
# mixin composition — bindings are pre-applied closures, not composed mixins.)
{ prelude }:
let
  contractLib = import ./contract.nix { inherit prelude; };
  mergeStrategyLib = import ./merge-strategy.nix { inherit prelude; };
  thunkLib = import ./thunk.nix { inherit prelude; };
  signatureLib = import ./signature.nix { inherit prelude; };
  moduleConvention = import ./module-convention.nix { };

  defaultCfg = {
    bindings = { };
    contracts = { };
    provenance = { };
    mergeStrategies = { };
    defaultMergeStrategy = mergeStrategyLib.mergeStrategy.bindWins;
    thunkBindings = null;
    # Optional scopeKey→config map for producer-scoped thunk resolution
    # (CHORAG §5.1). Default {} ⇒ thunks resolve against the consumer config,
    # byte-identical to the pre-producerConfigs behavior. See thunk.nix.
    producerConfigs = { };
  };

  # ★★★ ADR-0023 (b) SITE 1 — `applyContracts` — OFF-CROSSING BY THE ADAPTER
  # SURFACE, LIVE THROUGH THE RETIRED DIRECT-CALL SURFACE (see gen-settings
  # `lib/inject.nix`, write-list entry 7, for the one path that reaches it).
  #
  # (i) THIS SITE DOES NOT MEET ADR-0023 (c) THROUGH ANY SHIPPED ADAPTER: `contracts`
  # has no Adapter position on `injectAdapter`, `mkSystemTerminal` or
  # `mkFlakeTerminal` (crossing-adapter-set.nix's cfg-level-channel note: none of the
  # three forwards a caller's `contracts`), and no value-shape route reaches it the
  # way site 3's thunk sniff reaches `resolveThunks` — measured, O-4, two arms in one
  # run: the retired direct-call surface (`contracts` passed BY NAME to `wrapCore` /
  # `wrapAllCore`) fires the tripwire, rc=1; the SAME contract-shaped value crossed
  # AS A VALUE through an Adapter returns verbatim, inert, rc=0, tripwire count 0.
  #
  # (ii) THE PRICE, STATED CONDITIONALLY BECAUSE THE ADAPTER ROUTE DOES NOT INCUR IT:
  # were `contracts` ever given an Adapter position, a substrate closure — this
  # function calling `contractLib.apply` — would execute inside the target's
  # evaluation exactly as site 3's `resolveThunks` closure does, reading the bound
  # value and its provenance and throwing whatever the contract's own predicate
  # throws. Measured not incurred via any Adapter: O-4 above. It IS incurred through
  # the retired direct-call surface, at whichever evaluation the caller's own module
  # eventually joins — gen-settings `lib/inject.nix` is that live path.
  #
  # (iii) THE ARGUED IMPOSSIBILITY OF CLOSING IT BY CONSTRUCTION: there is no
  # crossing route through an Adapter to close, so a by-construction repair is not
  # available to this unit — there is nothing here for `den-hoag-i546n` to fix.
  # Opening one (adding a `contracts` Adapter position) would be a reach widening,
  # out of scope for a record that only prices what already exists.
  #
  # Chitil 2012 §2: lazy contract application via genAttrs.
  # Contract thunks are shared across all modules when called from wrapAll.
  applyContracts =
    contracts: provenance: bindings:
    let
      contractNames = builtins.filter (k: contracts ? ${k}) (builtins.attrNames bindings);
    in
    if contractNames == [ ] then
      bindings
    else
      bindings
      // prelude.genAttrs contractNames (
        k: contractLib.apply contracts.${k} bindings.${k} (provenance.${k} or null)
      );

  # Resolve merge strategy for a given arg name.
  resolvePolicy =
    {
      mergeStrategies,
      defaultMergeStrategy,
      bindings,
    }:
    name:
    if mergeStrategies ? ${name} then
      mergeStrategies.${name}
    else if
      builtins.isAttrs (bindings.${name} or null) && (bindings.${name} or { }) ? _mergeStrategy
    then
      bindings.${name}._mergeStrategy
    else
      defaultMergeStrategy;

  # Core wrapping for function modules.
  wrapFunctionModule =
    cfg: module:
    let
      inherit (cfg)
        bindings
        provenance
        mergeStrategies
        defaultMergeStrategy
        thunkBindings
        producerConfigs
        ;
      moduleArgs = builtins.functionArgs module;
      moduleArgNames = builtins.attrNames moduleArgs;
      boundArgNames = builtins.filter (k: bindings ? ${k}) moduleArgNames;
    in
    if boundArgNames == [ ] then
      # No match — passthrough
      {
        inherit module;
        wrapped = false;
        validator = null;
        signature = signatureLib.buildSignature {
          inherit
            module
            bindings
            defaultMergeStrategy
            mergeStrategies
            provenance
            ;
        };
        advertisedArgs = moduleArgs;
      }
    else
      let
        allMatched = builtins.length boundArgNames == builtins.length moduleArgNames;

        policy = resolvePolicy {
          inherit mergeStrategies defaultMergeStrategy bindings;
        };

        # ★★★ ADR-0023 (b) SITE 3 — the value-shape sniff below is a CROSSING-
        # REACHABLE ROUTE, not discharged by construction (measured, gate v4 / O-1;
        # falsifies the earlier premise that `thunkBindings`/`producerConfigs` being
        # unoffered discharges this site).
        #
        # (i) THIS SITE DOES NOT MEET ADR-0023 (c). On the `thunkBindings == null`
        # default — every shipped Adapter's default — this falls to a VALUE-SHAPE
        # TEST on the crossed binding itself (`isList v && any (e: e ? __configThunk)
        # v`) rather than a declared channel. A crossed value of that shape selects
        # `resolveThunks` (`thunk.nix`), and `entry.__fn` — a caller-supplied closure
        # — is applied INSIDE the target's fixpoint.
        #
        # (ii) THE PRICE: a substrate closure executes inside the target's
        # evaluation. It reads `ctx` (the whole binding set passed to the wrapper)
        # and `producerConfigs`, and it can throw anything `entry.__fn` throws,
        # evaluated at the target's own recursion depth rather than the substrate's.
        # O-1 measures the ground in one run: `armThunk` (a `__configThunk`-shaped
        # value) rc=1, tripwire fired; `armPlain` (an ordinary attrset) rc=0, the
        # in-run control, value returned verbatim.
        #
        # (iii) THE ARGUED IMPOSSIBILITY: closing this by construction would mean
        # replacing the value-shape sniff with a typed Adapter channel for thunks —
        # a `ThunkBindings` position threaded the way `bindArgEnv` is — which would
        # have to change the Adapter TYPE itself (`crossing-adapter.nix`), not this
        # file — the argued impossibility this declaration records under ADR-0013,
        # not a scope limit on the record itself. Closing it is a crossing
        # re-derivation question, carried by `den-hoag-i546n`.
        #
        # Per-key thunk decision — the same predicate the eager detection used,
        # asked one key at a time so it forces only the key being demanded.
        isThunkArg =
          k:
          if thunkBindings != null then
            builtins.elem k thunkBindings
          else
            let
              v = bindings.${k} or null;
            in
            builtins.isList v && builtins.any (entry: builtins.isAttrs entry && entry ? __configThunk) v;

        # The injected value for ONE bound arg. Membership in the injected attrset is
        # value-free (boundArgNames is functionArgs ∩ bindings keys); the merge-policy
        # decision and the thunk decision live INSIDE this thunk, so a binding value is
        # forced only when the module demands that specific arg. Chitil 2012 §2 — the
        # assertion thunk is not forced until the consumer demands it.
        bindValue =
          { moduleCallArgs, thunkConfig }:
          k:
          if policy k == "system-wins" then
            moduleCallArgs.${k} or bindings.${k}
          else if isThunkArg k then
            (thunkLib.resolveThunks {
              config = thunkConfig;
              ctx = bindings;
              thunkArgNames = [ k ];
              inherit producerConfigs;
              bindings = {
                ${k} = bindings.${k};
              };
            }).${k}
          else
            bindings.${k};

        # Build the validator for collision detection
        validator = mergeStrategyLib.mkMergeValidator {
          resolvePolicy = policy;
          inherit boundArgNames provenance;
        };

        signature = signatureLib.buildSignature {
          inherit
            module
            bindings
            defaultMergeStrategy
            mergeStrategies
            provenance
            ;
        };

        # Remaining args after stripping bound ones
        remainingArgs = builtins.removeAttrs moduleArgs boundArgNames;
      in
      if allMatched then
        # Fully applied — call immediately, result is an attrset module.
        # The fully-applied path is thunk-aware (consistent with the partial-app
        # branch below): a bound arg may still carry a __configThunk (e.g. a
        # channel-only consumer `{ ch, ... }` whose every named formal is bound,
        # so allMatched holds, yet `ch` is a producer-emitted config-thunk). The
        # per-key thunk decision lives inside `bindValue`, so such a binding is
        # resolved when the module demands that arg. producerConfigs
        # is self-sufficient for __sourceScope thunks (they resolve against the
        # PRODUCER config, not a consumer config) — the actual target here. A
        # null-scope thunk on this path has no evalModules `config` to read (if it
        # needed one it would require `config` as an UNBOUND formal, routing it to
        # the partial-app path); it resolves against a bound `config` arg if one
        # was supplied, else `{}` — a documented ~vacuous edge.
        let
          applied = module (
            prelude.genAttrs boundArgNames (bindValue {
              moduleCallArgs = { };
              thunkConfig = if builtins.elem "config" boundArgNames then bindings.config else { };
            })
          );
        in
        {
          module = applied;
          wrapped = true;
          inherit validator signature;
          advertisedArgs = { };
        }
      else
        # Partial application — build wrapper
        let
          wrapper =
            moduleCallArgs:
            module (
              moduleCallArgs
              // prelude.genAttrs boundArgNames (bindValue {
                inherit moduleCallArgs;
                thunkConfig = moduleCallArgs.config or { };
              })
            );

          wrappedModule = moduleConvention.setFunctionArgs wrapper remainingArgs;
        in
        {
          module = wrappedModule;
          wrapped = true;
          inherit validator signature;
          advertisedArgs = remainingArgs;
        };

  # Wrap imports-style modules: { imports = [...]; }
  # Each import is wrapped once; both .module and .wrapped are read from the
  # same result record (no duplicate wrapCore calls).
  wrapImportsModule =
    cfg: module:
    let
      results = builtins.map (imp: wrapCore (cfg // { module = imp; })) module.imports;
      anyWrapped = builtins.any (r: r.wrapped) results;
      # Propagate only the first non-null sub-import validator
      validatorResults = builtins.filter (r: r.validator != null) results;
      firstValidator =
        if validatorResults == [ ] then null else (builtins.head validatorResults).validator;
    in
    {
      module = module // {
        imports = builtins.map (r: r.module) results;
      };
      wrapped = anyWrapped;
      validator = firstValidator;
      signature = signatureLib.buildSignature {
        module = _: { };
        inherit (cfg)
          bindings
          defaultMergeStrategy
          mergeStrategies
          provenance
          ;
      };
      advertisedArgs = { };
    };

  # Top-level dispatch on module shape.
  wrapCore =
    args:
    let
      cfg = defaultCfg // args;
      inherit (cfg)
        module
        contracts
        provenance
        bindings
        ;

      contractedBindings =
        if contracts == { } then bindings else applyContracts contracts provenance bindings;

      cfgWithContracted = cfg // {
        bindings = contractedBindings;
        contracts = { };
      };
    in
    if builtins.isFunction module then
      wrapFunctionModule cfgWithContracted module
    else if builtins.isAttrs module && module ? imports && builtins.isList module.imports then
      wrapImportsModule cfgWithContracted module
    else
      # Plain attrset — passthrough
      {
        inherit module;
        wrapped = false;
        validator = null;
        signature = signatureLib.buildSignature {
          inherit module;
          inherit (cfgWithContracted)
            bindings
            defaultMergeStrategy
            mergeStrategies
            provenance
            ;
        };
        advertisedArgs = { };
      };

  # Batch wrap with shared contracted bindings (Chitil 2012 optimization).
  wrapAllCore =
    args:
    let
      cfg = defaultCfg // args;
      inherit (cfg)
        modules
        contracts
        provenance
        bindings
        ;

      # Pre-compute contracted bindings once, share across all modules
      contractedBindings =
        if contracts == { } then bindings else applyContracts contracts provenance bindings;

      sharedCfg = cfg // {
        bindings = contractedBindings;
        contracts = { };
      };

      results = builtins.map (mod: wrapCore (sharedCfg // { module = mod; })) modules;
      mods = builtins.map (r: r.module) results;
      vals = builtins.filter (v: v != null) (builtins.map (r: r.validator) results);
    in
    {
      modules = mods;
      validators = vals;
      signatures = builtins.map (r: r.signature) results;
      all = mods ++ vals;
    };
in
{
  inherit wrapCore wrapAllCore;
}

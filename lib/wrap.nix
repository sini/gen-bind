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

# Core wrap and wrapAll — partial application of external bindings into NixOS
# module functions.
#
# Academic: Reynolds 1972 — deferred evaluation via closure inspection.
# builtins.functionArgs inspects the module's formal parameters to determine
# which bindings to inject, achieving partial application without macros.
#
# Academic: Bracha 2004 — pluggable composition. The wrapper function is a
# mixin combinator: it partially applies external bindings while preserving
# the module's ability to receive remaining args from evalModules.
{ lib }:
let
  contractLib = import ./contract.nix { inherit lib; };
  mergeStrategyLib = import ./merge-strategy.nix { inherit lib; };
  thunkLib = import ./thunk.nix { inherit lib; };
  signatureLib = import ./signature.nix { inherit lib; };
  stripLib = import ./strip.nix { inherit lib; };

  defaultCfg = {
    bindings = { };
    contracts = { };
    provenance = { };
    mergeStrategies = { };
    defaultMergeStrategy = mergeStrategyLib.mergeStrategy.bindWins;
    thunkBindings = [ ];
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
      // lib.genAttrs contractNames (
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

  # Detect which binding args contain thunks (auto or explicit).
  detectThunkArgs =
    thunkBindings: bindings: boundArgNames:
    if thunkBindings != [ ] then
      builtins.filter (k: builtins.elem k boundArgNames) thunkBindings
    else
      builtins.filter (
        k:
        let
          v = bindings.${k};
        in
        builtins.isList v && builtins.any (entry: thunkLib.isThunk entry) v
      ) boundArgNames;

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

        # Partition by merge strategy
        systemWinsNames = builtins.filter (k: policy k == "system-wins") boundArgNames;
        bindWinsNames = builtins.filter (k: policy k != "system-wins") boundArgNames;

        systemWinsArgs = lib.genAttrs systemWinsNames (k: bindings.${k});
        bindWinsArgs = lib.genAttrs bindWinsNames (k: bindings.${k});

        thunkArgNames = detectThunkArgs thunkBindings bindings boundArgNames;
        hasThunks = thunkArgNames != [ ];

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
        # Fully applied — call immediately, result is an attrset module
        let
          applied = module (systemWinsArgs // bindWinsArgs);
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
            let
              resolvedBind =
                if hasThunks then
                  thunkLib.resolveThunks {
                    config = moduleCallArgs.config or { };
                    ctx = moduleCallArgs;
                    inherit thunkArgNames;
                    bindings = bindWinsArgs;
                  }
                else
                  bindWinsArgs;
            in
            module (systemWinsArgs // moduleCallArgs // resolvedBind);

          wrappedModule = lib.setFunctionArgs wrapper remainingArgs;
        in
        {
          module = wrappedModule;
          wrapped = true;
          inherit validator signature;
          advertisedArgs = remainingArgs;
        };

  # Wrap imports-style modules: { imports = [...]; }
  wrapImportsModule =
    cfg: module:
    let
      wrappedImports = builtins.map (imp: (wrapCore (cfg // { module = imp; })).module) module.imports;
      newModule = module // {
        imports = wrappedImports;
      };
      anyWrapped = builtins.any (imp: (wrapCore (cfg // { module = imp; })).wrapped) module.imports;
    in
    {
      module = newModule;
      wrapped = anyWrapped;
      validator = null;
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
    in
    {
      modules = builtins.map (r: r.module) results;
      validators = builtins.filter (v: v != null) (builtins.map (r: r.validator) results);
      signatures = builtins.map (r: r.signature) results;
      all = results;
    };
in
{
  inherit wrapCore wrapAllCore applyContracts;
}

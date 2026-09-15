# Config-dependent thunk creation and resolution.
#
# Thunks represent deferred computations that need the evalModules fixpoint
# (config) to resolve. They travel as markers through the binding pipeline
# and resolve inside the module wrapper when evalModules provides config.
#
# Academic: Reynolds 1972 §4 — deferred evaluation via closure inspection.
# The thunk's __fn is a closure whose formal parameters (builtins.functionArgs)
# determine which context args to inject alongside config.
{ prelude }:
{
  mkThunk = fn: {
    __configThunk = true;
    __fn = fn;
    __sourceScope = null;
  };

  mkThunkFrom = scopeId: fn: {
    __configThunk = true;
    __fn = fn;
    __sourceScope = scopeId;
  };

  isThunk = v: builtins.isAttrs v && v ? __configThunk;

  # Resolve thunks within list-valued bindings.
  #
  # For each arg name in thunkArgNames whose binding value is a list,
  # expand any thunk entries by calling __fn with context args + config.
  # Non-list args and args not in thunkArgNames pass through unchanged.
  #
  # Producer-scoped resolution (Söderberg & Hedin 2013, CHORAG §5.1 —
  # materialization-as-attribution over the static AST): a thunk stamped with a
  # source scope (via `mkThunkFrom`) represents a value emitted at a PRODUCER
  # terminal but consumed at a different one. When the caller supplies that
  # scope's config in `producerConfigs`, __fn resolves against the PRODUCER's
  # config — the value materializes over the terminal that emitted it, not the
  # one consuming it. Absent that (the default `producerConfigs = {}`, or a
  # `__sourceScope == null` thunk, or a scope the caller did not supply),
  # resolution falls back to the consumer `config` exactly as before —
  # byte-identical to the pre-producerConfigs behavior. gen-bind stays GENERAL:
  # it takes an opaque scopeKey→config map and does one lazy index; the caller
  # (e.g. den-hoag) builds the map — encoding class into the key if a scope has
  # multiple class terminals. Laziness (A17): the lookup is a single lazy attrset
  # index, and the producer config is forced only to the depth __fn reads, at the
  # consumer, on demand — no eager force at wrap time. A genuine cross-terminal
  # cycle (the producer config transitively demands this same thunk) surfaces as
  # Nix's own LOUD `infinite recursion encountered`, never a silent stale read.
  # ★★★ ADR-0023 (b) — POINTER DECLARATION, NOT THE CROSSING'S DECLARATION OF
  # RECORD. The full four-part declaration for the crossing route THIS function
  # executes lives at `wrap.nix`'s `isThunkArg` (write-list entry 3, gen-bind
  # `crossing-adapter-set.nix`'s SITE-2 sibling in structure): that is the SITE-3
  # SELECTION POINT — the value-shape sniff that decides whether a crossed
  # binding routes here at all — and the declaration belongs there for parity
  # with SITE 2's own selection point (`mkMergeValidator` is priced at
  # `crossing-adapter-set.nix`, not at `merge-strategy.nix`; see that file's
  # pointer).
  #
  # (i) THIS FUNCTION DOES NOT MEET ADR-0023 (c) when `isThunkArg` selects it:
  # `entry.__fn` — a caller-supplied closure — is applied here, inside whatever
  # fixpoint `config`/`targetConfig` belongs to.
  # (ii) THE PRICE, stated here as it is stated at the selection point: a
  # substrate closure executes inside the target's evaluation, reading `ctx`,
  # `producerConfigs` and the resolved `targetConfig`, and it can throw anything
  # `entry.__fn` throws.
  # (iii) THE ARGUED IMPOSSIBILITY is `wrap.nix`'s: closing this would have to change
  # the Adapter TYPE to carry a typed thunk channel — SITE-3's argued
  # impossibility under ADR-0013, not a scope limit on either record. See
  # `wrap.nix`'s `isThunkArg` for the full argument and O-1's measured ground.
  resolveThunks =
    {
      config,
      ctx,
      thunkArgNames,
      bindings,
      producerConfigs ? { },
    }:
    builtins.mapAttrs (
      k: v:
      if builtins.elem k thunkArgNames && builtins.isList v then
        builtins.concatMap (
          entry:
          if builtins.isAttrs entry && entry ? __configThunk then
            let
              thunkArgs = builtins.functionArgs entry.__fn;
              ctxArgs = prelude.genAttrs (builtins.filter (ak: ctx ? ${ak}) (builtins.attrNames thunkArgs)) (
                ak: ctx.${ak}
              );
              sourceScope = entry.__sourceScope or null;
              # The scope key must be a STRING to index producerConfigs. A non-string
              # __sourceScope (a caller that stamped a structured scope rather than a
              # flat key) falls back to the consumer config — a graceful degrade, not a
              # `cannot coerce a set to a string` throw. gen-bind stays agnostic about
              # the key SHAPE the caller chose; it only indexes when the key is usable.
              targetConfig =
                if sourceScope != null && builtins.isString sourceScope && producerConfigs ? ${sourceScope} then
                  producerConfigs.${sourceScope}
                else
                  config;
              result = entry.__fn (ctxArgs // { config = targetConfig; });
            in
            if builtins.isList result then result else [ result ]
          else
            [ entry ]
        ) v
      else
        v
    ) bindings;
}

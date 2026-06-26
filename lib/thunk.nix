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
  resolveThunks =
    {
      config,
      ctx,
      thunkArgNames,
      bindings,
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
              result = entry.__fn (ctxArgs // { inherit config; });
            in
            if builtins.isList result then result else [ result ]
          else
            [ entry ]
        ) v
      else
        v
    ) bindings;
}

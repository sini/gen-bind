# Binding arg stripping from module __functionArgs.
#
# After wrapping, binding arg names must be removed from the module's
# advertised args. Otherwise NixOS probes _module.args.${name} for every
# advertised arg and crashes when the key doesn't exist.
#
# Academic: after partial application, the remaining formal parameters are the
# residual signature. Stripping is the metadata counterpart: updating the
# advertised interface to match reality. (Currying / residual arity is lambda
# calculus, not a specific Reynolds 1972 section — §4 is Abstract Syntax; the
# paper's only partial-application artifact is §6's EQ2 record.)
{ ... }:
let
  moduleConvention = import ./module-convention.nix { };
in
{
  stripBindingArgs =
    {
      module,
      bindingNames,
    }:
    let
      isWrappedAttrset = builtins.isAttrs module && module ? __functionArgs;
      rawArgs =
        if isWrappedAttrset then
          module.__functionArgs
        else if builtins.isFunction module then
          builtins.functionArgs module
        else
          { };
      toStrip = builtins.filter (k: rawArgs ? ${k}) bindingNames;
    in
    if toStrip == [ ] || (!isWrappedAttrset && !builtins.isFunction module) then
      module
    else if isWrappedAttrset then
      module // { __functionArgs = builtins.removeAttrs rawArgs toStrip; }
    else
      moduleConvention.setFunctionArgs module (builtins.removeAttrs rawArgs toStrip);
}

# NixOS module identity wrapping mechanism.
#
# Every wrapped module gets a stable `key` for NixOS module dedup.
# Two modules with the same key are merged (not duplicated) by evalModules.
#
# Academic: Cardelli 1997 §3 — linksets carry identity. Each compilation
# unit (module) has a unique identity that the linker uses to resolve
# duplicates. gen-bind's key serves the same role within evalModules.
{ lib }:
{
  wrapIdentity =
    {
      class,
      module,
      identity,
      isAnon ? false,
    }:
    let
      loc = "${class}@${identity}";
    in
    if isAnon then
      lib.setDefaultModuleLocation loc module
    else
      {
        key = loc;
        _file = loc;
        imports = [ module ];
      };
}

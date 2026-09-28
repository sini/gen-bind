# NixOS module identity wrapping mechanism.
#
# Every wrapped module gets a stable `key` for NixOS module dedup.
# Two modules with the same key are merged (not duplicated) by evalModules.
#
# Academic: Cardelli 1997 §3 — linksets carry identity. Each compilation
# unit (module) has a unique identity that the linker uses to resolve
# duplicates. gen-bind's key serves the same role within evalModules.
#
# `wrapIdentity { isAnon ? false; } class identity module` (den-hoag-7gp66 P2, R7): the option is
# one closed set, first, checked when `wrapIdentity opts` is formed (a `prelude.door`), so an
# unknown option is refused by name and catchably; the operands are positional, the class and the
# identity — the two halves of the key, in the key's own order — as configuration and the module,
# the value wrapped, as the subject, last.
{ prelude }:
let
  moduleConvention = import ./module-convention.nix { };
in
{
  wrapIdentity =
    prelude.door
      {
        name = "gen-bind.wrapIdentity";
        optional = [ "isAnon" ];
      }
      (
        o: class: identity: module:
        let
          loc = "${class}@${identity}";
        in
        if o.isAnon or false then
          moduleConvention.setDefaultModuleLocation loc module
        else
          {
            key = loc;
            _file = loc;
            imports = [ module ];
          }
      );
}

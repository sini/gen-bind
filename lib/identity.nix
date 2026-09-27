# NixOS module identity wrapping mechanism.
#
# Every wrapped module gets a stable `key` for NixOS module dedup.
# Two modules with the same key are merged (not duplicated) by evalModules.
#
# Academic: Cardelli 1997 §3 — linksets carry identity. Each compilation
# unit (module) has a unique identity that the linker uses to resolve
# duplicates. gen-bind's key serves the same role within evalModules.
#
# Door check (den-hoag-7gp66, P1 unit 7): `class`/`module`/`identity` required, `isAnon`
# optional — a mixed door, closed overall (§v1.2), so an unknown field is refused by
# name and catchably rather than aborting Nix's own uncatchable arity check.
{ prelude }:
let
  moduleConvention = import ./module-convention.nix { };
in
{
  wrapIdentity =
    argsRaw:
    let
      args = prelude.checkOptions "gen-bind.wrapIdentity" [
        "class"
        "module"
        "identity"
        "isAnon"
      ] (prelude.checkRequired "gen-bind.wrapIdentity" [ "class" "module" "identity" ] argsRaw);
      inherit (args) class module identity;
      isAnon = args.isAnon or false;
      loc = "${class}@${identity}";
    in
    if isAnon then
      moduleConvention.setDefaultModuleLocation loc module
    else
      {
        key = loc;
        _file = loc;
        imports = [ module ];
      };
}

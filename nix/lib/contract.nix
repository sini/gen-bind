# Lazy binding contracts.
#
# Contracts are partial identities: `assert check then value else throw`.
# They fire only when the bound value is demanded by the consuming module,
# preserving Nix's lazy evaluation semantics.
#
# Academic: Chitil 2012 — practical typed lazy contracts. Theorem: asserting
# a lazy contract preserves program semantics unless violated. Contract
# combinators are partial identities (assert c ⊑ id) that "cut off" invalid
# parts on demand rather than eagerly failing.
#
# Academic: Findler & Felleisen 2002 §2 — blame assignment. When a contract
# fires, the error message identifies the guilty party via provenance metadata.
{ lib }:
let
  provenanceLib = import ./provenance.nix { inherit lib; };
in
{
  mk =
    {
      check,
      message ? "contract violation",
      blame ? null,
    }:
    {
      __contract = true;
      inherit check message blame;
    };

  hasFields = fields: {
    __contract = true;
    check = v: builtins.all (f: v ? ${f}) fields;
    message = "value must have fields: ${builtins.concatStringsSep ", " fields}";
    blame = null;
  };

  isType = type: {
    __contract = true;
    check = v: builtins.typeOf v == type;
    message = "value must be of type ${type}";
    blame = null;
  };

  nonEmpty = {
    __contract = true;
    check =
      v:
      if builtins.isList v then
        v != [ ]
      else if builtins.isAttrs v then
        v != { }
      else
        v != null;
    message = "value must be non-empty";
    blame = null;
  };

  # Chitil 2012 §2: "assert c is roughly the identity function"
  apply =
    contract: value: prov:
    if contract.check value then
      value
    else
      throw (
        "gen-bind: contract violation: ${contract.message}"
        + (
          let
            s = provenanceLib.format prov;
          in
          if s == "" then "" else " (${s})"
        )
        + lib.optionalString (contract.blame or null != null) " [blame: ${contract.blame}]"
      );
}

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
{ prelude }:
let
  provenanceLib = import ./provenance.nix { inherit prelude; };
  applicable = import ./applicable.nix { };
in
{
  # `mk { message ? "contract violation"; blame ? null; } check` (den-hoag-7gp66 P2, R7): the
  # options are one closed set, first, checked when `mk opts` is formed (a `prelude.door`); the
  # predicate is the one operand.
  mk =
    prelude.door
      {
        name = "gen-bind.contract.mk";
        optional = [
          "message"
          "blame"
        ];
      }
      (
        o: check: {
          __contract = true;
          # The record carries `check` itself; the door fires when `check` is first read
          # (den-hoag-k0whn).
          check = if builtins.isFunction check then check else applicable.door "contract.mk" "check" check;
          message = o.message or "contract violation";
          blame = o.blame or null;
        }
      );

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
    let
      # A hand-built record meets the same door here; a lambda passes on the builtin alone, since
      # `wrap`'s contract route calls this per binding.
      check =
        if builtins.isFunction contract.check then
          contract.check
        else
          applicable.door "contract.apply" "check" contract.check;
    in
    if check value then
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
        + prelude.optionalString (contract.blame or null != null) " [blame: ${contract.blame}]"
      );
}

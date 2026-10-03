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
  typeNames = [
    "bool"
    "float"
    "int"
    "lambda"
    "list"
    "null"
    "path"
    "set"
    "string"
  ];
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

  # `fields` is caller data that `check` and the message both read as a list of strings; anything
  # else is refused by name, catchably, when the contract is formed, rather than reaching Nix's own
  # uncatchable `expected a list` / `expected a string` later (den-hoag-9kj1f).
  hasFields =
    fields:
    if builtins.isList fields && builtins.all builtins.isString fields then
      {
        __contract = true;
        check = v: builtins.all (f: v ? ${f}) fields;
        message = "value must have fields: ${builtins.concatStringsSep ", " fields}";
        blame = null;
      }
    else
      throw "gen-bind.contract.hasFields: `fields` ${
        if builtins.isList fields then
          "holds a ${builtins.typeOf (builtins.head (builtins.filter (f: !builtins.isString f) fields))}"
        else
          "is a ${builtins.typeOf fields}"
      }, not a list of strings";

  # `type` is caller data whose codomain is closed: the nine names `builtins.typeOf` returns. A name
  # outside them matches no value, so it is refused by name, catchably, when the contract is formed,
  # rather than forming and then blaming every value (den-hoag-9kj1f).
  isType =
    type:
    if builtins.elem type typeNames then
      {
        __contract = true;
        check = v: builtins.typeOf v == type;
        message = "value must be of type ${type}";
        blame = null;
      }
    else
      throw "gen-bind.contract.isType: `type` is ${
        if builtins.isString type then builtins.toJSON type else "a ${builtins.typeOf type}"
      }, not one of ${builtins.concatStringsSep ", " (map builtins.toJSON typeNames)}";

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
      # `check` is a predicate: a result that is not a Boolean is refused by name rather than
      # reaching `if`, whose own type error is uncatchable (den-hoag-5rz5r).
      ok = check value;
    in
    if !builtins.isBool ok then
      throw "gen-bind.contract.apply: `check` returned a ${builtins.typeOf ok}, not a Boolean"
    else if ok then
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

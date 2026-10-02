# den-hoag-bme8i (B1) clause 1: the BINDING relatum is the binding's KEY together with its VALUE's
# identity (amended 2026-09-30, Q1a), minted through the one authority at REGISTRATION, one pass
# before the `link` that relates it (ADR-0034's bme8i rider; ADR-0016 r7;
# specs/2026-09-28-gen-bind-binding-key-identity-spec.md §2.1, §3a). What `merge` does with a
# shared crossing id is asserted in crossing-binding-origin.nix.
{ genBind, ... }:
let
  f = import ./_crossing-fixtures.nix { inherit genBind; };
  inherit (f)
    x
    sig
    imp
    reg
    supply
    wrappedB
    entity
    _testHashIdentity
    ;
  c = x.contractTerm;

  bindings.db = wrappedB "loom" (_: "postgres");
  registered = (reg bindings).value;
  fragment = (x.declare (sig { db = imp c.any; }) null).value;
  linked = (x.link "igloo" registered fragment).value;
  node = linked.nodes.${builtins.head linked.crossings};
in
{
  flake.tests.crossing-binding-key.test-bme8i-binding-relatum-is-the-minted-key = {
    expr = [
      (node.binding == "db")
      (
        node.binding
        == _testHashIdentity "binding" [ "key" "value" ] (l: if l == "key" then "db" else entity "db")
      )
    ];
    expected = [
      false
      true
    ];
  };

  # R1, the staging: the binding node exists on the registration BEFORE any `link`, and the
  # crossing's relatum is read from it rather than minted at `link`.
  flake.tests.crossing-binding-key.test-bme8i-registration-mints-the-binding-node = {
    expr = {
      fields = builtins.attrNames registered;
      relatumIsTheRegisteredNode = node.binding == registered.bindingIdentities.db;
    };
    expected = {
      fields = [
        "bindingIdentities"
        "heights"
        "projection"
        "supply"
      ];
      relatumIsTheRegisteredNode = true;
    };
  };

  # R2: `link` READS the relatum off the registration, never re-mints it. A different,
  # well-formed identity planted in `bindingIdentities` must be exactly the node's relatum; a
  # `link` that re-mints from the key carries the key's own identity instead and goes red here.
  flake.tests.crossing-binding-key.test-bme8i-link-reads-the-registered-binding-node = {
    expr =
      let
        planted = _testHashIdentity "binding" [ "key" ] (_: "sentinel");
        forged = registered // {
          bindingIdentities.db = planted;
        };
        l = (x.link "igloo" forged fragment).value;
      in
      [
        (l.nodes.${builtins.head l.crossings}.binding == planted)
        (planted != node.binding)
      ];
    expected = [
      true
      true
    ];
  };

  # R2: a supply that did not pass registration carries no binding nodes, and `link` refuses it
  # by name rather than minting a relatum of its own.
  flake.tests.crossing-binding-key.test-bme8i-link-refuses-an-unregistered-supply = {
    expr = (x.link "igloo" (supply bindings) fragment).refusal.witness or "linked-silently";
    expected = {
      object = "Registration";
      field = "bindingIdentities";
      reason = "the supply was not registered through `registerSupply`";
    };
  };

  flake.tests.crossing-binding-key.test-control-bme8i-link-admits-a-registered-supply = {
    expr = x.isOk (x.link "igloo" registered fragment);
    expected = true;
  };

  # The node keeps the key as its IDENTIFIER beside the identity (ADR-0016 r5).
  flake.tests.crossing-binding-key.test-bme8i-the-key-rides-as-the-name = {
    expr = node.name;
    expected = "db";
  };
}

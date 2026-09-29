# den-hoag-bme8i (B1) clause 1: the BINDING relatum is the binding's KEY, minted through the one
# authority at REGISTRATION, one pass before the `link` that relates it (ADR-0034's bme8i rider;
# ADR-0016 r7; specs/2026-09-28-gen-bind-binding-key-identity-spec.md §2.1, §3a).
#
# Clause 2 (two bindings under one key refusing where they meet) waits on its predicate's reading,
# so no cell here asserts what `merge` does with a shared key.
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
      (node.binding == _testHashIdentity "binding" [ "key" ] (_: "db"))
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

  # R2: a supply that did not pass registration carries no binding nodes, and `link` refuses it
  # by name rather than minting a relatum of its own.
  flake.tests.crossing-binding-key.test-bme8i-link-refuses-an-unregistered-supply = {
    expr = (x.link "igloo" (supply bindings) fragment).refusal.witness or "linked-silently";
    expected = {
      object = "Registration";
      field = "bindingIdentities";
      reason = "the supply was not registered through this operation set's `registerSupply`";
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

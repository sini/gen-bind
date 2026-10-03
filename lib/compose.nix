# Layered binding composition.
#
# Bindings arrive from multiple sources (entity context, enrichment, pipes).
# Later layers shadow earlier ones for matching keys.
#
# Academic: Leijen 2005 §2 — extension with scoped labels. Free extension
# retains previous fields but selection returns the most recent. Our compose
# is the simpler attrset //, where later layers overwrite.
{ prelude }:
let
  # A `composeWith` layer is a CLOSED record whose four fields are all optional (den-hoag-ekum1). It
  # is a `prelude.door`, so a misspelt field is refused by name and catchably, where the native
  # closed formal it replaces aborted uncatchably (ADR-0025 item 1). Bound once, outside the fold,
  # so a `{ }` layer takes the door's fast path. Each layer is checked as the fold reaches it —
  # `seq`, not a lazy `let` — so a bad layer is refused when `composeWith layers` is formed, whether
  # or not a field of the result is read. Each field is itself a record, so a non-attrset one is
  # refused by name at the same point (den-hoag-bvpuo), where the fold's `//` aborted uncatchably.
  layer =
    prelude.door
      {
        name = "gen-bind.composeWith";
        optional = [
          "bindings"
          "provenance"
          "contracts"
          "mergeStrategies"
        ];
      }
      (
        l:
        let
          bad = builtins.filter (f: !builtins.isAttrs l.${f}) (builtins.attrNames l);
        in
        if bad == [ ] then
          l
        else
          throw "gen-bind.composeWith: `${builtins.head bad}` must be an attrset, not a ${
            builtins.typeOf l.${builtins.head bad}
          }"
      );
in
{
  compose = layers: builtins.foldl' (acc: layer: acc // layer) { } layers;

  composeWith =
    layers:
    builtins.foldl'
      (
        acc: l:
        let
          checked = layer l;
        in
        builtins.seq checked {
          bindings = acc.bindings // checked.bindings or { };
          provenance = acc.provenance // checked.provenance or { };
          contracts = acc.contracts // checked.contracts or { };
          mergeStrategies = acc.mergeStrategies // checked.mergeStrategies or { };
        }
      )
      {
        bindings = { };
        provenance = { };
        contracts = { };
        mergeStrategies = { };
      }
      layers;
}

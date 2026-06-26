# Layered binding composition.
#
# Bindings arrive from multiple sources (entity context, enrichment, pipes).
# Later layers shadow earlier ones for matching keys.
#
# Academic: Leijen 2005 §2 — extension with scoped labels. Free extension
# retains previous fields but selection returns the most recent. Our compose
# is the simpler attrset //, where later layers overwrite.
{ ... }:
{
  compose = layers: builtins.foldl' (acc: layer: acc // layer) { } layers;

  composeWith =
    layers:
    builtins.foldl'
      (
        acc:
        {
          bindings ? { },
          provenance ? { },
          contracts ? { },
          mergeStrategies ? { },
        }:
        {
          bindings = acc.bindings // bindings;
          provenance = acc.provenance // provenance;
          contracts = acc.contracts // contracts;
          mergeStrategies = acc.mergeStrategies // mergeStrategies;
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

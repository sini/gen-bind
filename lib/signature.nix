# Module signature inference.
#
# Every wrap result includes a signature — what the module requires from
# evalModules, what gen-bind injected, what's unsatisfied, and what collision
# strategies would apply. Derived from existing wrapping computation at zero
# additional cost.
#
# Academic: Cardelli 1997 §2-3 — program fragments carry typed interfaces
# (imports/exports). A linkset declares what it provides and what it still
# needs. gen-bind's signature is a lightweight analog: `bound` = exports
# (what gen-bind provided), `requires` = imports (what evalModules must fill).
{ prelude }:
{
  buildSignature =
    {
      module,
      bindings,
      defaultMergeStrategy,
      mergeStrategies,
      provenance ? { },
    }:
    let
      allArgs = if builtins.isFunction module then builtins.functionArgs module else { };
      argNames = builtins.attrNames allArgs;
      boundArgNames = builtins.filter (k: bindings ? ${k}) argNames;
    in
    {
      requires = builtins.removeAttrs allArgs boundArgNames;

      bound = prelude.genAttrs boundArgNames (k: {
        optional = allArgs.${k} or false;
        provenance = provenance.${k} or null;
      });

      # In the current API, bindings IS the vocabulary, so unsatisfied is empty
      # when all vocabulary keys are present. This field becomes useful when
      # consumers pass a broader vocabulary than the specific bindings provided.
      unsatisfied = builtins.filter (
        k:
        let
          inVocabulary = builtins.elem k (builtins.attrNames bindings);
          isBound = bindings ? ${k};
          isOptional = allArgs.${k} or false;
        in
        inVocabulary && !isBound && !isOptional
      ) argNames;

      mergeStrategies = prelude.genAttrs boundArgNames (k: mergeStrategies.${k} or defaultMergeStrategy);
    };
}

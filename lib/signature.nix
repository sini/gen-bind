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
      # The vocabulary a CALLER declares it may supply, which can be broader
      # than the bindings actually provided at this specific wrap site (e.g.
      # a layered composition where a later stage covers the rest). Default
      # is the standard API: no separate vocabulary, so it collapses to
      # `bindings`' own keys and inVocabulary == isBound for every key —
      # unsatisfied is honestly [] because nothing outside bindings was ever
      # declared as forthcoming.
      vocabulary ? null,
    }:
    let
      allArgs = if builtins.isFunction module then builtins.functionArgs module else { };
      argNames = builtins.attrNames allArgs;
      boundArgNames = builtins.filter (k: bindings ? ${k}) argNames;
      fullVocabulary = if vocabulary == null then builtins.attrNames bindings else vocabulary;
    in
    {
      requires = builtins.removeAttrs allArgs boundArgNames;

      bound = prelude.genAttrs boundArgNames (k: {
        optional = allArgs.${k} or false;
        provenance = provenance.${k} or null;
      });

      # A name is unsatisfied when the caller's declared vocabulary promises
      # it, this call's bindings didn't supply it, and the module can't fall
      # back to a default. With the standard API (no `vocabulary` passed)
      # fullVocabulary IS bindings' keys, so inVocabulary implies isBound and
      # this is always [] — that emptiness is now a true report about a
      # single-layer call, not a broken predicate.
      unsatisfied = builtins.filter (
        k:
        let
          inVocabulary = builtins.elem k fullVocabulary;
          isBound = bindings ? ${k};
          isOptional = allArgs.${k} or false;
        in
        inVocabulary && !isBound && !isOptional
      ) argNames;

      mergeStrategies = prelude.genAttrs boundArgNames (k: mergeStrategies.${k} or defaultMergeStrategy);
    };
}

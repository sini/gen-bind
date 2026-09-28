# Module signature inference.
#
# Every wrap result includes a signature — what the module requires from
# evalModules, what gen-bind injected, what's unsatisfied, and the DECLARED
# collision strategy per bound arg. Derived from existing wrapping computation
# at zero additional cost.
#
# "Declared" means declared AT THE CALL: the cfg `mergeStrategies.<k>` entry,
# else `defaultMergeStrategy`. A binding's own `_mergeStrategy` annotation is
# also a declaration and is NOT reflected here — reading it would force the
# binding value. So `declaredMergeStrategies` is not the effective strategy.
# The runtime precedence is: cfg `mergeStrategies.<k>`, then the value's
# `_mergeStrategy` annotation, then `defaultMergeStrategy`. The annotation
# channel is `mergeStrategy.fromBindings`; reading `(fromBindings b).<k>`
# forces binding `<k>` to WHNF.
#
# Academic: Cardelli 1997 §2-3 — program fragments carry typed interfaces
# (imports/exports). A linkset declares what it provides and what it still
# needs. gen-bind's signature is a lightweight analog: `bound` = exports
# (what gen-bind provided), `requires` = imports (what evalModules must fill).
{ prelude }:
let
  # `buildSignature { provenance ? { }; vocabulary ? null; } { module; bindings; defaultMergeStrategy;
  # mergeStrategies; }` (den-hoag-7gp66 P2, R7). The options are one closed set, first. The four
  # operands stay ONE required-argument record (R7 (a)): the module is the subject, and the three
  # beside it — the bound values, the default strategy and the per-name strategies — have no order
  # among them, so a positional order would be an arbitrary one to remember. The record is a
  # `prelude.door` too (open, R5), guarded against the options step (`optionsStep`), so an option
  # given on the record is refused by name rather than silently dropped. `cores.buildSignature` is
  # the unchecked core `wrap.nix` calls.
  #
  # `vocabulary`: the vocabulary a CALLER declares it may supply, which can be broader
  # than the bindings actually provided at this specific wrap site (e.g. a layered
  # composition where a later stage covers the rest). Default is the standard API: no
  # separate vocabulary, so it collapses to `bindings`' own keys and inVocabulary ==
  # isBound for every key — unsatisfied is honestly [] because nothing outside bindings
  # was ever declared as forthcoming.
  buildSignatureCore =
    o: args:
    let
      inherit (args)
        module
        bindings
        defaultMergeStrategy
        mergeStrategies
        ;
      provenance = o.provenance or { };
      vocabulary = o.vocabulary or null;
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

      declaredMergeStrategies = prelude.genAttrs boundArgNames (
        k: mergeStrategies.${k} or defaultMergeStrategy
      );
    };

  buildSignatureOptions = prelude.door {
    name = "gen-bind.buildSignature";
    optional = [
      "provenance"
      "vocabulary"
    ];
  };
  buildSignatureRecord = prelude.door {
    name = "gen-bind.buildSignature";
    required = [
      "module"
      "bindings"
      "defaultMergeStrategy"
      "mergeStrategies"
    ];
    open = true;
    optionsStep = buildSignature;
  };
  buildSignature = buildSignatureOptions (o: buildSignatureRecord (buildSignatureCore o));
in
{
  inherit buildSignature;
  cores.buildSignature = buildSignatureCore;
}

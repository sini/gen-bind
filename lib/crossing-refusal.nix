# The crossing's refusal carrier — a tagged VALUE, never a throw.
#
# Spec: specs/2026-08-18-gen-crossing-rederivation-spec.md §2.10:
#   Refusal = { code :: RefusalCode, blamed :: Party, witness :: Witness }
# and the closing note of that section — `tryEval` cannot catch every failure
# form, so a thrown refusal is not reliably recoverable and the realization is a
# tagged value. Every operation of the surface therefore returns
# `Either Refusal X`.
#
# The Either is realized as an EXPLICIT two-constructor sum rather than as
# "a Refusal is recognized by its marker attribute". That choice is forced by
# §2.10's opacity register: Body, TargetUnit, TargetArgs and ProducerScope are
# target-owned and the substrate does not read their structure, so a success
# value carrying a marker attribute of its own could not be distinguished from a
# refusal under a marker convention. The sum makes the discrimination structural.
#
# Academic: Reynolds 1972 — the failure channel is DATA the surface interprets,
# not a control-flow effect of the defining language.
{ prelude }:
let
  ok = value: {
    __crossingResult = "ok";
    inherit value;
  };

  refuse =
    {
      code,
      blamed,
      witness,
    }:
    {
      __crossingResult = "refusal";
      refusal = { inherit code blamed witness; };
    };

  isResult = v: builtins.isAttrs v && v ? __crossingResult;
  isOk = r: isResult r && r.__crossingResult == "ok";
  isRefusal = r: isResult r && r.__crossingResult == "refusal";

  # Monadic sequencing: a refusal short-circuits, an ok is unwrapped into `f`.
  andThen = r: f: if isRefusal r then r else f r.value;

  # The first element satisfying `pred`, or `default`. A fold rather than the
  # prelude's own scan, so this file works against the pinned prelude as well as
  # the current one; the lists it runs over are a term's operands and a
  # signature's names, so the absence of an early cutoff costs nothing.
  findFirst =
    pred: default: xs:
    prelude.foldl' (
      acc: v:
      if acc != default then
        acc
      else if pred v then
        v
      else
        acc
    ) default xs;

  # The first refusal among `xs`, or null. `xs` may hold values that are not
  # results at all (a term position holding an ordinary former, say) — those are
  # not refusals and are skipped.
  firstRefusal = findFirst isRefusal null;

  # traverse: [a] -> (a -> Result b) -> Result [b]. The first refusal wins.
  traverse =
    xs: f:
    let
      results = builtins.map f xs;
      bad = firstRefusal results;
    in
    if bad != null then bad else ok (builtins.map (r: r.value) results);

  # traverseAttrs: AttrsOf a -> (name -> a -> Result b) -> Result (AttrsOf b)
  traverseAttrs =
    m: f:
    let
      names = builtins.attrNames m;
      results = prelude.genAttrs names (n: f n m.${n});
      bad = firstRefusal (builtins.map (n: results.${n}) names);
    in
    if bad != null then bad else ok (prelude.genAttrs names (n: results.${n}.value));
in
{
  inherit
    ok
    refuse
    isResult
    isOk
    isRefusal
    andThen
    findFirst
    firstRefusal
    traverse
    traverseAttrs
    ;

  # The blame vocabulary of §2.11's `blamed` column, enumerated so a caller
  # cannot spell one differently at two sites.
  party = {
    supplier = "supplier";
    declarer = "declarer";
    declarers = "both-declarers";
    caller = "caller";
    adapterSelector = "adapter-selector";
    proposer = "proposer";
    nobody = "nobody";
  };

  # RefusalCode — one code per row of §2.11, plus the codes marked TAKEN-DEFAULT,
  # which fill a carrier the spec's own signatures do not supply. Each of those is
  # enumerated in the landing report; none of them is a row §2.11 states.
  codes = {
    # registration
    wrappedBodyNotApplicable = "wrapped-body-not-applicable";
    supplyUnstratifiable = "supply-unstratifiable";
    bindingMarkMissing = "binding-mark-missing";

    # declare
    termVocabulary = "term-vocabulary";
    contractVocabulary = "contract-vocabulary";
    higherOrderContract = "higher-order-contract";
    mergePolicyVocabulary = "merge-policy-vocabulary";
    gateEnumNotFinite = "gate-enum-not-finite";
    declarationMissingField = "declaration-missing-field";
    importExportOverlap = "import-export-overlap";

    # mint
    litPayloadFunction = "lit-payload-function";
    litPayloadDerivation = "lit-payload-derivation";
    litPayloadBudget = "lit-payload-budget";
    litPayloadThrows = "lit-payload-throws";
    emptyRelationKind = "empty-relation-kind";

    # link
    readCtxUnresolvableSibling = "readctx-unresolvable-sibling";
    readFromNamesNonMember = "readfrom-names-non-member";
    proposalAgainstSealed = "proposal-against-sealed";

    # resolution
    pathOperandStoreCopying = "path-operand-store-copying-former";
    applyArityOrType = "apply-arity-or-type";
    applyDomain = "apply-domain";
    pathJoinOperand = "pathjoin-operand";
    formerOperandType = "former-operand-type"; # TAKEN-DEFAULT
    projectionPathMissing = "projection-path-missing"; # TAKEN-DEFAULT

    # merge
    duplicateExport = "duplicate-export";
    mergeIncompatibility = "merge-incompatibility";

    # close
    substrateDemandInexact = "substrate-placement-inexact-demand";
    adapterMissingBindFormals = "adapter-missing-bind-formals";
    adapterMissingTargetInvoked = "adapter-missing-target-invoked-channel";
    linksetIncoherent = "linkset-incoherent";
    requiredImportUnsatisfied = "required-import-unsatisfied";
    contractViolated = "contract-violated";
    gateSelectOutsideEnum = "gate-select-outside-enum";
    fragmentToken = "fragment-token";
    adapterMalformed = "adapter-malformed"; # TAKEN-DEFAULT
    valueNotObtainable = "value-not-obtainable"; # TAKEN-DEFAULT
    bodyCount = "close-body-count"; # TAKEN-DEFAULT
    deltaProjectionMissing = "delta-projection-missing"; # TAKEN-DEFAULT
  };
}

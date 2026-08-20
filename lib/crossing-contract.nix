# ContractTerm — contracts are DATA, and they are checked on the substrate side.
#
# Spec: specs/2026-08-18-gen-crossing-rederivation-spec.md §2.7, §2.10 (the
# closed algebra), §2.11 (the refusal rows).
#
# (i) A CONTRACT IS A FIRST-ORDER TERM, NOT A FUNCTION. A contract carried as a
#     closure is closure-opacity inside the crossing's own signature; functions
#     live BENEATH the algebra, as implementation, and the algebra is extensible
#     by owner ruling, never by accretion. Two things follow: a signature's
#     identity becomes ordinary structural data, and `merge`'s refusal stops
#     being conservative-by-necessity — structural equality decides contract
#     equality outright.
#
# (ii) THE CHECK RUNS SUBSTRATE-SIDE, BEFORE THE VALUE CROSSES, AND IT FORCES.
#      A monitor installed with the value is a substrate closure in the target's
#      reachable graph, and a lazy scoping does not avoid this on either time.
#      The only construction under which the payload contains no reachable
#      function is one where the check has already run and the payload is the
#      checked value.
#
#      PRICE — Degen, Thiemann and Wehr's result, reported by Chitil §8: a
#      contract system is meaning-preserving OR complete, not both. This takes
#      COMPLETENESS over the domain it can reach: every violation of a declared
#      first-order contract, on a value the substrate can force at the crossing,
#      is reported INCLUDING in parts the target would never have demanded, and a
#      fleet that succeeds today by never forcing a bad part fails under it. The
#      cost is opt-in per name — `Any` is unconstrained, said visibly, and costs
#      no forcing — so the price is paid where a contract was asked for and
#      nowhere else. No reassurance is attached: Chitil's Lemma 4.1
#      (`assert c ⊑ id`) is stated over the information-theoretic order whose
#      least element represents both non-termination and a violated contract, so
#      it ADMITS this loss rather than excluding it.
#
# (iii) HIGHER-ORDER CONTRACTS ARE NOT ADMISSIBLE. Chitil's function combinator
#       is `(>->)`, monitoring as `assert c2 . v . assert c1`, so its two
#       contracts fire ON APPLICATION — inside the consuming target — which needs
#       a substrate closure at the installation site, the one thing (ii) exists
#       to remove. A function-valued import may still cross; it may not carry a
#       function contract, it takes `Any`, and its correctness is the target's
#       concern. Findler's even-odd rule is therefore NOT REACHED: its
#       contravariant/covariant blame split needs a monitored function boundary
#       and there is none, so blame at a violation is the supplier's.
{ prelude }:
let
  refusalLib = import ./crossing-refusal.nix { inherit prelude; };
  inherit (refusalLib)
    ok
    refuse
    codes
    party
    ;

  # CLOSED, first-order, no function combinator.
  formers = [
    "Any"
    "Never"
    "Prop"
    "Attrs"
    "List"
    "And"
    "OrElse"
  ];

  # CLOSED. Whether this vocabulary covers the corpus's authored contracts is the
  # spec's own open question, measured by enumeration and never assumed.
  preds = {
    isString = builtins.isString;
    isInt = builtins.isInt;
    isBool = builtins.isBool;
    isPath = builtins.isPath;
    nonEmpty =
      v:
      if builtins.isList v then
        v != [ ]
      else if builtins.isAttrs v then
        v != { }
      else if builtins.isString v then
        v != ""
      else
        v != null;
  };

  any = {
    __contractTerm = "Any";
  };
  never = {
    __contractTerm = "Never";
  };
  prop = pred: {
    __contractTerm = "Prop";
    inherit pred;
  };
  attrs = fields: {
    __contractTerm = "Attrs";
    inherit fields;
  };
  list = item: {
    __contractTerm = "List";
    inherit item;
  };
  and = left: right: {
    __contractTerm = "And";
    inherit left right;
  };
  # Chitil's `|>`.
  orElse = left: right: {
    __contractTerm = "OrElse";
    inherit left right;
  };

  isContractTerm = v: builtins.isAttrs v && v ? __contractTerm;

  declarerRefusal =
    code: witness:
    refuse {
      inherit code witness;
      blamed = party.declarer;
    };

  # ── vocabulary check, at `declare` ───────────────────────────────────────────
  # A contract that is a FUNCTION, or a term tagged with a function combinator,
  # is the higher-order row — a distinct code from a merely unknown former,
  # because the two are refused for different reasons and a witness that cannot
  # say which is not a witness.
  higherOrderTags = [
    ">->"
    "Function"
    "Arrow"
  ];

  checkContract =
    c:
    if builtins.isFunction c then
      declarerRefusal codes.higherOrderContract {
        reason = "contract is a function";
      }
    else if !(isContractTerm c) then
      declarerRefusal codes.contractVocabulary {
        node = builtins.typeOf c;
        vocabulary = formers;
      }
    else if prelude.elem c.__contractTerm higherOrderTags then
      declarerRefusal codes.higherOrderContract {
        former = c.__contractTerm;
      }
    else if !(prelude.elem c.__contractTerm formers) then
      declarerRefusal codes.contractVocabulary {
        former = c.__contractTerm;
        vocabulary = formers;
      }
    else if c.__contractTerm == "Prop" then
      if !(preds ? ${c.pred}) then
        declarerRefusal codes.contractVocabulary {
          pred = c.pred;
          vocabulary = builtins.attrNames preds;
        }
      else
        ok c
    else
      let
        sub =
          if c.__contractTerm == "Attrs" then
            builtins.attrValues c.fields
          else if c.__contractTerm == "List" then
            [ c.item ]
          else if c.__contractTerm == "And" || c.__contractTerm == "OrElse" then
            [
              c.left
              c.right
            ]
          else
            [ ];
        bad = refusalLib.firstRefusal (builtins.map checkContract sub);
      in
      if bad != null then bad else ok c;

  # ── the interpreter, beneath the algebra ─────────────────────────────────────
  # `Any` passes WITHOUT FORCING — that is what makes the price opt-in per name.
  # Every other former forces, and `Attrs`/`List` walk every declared position,
  # including ones the target would never demand. That is completeness, and it is
  # the half of the Degen-Thiemann-Wehr disjunction this construction takes.
  violation =
    path: constructor: detail:
    refuse {
      code = codes.contractViolated;
      blamed = party.supplier;
      witness = {
        inherit path constructor detail;
      };
    };

  interpretAt =
    path: c: v:
    if c.__contractTerm == "Any" then
      ok v
    else if c.__contractTerm == "Never" then
      violation path "Never" { }
    else if c.__contractTerm == "Prop" then
      if preds.${c.pred} v then ok v else violation path "Prop" { pred = c.pred; }
    else if c.__contractTerm == "Attrs" then
      if !(builtins.isAttrs v) then
        violation path "Attrs" {
          expected = "set";
          got = builtins.typeOf v;
        }
      else
        let
          names = builtins.attrNames c.fields;
          missing = builtins.filter (n: !(v ? ${n})) names;
          results = builtins.map (n: interpretAt (path ++ [ n ]) c.fields.${n} v.${n}) names;
          bad = refusalLib.firstRefusal results;
        in
        if missing != [ ] then
          violation path "Attrs" { inherit missing; }
        else if bad != null then
          bad
        else
          ok v
    else if c.__contractTerm == "List" then
      if !(builtins.isList v) then
        violation path "List" {
          expected = "list";
          got = builtins.typeOf v;
        }
      else
        let
          results = prelude.imap0 (i: x: interpretAt (path ++ [ (builtins.toString i) ]) c.item x) v;
          bad = refusalLib.firstRefusal results;
        in
        if bad != null then bad else ok v
    else if c.__contractTerm == "And" then
      let
        l = interpretAt path c.left v;
      in
      if refusalLib.isRefusal l then l else interpretAt path c.right v
    else
      let
        l = interpretAt path c.left v;
      in
      if refusalLib.isRefusal l then interpretAt path c.right v else l;

  interpret = c: v: interpretAt [ ] c v;
in
{
  inherit
    formers
    preds
    isContractTerm
    checkContract
    interpret
    ;

  contractTerm = {
    inherit
      any
      never
      prop
      attrs
      list
      and
      orElse
      ;
  };
}

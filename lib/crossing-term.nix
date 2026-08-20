# BodyTerm — the closed, first-order body algebra that makes population P-A
# inhabitable, together with its `InertValue` minting walk, its closed primitive
# vocabulary, and its resolution.
#
# Spec: specs/2026-08-18-gen-crossing-rederivation-spec.md §2.10 (the algebra),
# §2.10a (totality over every former's argument domain), §2.10b (`Lit` is
# CONSTRAINED and the walk is bounded), §2.10c (`Concat` is string-only; paths
# take `PathJoin`), §2.11 (the refusal rows).
#
# The property every former preserves: a TargetId is LITERAL in the term. The
# algebra is closed so that no term can compute WHICH fixpoint to read; a former
# that let one do so would return the demand relation to the sealed-closure case
# the population exists to exclude.
#
# Academic: Reynolds 1972 — the defunctionalization technique. A set of
# functions becomes a set of records interpreted by an `apply`-style function
# beneath the algebra; Reynolds labels his own justification informal and states
# no completeness theorem, so the claim that this vocabulary covers the authored
# corpus is the spec's argument (its §4 Q3), never his.
{ prelude }:
let
  refusalLib = import ./crossing-refusal.nix { inherit prelude; };
  inherit (refusalLib)
    ok
    refuse
    isRefusal
    findFirst
    firstRefusal
    traverse
    traverseAttrs
    codes
    party
    ;

  supplierRefusal =
    code: witness:
    refuse {
      inherit code witness;
      blamed = party.supplier;
    };

  # ── the walk budget (§2.10b gate 2) ──────────────────────────────────────────
  # TAKEN-DEFAULT: the spec fixes that there IS a depth-and-node budget and that
  # exhausting it is a refusal BY NAME; it fixes no numbers. These are the
  # numbers, exported so they are inspectable rather than buried.
  inertBudget = {
    maxDepth = 32;
    maxNodes = 10000;
  };

  budgetRefusal = path: axis: nodesLeft: {
    ok = false;
    nodes = nodesLeft;
    refusal = supplierRefusal codes.litPayloadBudget {
      inherit path axis;
      budget = inertBudget;
    };
  };

  # ── the InertValue walk (§2.10b) ─────────────────────────────────────────────
  # Three gates, in the spec's order, so a node that is both a derivation and
  # over budget is attributed to the DERIVATION row: a witness that cannot say
  # which of four things happened is not a witness.
  #
  # The derivation test is a single attribute read applied at EVERY node BEFORE
  # descending into any attrset — a root-only test returns false on `{ pkg = drv; }`
  # and the nested derivation then reaches the descent and aborts.
  #
  # The walk FORCES. That is the point: a payload placed unforced is a fixpoint
  # channel the demand analysis cannot see, and forcing it during the minting
  # pass — before any target evaluation has run — makes a fixpoint-reading
  # payload self-defeating rather than silently wrong.
  walkInert =
    path: depth: nodesLeft: v:
    let
      forced = builtins.tryEval (builtins.typeOf v);
    in
    if !forced.success then
      {
        ok = false;
        nodes = nodesLeft;
        # `tryEval` yields `{ success, value }` and carries no message, so the
        # witness names the field's PATH and that it threw. Measured: there is no
        # builtin that returns a caught error's text.
        refusal = supplierRefusal codes.litPayloadThrows {
          inherit path;
          message = null;
        };
      }
    else
      let
        t = forced.value;
      in
      if t == "lambda" then
        {
          ok = false;
          nodes = nodesLeft;
          refusal = supplierRefusal codes.litPayloadFunction { inherit path; };
        }
      else
        let
          drv =
            if t == "set" then
              builtins.tryEval ((v.type or null) == "derivation")
            else
              {
                success = true;
                value = false;
              };
        in
        if !drv.success then
          {
            ok = false;
            nodes = nodesLeft;
            refusal = supplierRefusal codes.litPayloadThrows {
              path = path ++ [ "type" ];
              message = null;
            };
          }
        else if drv.value then
          {
            ok = false;
            nodes = nodesLeft;
            refusal = supplierRefusal codes.litPayloadDerivation {
              inherit path;
              isDerivation = true;
            };
          }
        # The budget is checked at EVERY node, scalars included. Checking it only
        # where the walk descends leaves a FLAT payload — a long list of scalars —
        # driving the counter past zero without ever refusing, which is the budget
        # row failing open on the one shape it most obviously has to catch.
        else if depth >= inertBudget.maxDepth then
          budgetRefusal path "depth" nodesLeft
        else if nodesLeft <= 0 then
          budgetRefusal path "nodes" nodesLeft
        else if t == "set" then
          walkMany path (depth + 1) (nodesLeft - 1) (
            builtins.map (n: {
              key = n;
              value = v.${n};
            }) (builtins.attrNames v)
          )
        else if t == "list" then
          walkMany path (depth + 1) (nodesLeft - 1) (
            prelude.imap0 (i: x: {
              key = builtins.toString i;
              value = x;
            }) v
          )
        else
          {
            ok = true;
            refusal = null;
            nodes = nodesLeft - 1;
          };

  walkMany =
    path: depth: nodesLeft: entries:
    prelude.foldl'
      (acc: e: if !acc.ok then acc else walkInert (path ++ [ e.key ]) depth acc.nodes e.value)
      {
        ok = true;
        refusal = null;
        nodes = nodesLeft;
      }
      entries;

  checkInert =
    value:
    let
      r = walkInert [ ] 0 inertBudget.maxNodes value;
    in
    if r.ok then null else r.refusal;

  # ── the closed primitive vocabulary (§2.10) ──────────────────────────────────
  # Each entry fixes ARITY, OPERAND TYPES and DOMAIN. The table's completeness is
  # the class closure: a primitive whose domain is not stated cannot be in this
  # list, so there is no residual well-typed-but-out-of-domain input left over.
  # `storeCopies` is the ⊗ mark — a primitive whose coercion copies a path into
  # the store, and therefore refuses a path operand by name (§2.10c).
  prims = {
    # `Scalar` is a DELIBERATE NARROWING, not a description of what Nix coerces:
    # Nix also coerces a list and a set carrying `__toString`/`outPath`. Admitting
    # the scalar cases only over-refuses on purpose, so the admitted set is one a
    # reader can check — and so the type row is fireable at all.
    toString = {
      arity = 1;
      types = [ "scalar" ];
      storeCopies = false;
    };
    concatStringsSep = {
      arity = 2;
      types = [
        "string"
        "listOfString"
      ];
      storeCopies = true;
    };
    length = {
      arity = 1;
      types = [ "list" ];
      storeCopies = false;
    };
    attrNames = {
      arity = 1;
      types = [ "set" ];
      storeCopies = false;
    };
    elemAt = {
      arity = 2;
      types = [
        "list"
        "int"
      ];
      storeCopies = false;
    };
    getAttr = {
      arity = 2;
      types = [
        "name"
        "set"
      ];
      storeCopies = false;
    };
  };

  scalarTypes = [
    "string"
    "int"
    "float"
    "bool"
    "path"
    "null"
  ];

  hasType =
    want: v:
    if want == "scalar" then
      prelude.elem (builtins.typeOf v) scalarTypes
    else if want == "string" || want == "name" then
      builtins.isString v
    else if want == "listOfString" then
      builtins.isList v && builtins.all builtins.isString v
    else if want == "list" then
      builtins.isList v
    else if want == "set" then
      builtins.isAttrs v
    else if want == "int" then
      builtins.isInt v
    else
      false;

  # A path anywhere in an operand that a ⊗ primitive would coerce. Measured in
  # the spec: `concatStringsSep` store-copies a path IDENTICALLY to `+`, same
  # store hash, so restricting `Concat` alone re-enters the hazard through a
  # sibling former in the same closed vocabulary.
  reachesPath = v: builtins.isPath v || (builtins.isList v && builtins.any builtins.isPath v);

  # ── the formers ──────────────────────────────────────────────────────────────
  # A former propagates a refusal sitting in an operand position, so a `Lit`
  # refused at minting cannot be lost by being nested.
  guard =
    operands: build:
    let
      bad = firstRefusal operands;
    in
    if bad != null then bad else build;

  lit =
    value:
    let
      bad = checkInert value;
    in
    if bad != null then
      bad
    else
      {
        __bodyTerm = "Lit";
        inherit value;
      };

  readFrom = target: path: {
    __bodyTerm = "ReadFrom";
    inherit target path;
  };

  # The head is a SEPARATE argument, so an empty reference is not constructible.
  readCtx = head: path: {
    __bodyTerm = "ReadCtx";
    inherit head path;
  };

  if_ =
    cond: then_: else_:
    guard
      [
        cond
        then_
        else_
      ]
      {
        __bodyTerm = "If";
        inherit cond then_ else_;
      };

  attrs =
    m:
    guard (builtins.attrValues m) {
      __bodyTerm = "Attrs";
      attrs = m;
    };

  list =
    xs:
    guard xs {
      __bodyTerm = "List";
      items = xs;
    };

  concat =
    xs:
    guard xs {
      __bodyTerm = "Concat";
      items = xs;
    };

  # The head is structurally separate, so operand ORDER cannot decide the result
  # type: `path + "s"` is a path while `"s" + path` is a store-copied string, and
  # this former removes that order-dependence by construction rather than by
  # documenting it. The join is SEPARATOR-BEARING — Nix inserts none.
  pathJoin =
    head: segments:
    guard ([ head ] ++ segments) {
      __bodyTerm = "PathJoin";
      inherit head segments;
    };

  apply =
    prim: operands:
    guard operands {
      __bodyTerm = "Apply";
      inherit prim operands;
    };

  isTerm = v: builtins.isAttrs v && v ? __bodyTerm;

  children =
    t:
    if t.__bodyTerm == "If" then
      [
        t.cond
        t.then_
        t.else_
      ]
    else if t.__bodyTerm == "Attrs" then
      builtins.attrValues t.attrs
    else if t.__bodyTerm == "List" || t.__bodyTerm == "Concat" then
      t.items
    else if t.__bodyTerm == "PathJoin" then
      [ t.head ] ++ t.segments
    else if t.__bodyTerm == "Apply" then
      t.operands
    else
      [ ];

  # ── vocabulary check (§2.11, at `declare`) ───────────────────────────────────
  knownFormers = [
    "Lit"
    "ReadFrom"
    "ReadCtx"
    "If"
    "Attrs"
    "List"
    "Concat"
    "PathJoin"
    "Apply"
  ];

  checkTerm =
    t:
    if isRefusal t then
      t
    else if !(isTerm t) then
      supplierRefusal codes.termVocabulary {
        node = builtins.typeOf t;
        vocabulary = knownFormers;
      }
    else if !(prelude.elem t.__bodyTerm knownFormers) then
      supplierRefusal codes.termVocabulary {
        former = t.__bodyTerm;
        vocabulary = knownFormers;
      }
    else if t.__bodyTerm == "Apply" && !(prims ? ${t.prim}) then
      supplierRefusal codes.termVocabulary {
        prim = t.prim;
        vocabulary = builtins.attrNames prims;
      }
    else
      let
        bad = firstRefusal (builtins.map checkTerm (children t));
      in
      if bad != null then bad else ok t;

  # ── the sibling channel's head names (consumed by the stratification) ────────
  readCtxHeads =
    t:
    if !(isTerm t) then
      [ ]
    else if t.__bodyTerm == "ReadCtx" then
      [ t.head ]
    else
      prelude.unique (builtins.concatMap readCtxHeads (children t));

  # ── resolution ───────────────────────────────────────────────────────────────
  # TAKEN-DEFAULT (signature). §2.11 assigns four refusal rows to a `resolution`
  # stage but §2.10's operation list names no resolution operation and no
  # operation's signature carries a TargetId -> config environment. `targets` and
  # `siblings` are that environment, made explicit here: `targets` maps a
  # TargetId to the config root a `ReadFrom` projects from, `siblings` maps a
  # sibling binding name to its resolved VALUE (never its Binding record — the
  # record reading is rejected in §2.10a-i because a `Wrapped` sibling's record
  # carries a function that would ride into the target).
  project =
    origin: value: path:
    prelude.foldl' (
      acc: seg:
      if isRefusal acc then
        acc
      else if !(builtins.isAttrs acc.value) || !(acc.value ? ${seg}) then
        supplierRefusal codes.projectionPathMissing {
          inherit origin path;
          missing = seg;
        }
      else
        ok acc.value.${seg}
    ) (ok value) path;

  resolveTerm =
    env: t:
    let
      inherit (env) targets siblings;
      recurse = resolveTerm env;
    in
    if isRefusal t then
      t
    else if !(isTerm t) then
      supplierRefusal codes.termVocabulary {
        node = builtins.typeOf t;
        vocabulary = knownFormers;
      }
    else if t.__bodyTerm == "Lit" then
      ok t.value
    else if t.__bodyTerm == "ReadFrom" then
      # TAKEN-DEFAULT (stage). §2.11 places the naming-a-non-member row at `link`,
      # but `link`'s signature in §2.10 carries NO member list — the Linkset first
      # appears at `close`. The row and the signature contradict each other, and
      # no reading of the surface as written can fire the row where the table puts
      # it. It fires here, where the resolution environment is in scope, and again
      # at `close` under the coherence row, which subsumes it: a target a term
      # names is in the demand set, hence in the cross-unit environment the
      # containment check ranges over. A SPEC-TRAIL APPEND IS OWED.
      if !(targets ? ${t.target}) then
        supplierRefusal codes.readFromNamesNonMember {
          target = t.target;
          available = builtins.attrNames targets;
        }
      else
        project { readFrom = t.target; } targets.${t.target} t.path
    else if t.__bodyTerm == "ReadCtx" then
      if !(siblings ? ${t.head}) then
        supplierRefusal codes.readCtxUnresolvableSibling {
          head = t.head;
          siblings = builtins.attrNames siblings;
        }
      else
        project { readCtx = t.head; } siblings.${t.head} t.path
    else if t.__bodyTerm == "If" then
      let
        c = recurse t.cond;
      in
      if isRefusal c then
        c
      else if !(builtins.isBool c.value) then
        supplierRefusal codes.formerOperandType {
          former = "If";
          position = "cond";
          expected = "bool";
          got = builtins.typeOf c.value;
        }
      else
        recurse (if c.value then t.then_ else t.else_)
    else if t.__bodyTerm == "Attrs" then
      traverseAttrs t.attrs (_: recurse)
    else if t.__bodyTerm == "List" then
      traverse t.items recurse
    else if t.__bodyTerm == "Concat" then
      let
        r = traverse t.items recurse;
      in
      if isRefusal r then
        r
      else if builtins.any builtins.isPath r.value then
        supplierRefusal codes.pathOperandStoreCopying {
          former = "Concat";
          operands = builtins.map builtins.typeOf r.value;
        }
      else if !(builtins.all builtins.isString r.value) then
        supplierRefusal codes.formerOperandType {
          former = "Concat";
          expected = "string";
          got = builtins.map builtins.typeOf r.value;
        }
      else
        ok (builtins.concatStringsSep "" r.value)
    else if t.__bodyTerm == "PathJoin" then
      resolvePathJoin recurse t
    else
      resolveApply recurse t;

  # A `..` PATH COMPONENT escapes above the head's directory and Nix normalises
  # it silently; a `..` SUBSTRING (`a..b`) is harmless and must not be refused,
  # so the predicate is over components.
  pathComponents = seg: builtins.filter builtins.isString (builtins.split "/" seg);

  resolvePathJoin =
    recurse: t:
    let
      h = recurse t.head;
      segs = traverse t.segments recurse;
    in
    if isRefusal h then
      h
    else if isRefusal segs then
      segs
    else if !(builtins.isPath h.value) then
      supplierRefusal codes.pathJoinOperand {
        position = "head";
        expected = "path";
        got = builtins.typeOf h.value;
      }
    else if !(builtins.all builtins.isString segs.value) then
      supplierRefusal codes.pathJoinOperand {
        position = "segment";
        expected = "string";
        got = builtins.map builtins.typeOf segs.value;
      }
    else
      let
        escaping = builtins.filter (s: prelude.elem ".." (pathComponents s)) segs.value;
      in
      if escaping != [ ] then
        supplierRefusal codes.pathJoinOperand {
          position = "segment";
          reason = "parent-directory-component";
          segments = escaping;
        }
      else
        ok (prelude.foldl' (acc: seg: acc + ("/" + seg)) h.value segs.value);

  resolveApply =
    recurse: t:
    let
      spec = prims.${t.prim} or null;
    in
    if spec == null then
      supplierRefusal codes.termVocabulary {
        prim = t.prim;
        vocabulary = builtins.attrNames prims;
      }
    else if builtins.length t.operands != spec.arity then
      supplierRefusal codes.applyArityOrType {
        prim = t.prim;
        expectedArity = spec.arity;
        got = builtins.length t.operands;
      }
    else
      let
        r = traverse t.operands recurse;
      in
      if isRefusal r then
        r
      else
        let
          vs = r.value;
          storeCopyOperands = builtins.filter reachesPath vs;
          badTypeIndex = findFirst (
            i: !(hasType (builtins.elemAt spec.types i) (builtins.elemAt vs i))
          ) null (prelude.range 0 (spec.arity - 1));
        in
        # The store-copy predicate runs FIRST for a ⊗ former: a path operand is
        # refused as a store-copying coercion, never reported as a mere type
        # mismatch, because the hazard is the silent store copy of the file.
        if spec.storeCopies && storeCopyOperands != [ ] then
          supplierRefusal codes.pathOperandStoreCopying {
            prim = t.prim;
            operands = builtins.map builtins.typeOf vs;
          }
        else if badTypeIndex != null then
          supplierRefusal codes.applyArityOrType {
            prim = t.prim;
            position = badTypeIndex;
            expected = builtins.elemAt spec.types badTypeIndex;
            got = builtins.typeOf (builtins.elemAt vs badTypeIndex);
          }
        else
          applyPrim t.prim vs;

  applyPrim =
    prim: vs:
    let
      a = builtins.elemAt vs 0;
      b = if builtins.length vs > 1 then builtins.elemAt vs 1 else null;
    in
    if prim == "toString" then
      ok (builtins.toString a)
    else if prim == "concatStringsSep" then
      ok (builtins.concatStringsSep a b)
    else if prim == "length" then
      ok (builtins.length a)
    else if prim == "attrNames" then
      ok (builtins.attrNames a)
    else if prim == "elemAt" then
      # DOMAIN: measured, `elemAt` aborts UNCATCHABLY on an index its declared
      # types admit. The domain row is what makes that a named refusal instead.
      if b < 0 || b >= builtins.length a then
        supplierRefusal codes.applyDomain {
          inherit prim;
          index = b;
          length = builtins.length a;
        }
      else
        ok (builtins.elemAt a b)
    else if !(b ? ${a}) then
      # DOMAIN: `getAttr` with an absent name aborts uncatchably likewise.
      supplierRefusal codes.applyDomain {
        inherit prim;
        name = a;
        available = builtins.attrNames b;
      }
    else
      ok b.${a};
in
{
  inherit
    inertBudget
    checkInert
    checkTerm
    isTerm
    knownFormers
    prims
    readCtxHeads
    resolveTerm
    children
    ;

  term = {
    inherit
      lit
      readFrom
      readCtx
      attrs
      list
      concat
      pathJoin
      apply
      ;
    ifThenElse = if_;
  };
}

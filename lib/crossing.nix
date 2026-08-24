# The crossing — the noun, its identity, and the six operations of the surface.
#
# Spec: specs/2026-08-18-gen-crossing-rederivation-spec.md §2.1 (a crossing is a
# NODE), §2.2 (the three edges), §2.4 (what stays declared), §2.4a (the
# granularity register), §2.5 (placement in two steps at two operations), §2.6
# (the queries), §2.9 (gating), §2.10 (the surface), §2.11 (the refusals).
#
# ★ A CROSSING IS A BINDING NODE: the reified relation between an import
# declaration, a BINDING, and a consuming target. The middle relatum is the
# BINDING, not the supply, and the granularity is uniform on that choice
# throughout — the demand relation is a property of a BODY, a body is a field of
# a Binding, so a Supply is one EMITTER OF MANY crossings rather than a relatum
# of one. Making the supply the relatum would put the over-approximation back at
# the node: one congruence verdict per supply demotes every plain binding whose
# sibling carries a producer.
#
# It is a NODE and not an edge because a relation that must carry content cannot
# be an edge — the substrate's one edge carries no payload it interprets, and a
# crossing carries its congruence verdict, its residue bit and its refusal
# witness.
#
# ★ MINTING IS STAGED. A crossing relates only nodes minted in strictly earlier
# passes: the import at `declare`, the binding at emission, the target at fleet
# registration, the crossing itself later. Its user-visible cost, stated as the
# law states its own: a crossing whose binding is itself the output of another
# crossing takes two passes.
#
# ★ CONTENT-INDEPENDENCE. Two emitters presenting the same relata under
# different label orders mint ONE crossing; order-insensitivity holds AT THE
# ENCODING and no caller owes a sort. Two emitters producing the same relata with
# different content yield one node with contributions from both — refusal at
# minting is foreclosed, refusal at content merge stays available.
{ prelude }:
let
  refusalLib = import ./crossing-refusal.nix { inherit prelude; };
  termLib = import ./crossing-term.nix { inherit prelude; };
  bindingLib = import ./crossing-binding.nix { inherit prelude; };
  deltaLib = import ./crossing-delta.nix { inherit prelude; };
  contractLib = import ./crossing-contract.nix { inherit prelude; };
  adapterLib = import ./crossing-adapter.nix { inherit prelude; };
  linksetLib = import ./crossing-linkset.nix { inherit prelude; };

  # The concrete adapters — ADR-0031 F2's destination for gen-flake's
  # `inject.nix` and `terminals.nix`. `crossing-adapter.nix` defines the Adapter
  # type and resolves placement; that file defines the instances. The contract
  # interpreter is threaded in because it is SUBSTRATE-side and target-agnostic:
  # an adapter chooses its Body, never its own contract semantics.
  adapterSetLib = import ./crossing-adapter-set.nix {
    inherit prelude;
    inherit (contractLib) interpret;
  };

  inherit (refusalLib)
    ok
    refuse
    isRefusal
    andThen
    firstRefusal
    codes
    party
    ;

  # ── identity ─────────────────────────────────────────────────────────────────
  # `hashIdentity` is the SUBSTRATE'S ONE MINTING AUTHORITY and this file does not
  # define a second one: it is injected. What this file owns is the LABELS and the
  # canonical ordering — order-insensitivity is a property of the encoding, so two
  # emitters presenting the same relata under different label orders mint one
  # crossing and no caller owes a sort.
  relationLabels = [
    "import"
    "binding"
    "target"
  ];

  # ★★ THIS FILE SHIPS NO MINTING FORMULA, NOT EVEN AS A CONVENIENCE DEFAULT.
  # ADR-0016 gives the substrate ONE minting authority; a formula shipped here as
  # a fallback would be a SECOND one, reachable by any consumer who simply
  # omitted the injection, and the omission would be invisible at the call site.
  # The injected form is the licensed one, so the injection is REQUIRED and its
  # absence refuses by name. An earlier revision shipped a `sha256` stand-in on
  # the published surface and pre-wired the operation set with it; both are gone.
  # The test suite injects a stand-in EXPLICITLY, from its own fixtures.
  mintIdentity =
    hashIdentity: kind: relata:
    if kind == "" then
      refuse {
        code = codes.emptyRelationKind;
        blamed = party.caller;
        witness = {
          inherit kind;
        };
      }
    else
      ok (hashIdentity kind (builtins.attrNames relata) (l: relata.${l}));

  # ── the declared surface ─────────────────────────────────────────────────────
  mergePolicyNames = [
    "one"
    "first"
    "concat"
    "joinDeclared"
  ];

  # No field has a default; omission is MALFORMED, not unconstrained. `Any` is
  # how unconstrained is said, VISIBLY — absence as a silent default is a
  # decision nobody made.
  #
  # TAKEN-DEFAULT (field). §2.4 rules that the `supplied` boolean's FACT survives
  # while its carrier becomes the `satisfiedBy(import, target)` EDGE, and §2.2
  # mints that edge at `declare`; §2.10's ImportDecl enumeration omits the input
  # the mint would read. `satisfiedBy` is that input, total and with no default —
  # `null` is how "this name is not the consuming target's own obligation" is
  # said visibly. It is a DECLARED EDGE, which the law separates from a declared
  # read: a registration-time declaration is visible to analysis by construction.
  importDeclFields = [
    "merge"
    "contract"
    "required"
    "sealed"
    "origin"
    "satisfiedBy"
  ];

  exportDeclFields = [
    "contract"
    "origin"
  ];

  # `origin` is deliberately OUT of the comparison: two declarers of the same
  # name necessarily differ there, and the spec's own witness carries BOTH
  # origins beside the differing fields — so treating a differing origin as the
  # incompatibility would refuse every compatible merge and report the wrong
  # thing about it.
  importCompareFields = builtins.filter (f: f != "origin") importDeclFields;
  exportCompareFields = builtins.filter (f: f != "origin") exportDeclFields;

  fragmentToken = {
    __fragmentToken = "gen-bind:crossing";
  };

  declarerRefusal =
    code: witness:
    refuse {
      inherit code witness;
      blamed = party.declarer;
    };

  missingFields =
    fields: decl:
    if !(builtins.isAttrs decl) then fields else builtins.filter (f: !(decl ? ${f})) fields;

  checkImportDecl =
    name: d:
    let
      missing = missingFields importDeclFields d;
    in
    if missing != [ ] then
      declarerRefusal codes.declarationMissingField {
        object = "ImportDecl";
        inherit name missing;
      }
    else if !(prelude.elem d.merge mergePolicyNames) then
      declarerRefusal codes.mergePolicyVocabulary {
        inherit name;
        policy = d.merge;
        vocabulary = mergePolicyNames;
      }
    else
      contractLib.checkContract d.contract;

  checkExportDecl =
    name: d:
    let
      missing = missingFields exportDeclFields d;
    in
    if missing != [ ] then
      declarerRefusal codes.declarationMissingField {
        object = "ExportDecl";
        inherit name missing;
      }
    else
      contractLib.checkContract d.contract;

  checkSignature =
    sig:
    let
      missing = missingFields [ "imports" "exports" ] sig;
    in
    if missing != [ ] then
      declarerRefusal codes.declarationMissingField {
        object = "Signature";
        inherit missing;
      }
    else
      let
        importNames = builtins.attrNames sig.imports;
        exportNames = builtins.attrNames sig.exports;
        overlap = builtins.filter (n: sig.exports ? ${n}) importNames;
        bad = firstRefusal (
          builtins.map (n: checkImportDecl n sig.imports.${n}) importNames
          ++ builtins.map (n: checkExportDecl n sig.exports.${n}) exportNames
        );
      in
      if bad != null then
        bad
      # Cardelli Definition 5-2: imp(L) intersect exp(L) is empty.
      else if overlap != [ ] then
        declarerRefusal codes.importExportOverlap { names = overlap; }
      else
        ok sig;

  satisfiedByEdges =
    sig:
    prelude.filterAttrs (_: v: v != null) (
      prelude.genAttrs (builtins.attrNames sig.imports) (n: sig.imports.${n}.satisfiedBy)
    );

  mkFragment =
    f:
    f
    // {
      body = if builtins.length f.bodies == 1 then builtins.head f.bodies else null;
      token = fragmentToken;
    };

  # ── declare ──────────────────────────────────────────────────────────────────
  declare =
    sig: body:
    andThen (checkSignature sig) (
      s:
      ok (mkFragment {
        signature = s;
        declared = s;
        bodies = [ body ];
        crossings = [ ];
        nodes = { };
        edges = {
          satisfiedBy = satisfiedByEdges s;
        };
        gate = null;
      })
    );

  # ── merge ────────────────────────────────────────────────────────────────────
  # Cardelli Definition 5-7's precondition: exp(L) intersect exp(L') is empty.
  # The import halves may overlap, and a differing declaration is an
  # INCOMPATIBILITY refused with BOTH origins — structural equality decides it,
  # contracts now being first-order data, so the refusal is no longer
  # conservative-by-necessity.
  differingFields = a: b: builtins.filter (f: a.${f} != b.${f}) importCompareFields;

  merge =
    fa: fb:
    let
      dupExports = builtins.filter (n: fb.signature.exports ? ${n}) (
        builtins.attrNames fa.signature.exports
      );
      shared = builtins.filter (n: fb.signature.imports ? ${n}) (builtins.attrNames fa.signature.imports);
      incompatible = builtins.filter (
        n: differingFields fa.signature.imports.${n} fb.signature.imports.${n} != [ ]
      ) shared;
      mergedSig = {
        imports = fa.signature.imports // fb.signature.imports;
        exports = fa.signature.exports // fb.signature.exports;
      };
      overlap = builtins.filter (n: mergedSig.exports ? ${n}) (builtins.attrNames mergedSig.imports);
    in
    if dupExports != [ ] then
      refuse {
        code = codes.duplicateExport;
        blamed = party.declarers;
        witness = {
          names = dupExports;
          origins = builtins.map (n: {
            inherit n;
            left = fa.signature.exports.${n}.origin;
            right = fb.signature.exports.${n}.origin;
          }) dupExports;
        };
      }
    else if incompatible != [ ] then
      refuse {
        code = codes.mergeIncompatibility;
        blamed = party.declarers;
        witness = builtins.map (n: {
          name = n;
          fields = differingFields fa.signature.imports.${n} fb.signature.imports.${n};
          origins = [
            fa.signature.imports.${n}.origin
            fb.signature.imports.${n}.origin
          ];
        }) incompatible;
      }
    else if overlap != [ ] then
      declarerRefusal codes.importExportOverlap { names = overlap; }
    else
      ok (mkFragment {
        signature = mergedSig;
        declared = {
          imports = fa.declared.imports // fb.declared.imports;
          exports = fa.declared.exports // fb.declared.exports;
        };
        bodies = fa.bodies ++ fb.bodies;
        crossings = prelude.unique (fa.crossings ++ fb.crossings);
        nodes = fa.nodes // fb.nodes;
        edges = {
          satisfiedBy = fa.edges.satisfiedBy // fb.edges.satisfiedBy;
        };
        gate = if fa.gate != null then fa.gate else fb.gate;
      });

  # ── gate ─────────────────────────────────────────────────────────────────────
  # Jones's Trick applies "when a dynamic variable d is known to assume one of a
  # finite set F of statically computable values". That is a PRECONDITION, and it
  # is ENFORCED here rather than inherited: a gate whose `enum` is not finite and
  # determined before any target fixpoint is refused at `declare`, naming the
  # gate. Without the row the surface would face a choice between writing a
  # conditional edge and silently producing an incomplete union.
  #
  # With the precondition enforced every branch is MATERIALIZED, so a gated
  # fragment's declared edge set is the union over branches UNCONDITIONALLY —
  # whether or not that branch is selected. Nothing here writes a conditional edge
  # or a suppression.
  selectTerm = {
    literal = key: {
      __selectTerm = "Literal";
      inherit key;
    };
    readOption = path: {
      __selectTerm = "ReadOption";
      inherit path;
    };
  };

  # TAKEN-DEFAULT (reading). Two branches of ONE gate are ALTERNATIVES, not two
  # fragments being linked, so Cardelli's export disjointness does not apply
  # between them: identical declarations union, and only a DIFFERING one is the
  # incompatibility the spec says must refuse rather than silently union.
  unionAlternative =
    kind: fields: a: b:
    let
      shared = builtins.filter (n: b ? ${n}) (builtins.attrNames a);
      differing = builtins.filter (n: builtins.any (f: a.${n}.${f} != b.${n}.${f}) fields) shared;
    in
    if differing != [ ] then
      refuse {
        code = codes.mergeIncompatibility;
        blamed = party.declarers;
        witness = {
          object = kind;
          names = differing;
        };
      }
    else
      ok (a // b);

  mergeBranch =
    acc: f:
    andThen acc (
      g:
      andThen (unionAlternative "ImportDecl" importCompareFields g.signature.imports f.signature.imports)
        (
          imports:
          andThen (unionAlternative "ExportDecl" exportCompareFields g.signature.exports f.signature.exports)
            (
              exports:
              ok (
                g
                // {
                  signature = { inherit imports exports; };
                  declared = { inherit imports exports; };
                  bodies = g.bodies ++ f.bodies;
                  crossings = prelude.unique (g.crossings ++ f.crossings);
                  nodes = g.nodes // f.nodes;
                  edges = {
                    satisfiedBy = g.edges.satisfiedBy // f.edges.satisfiedBy;
                  };
                }
              )
            )
        )
    );

  gate =
    g:
    let
      missing = missingFields [ "enum" "select" "branches" ] g;
      enumForced =
        if missing != [ ] then
          { success = false; }
        else
          builtins.tryEval (builtins.isList g.enum && builtins.all builtins.isString g.enum && g.enum != [ ]);
      keys = if missing != [ ] then [ ] else g.enum;
      uncovered = builtins.filter (k: !(g.branches ? ${k})) keys;
      extra =
        if missing != [ ] then
          [ ]
        else
          builtins.filter (k: !(prelude.elem k keys)) (builtins.attrNames g.branches);
      branchList = builtins.map (k: g.branches.${k}) keys;
    in
    if missing != [ ] then
      declarerRefusal codes.declarationMissingField {
        object = "Gate";
        inherit missing;
      }
    else if !enumForced.success || !enumForced.value then
      declarerRefusal codes.gateEnumNotFinite {
        reason =
          if !enumForced.success then
            "enum is not determined before any target fixpoint"
          else
            "enum is not a non-empty list of keys";
      }
    else if uncovered != [ ] || extra != [ ] then
      declarerRefusal codes.declarationMissingField {
        object = "Gate";
        field = "branches";
        inherit uncovered extra;
      }
    else
      andThen (prelude.foldl' mergeBranch (ok (builtins.head branchList)) (builtins.tail branchList)) (
        merged:
        ok (
          mkFragment (
            merged
            // {
              gate = {
                inherit (g) enum select;
              };
            }
          )
        )
      );

  # ── residue ──────────────────────────────────────────────────────────────────
  # The unsatisfied portion of a TOTAL signature. The totality rule — no field
  # defaults, omission is malformed — is what stops the minuend being incomplete,
  # which is why this cannot be structurally always empty.
  residue = fragment: fragment.signature;

  tokenValid = fragment: (fragment.token or null) == fragmentToken;

  tokenRefusal =
    fragment:
    refuse {
      code = codes.fragmentToken;
      blamed = party.caller;
      witness = {
        token = fragment.token or null;
      };
    };

  # ── link ─────────────────────────────────────────────────────────────────────
  # `link` takes the CONSUMING TARGET because the congruence predicate is
  # localized to it and is evaluated there; `declare` and `merge` stay
  # fleet-independent, so a fragment is declared once and linked everywhere.
  #
  # STEP 1 — the CONGRUENCE PREDICATE. staticityAdmissible(c) is the negation of
  # "this binding demands this target", a pure query over the MATERIALIZED
  # projection and never the raw relation: it forces nothing, and both operands
  # are in hand here.
  #
  # STEP 1b — the RESIDUE ATTRIBUTE, recorded beside it. Without it the promise
  # that the residue is "recorded at the crossing" has no field to keep it, and
  # deciding the derived class needs a traversal the surface never states. It
  # costs no second walk.
  mkLink =
    hashIdentity: targetId: projection: supply: fragment:
    let
      bindings = supply.bindings or { };
      names = builtins.attrNames bindings;

      danglingHeads = builtins.concatMap (
        n:
        builtins.map (h: {
          binding = n;
          head = h;
        }) (builtins.filter (h: !(bindings ? ${h})) (deltaLib.outEdges bindings.${n}))
      ) names;

      sealedProposals = builtins.filter (
        n: (fragment.signature.imports.${n} or null) != null && fragment.signature.imports.${n}.sealed
      ) (builtins.attrNames (supply.proposals or { }));

      satisfied = builtins.filter (n: bindings ? ${n}) (builtins.attrNames fragment.signature.imports);

      missingProjection = builtins.filter (n: !(projection ? ${n})) satisfied;

      # TAKEN-DEFAULT (the binding relatum's identity). §2.1 fixes the three
      # relata and says each contributes "that relatum's identity"; it does not
      # say what a BINDING's identity is, and §2.10's `Binding` carries no
      # identity field. The default here is the binding's NAME WITHIN ITS SUPPLY,
      # which is unique there by construction. Its visible consequence is
      # deliberate and is content-independence, not a collision: two supplies
      # binding the same name at the same target mint ONE crossing with
      # contributions from both, which is exactly what §2.1 rules for two emitters
      # presenting the same relata. It would need revisiting if a binding ever
      # acquires an identity of its own.
      nodeFor =
        n:
        andThen
          (mintIdentity hashIdentity "crossing" {
            import = n;
            binding = n;
            target = targetId;
          })
          (
            id:
            ok {
              inherit id;
              import = n;
              binding = n;
              target = targetId;
              staticityAdmissible = !(prelude.elem targetId (deltaLib.demands projection n));
              deltaExact = deltaLib.deltaExact projection n;
              record = bindings.${n};
              origin = supply.origins.${n} or null;
            }
          );

      nodeResults = builtins.map nodeFor satisfied;
      badNode = firstRefusal nodeResults;
      nodes = builtins.listToAttrs (
        builtins.map (r: {
          name = r.value.id;
          value = r.value;
        }) nodeResults
      );
    in
    if !(tokenValid fragment) then
      tokenRefusal fragment
    else if danglingHeads != [ ] then
      refuse {
        code = codes.readCtxUnresolvableSibling;
        blamed = party.supplier;
        witness = {
          unresolved = danglingHeads;
          siblings = names;
        };
      }
    else if sealedProposals != [ ] then
      refuse {
        code = codes.proposalAgainstSealed;
        blamed = party.proposer;
        witness = {
          names = sealedProposals;
          proposals = builtins.map (n: supply.proposals.${n}) sealedProposals;
        };
      }
    else if missingProjection != [ ] then
      refuse {
        code = codes.deltaProjectionMissing;
        blamed = party.supplier;
        witness = {
          names = missingProjection;
        };
      }
    else if badNode != null then
      badNode
    else
      ok (
        mkFragment (
          fragment
          // {
            signature = {
              inherit (fragment.signature) exports;
              imports = builtins.removeAttrs fragment.signature.imports satisfied;
            };
            crossings = prelude.unique (fragment.crossings ++ builtins.attrNames nodes);
            nodes = fragment.nodes // nodes;
            siblings = (fragment.siblings or { }) // bindings;
          }
        )
      );

  # ── value obtainability ──────────────────────────────────────────────────────
  # TAKEN-DEFAULT (refusal row + the gap it names). The check runs SUBSTRATE-SIDE
  # and it FORCES, so `close` needs each contracted name's VALUE, and a name
  # placed at Substrate time needs one whether or not it carries a contract. No
  # operation's signature carries the environment that would supply one for the
  # two constructors that need a foreign scope: a `ReadFrom` needs the named
  # target's config root, and a `Wrapped` body needs a ProducerScope. Rather than
  # skipping those checks — silence reading as success — this refuses BY NAME and
  # the witness says which carrier is missing.
  hasReadFrom =
    t:
    termLib.isTerm t && (t.__bodyTerm == "ReadFrom" || builtins.any hasReadFrom (termLib.children t));

  obtainable =
    siblings: b:
    if b.__binding == "Plain" || b.__binding == "Scoped" then
      true
    else if b.__binding == "Wrapped" then
      false
    else
      !(hasReadFrom b.term)
      && builtins.all (h: (siblings ? ${h}) && obtainable siblings siblings.${h}) (deltaLib.outEdges b);

  # Only ever forced along an OBTAINABLE chain: `substrateValue` establishes
  # obtainability before it resolves a term, so no entry read from here is a
  # refusal.
  siblingValues =
    siblings:
    prelude.genAttrs (builtins.attrNames siblings) (n: (substrateValue siblings siblings.${n}).value);

  substrateValue =
    siblings: b:
    if b.__binding == "Plain" then
      ok b.value
    else if b.__binding == "Scoped" then
      # P-B: a Nix expression in its OWN file, loaded with a substrate-supplied
      # scope. The substrate decides what the body can name; the caller-lexical
      # closure is a property of the file import itself.
      ok (builtins.scopedImport b.scope b.file)
    else if b.__binding == "Wrapped" then
      refuse {
        code = codes.valueNotObtainable;
        blamed = party.supplier;
        witness = {
          constructor = "Wrapped";
          inherit (b) producer;
          missingCarrier = "ProducerScope";
        };
      }
    else if hasReadFrom b.term then
      refuse {
        code = codes.valueNotObtainable;
        blamed = party.supplier;
        witness = {
          constructor = "Termed";
          missingCarrier = "TargetId -> config";
        };
      }
    else if !(obtainable siblings b) then
      refuse {
        code = codes.valueNotObtainable;
        blamed = party.supplier;
        witness = {
          constructor = "Termed";
          reason = "the sibling closure reaches a binding whose value needs a foreign scope";
          heads = deltaLib.outEdges b;
        };
      }
    else
      termLib.resolveTerm {
        targets = { };
        siblings = siblingValues siblings;
      } b.term;

  # ── close ────────────────────────────────────────────────────────────────────
  close =
    targetId: projection: linkset: adapter: fragment:
    let
      nodeList = builtins.map (id: fragment.nodes.${id}) fragment.crossings;
      siblings = fragment.siblings or { };

      unsatisfiedRequired = builtins.filter (
        n: fragment.signature.imports.${n}.required && !(fragment.edges.satisfiedBy ? ${n})
      ) (builtins.attrNames fragment.signature.imports);

      placementFor =
        node:
        andThen (adapterLib.placement {
          inherit (node) staticityAdmissible deltaExact;
          inherit adapter;
          name = node.import;
        }) (p: ok (node // { placement = p; }));

      placed = builtins.map placementFor nodeList;
      badPlacement = firstRefusal placed;

      gateCheck =
        if fragment.gate == null then
          ok null
        else if fragment.gate.select.__selectTerm == "Literal" then
          if prelude.elem fragment.gate.select.key fragment.gate.enum then
            ok fragment.gate.select.key
          else
            refuse {
              code = codes.gateSelectOutsideEnum;
              blamed = party.supplier;
              witness = {
                actual = fragment.gate.select.key;
                inherit (fragment.gate) enum;
              };
            }
        else
          refuse {
            code = codes.valueNotObtainable;
            blamed = party.supplier;
            witness = {
              object = "SelectTerm";
              constructor = "ReadOption";
              missingCarrier = "the consuming target's option environment";
            };
          };
    in
    if !(tokenValid fragment) then
      tokenRefusal fragment
    else
      andThen (adapterLib.mkAdapter adapter) (
        a:
        if builtins.length fragment.bodies != 1 then
          # DERIVED FROM OPACITY, not invented: Body is target-owned and produced
          # or consumed ONLY by an Adapter, so the substrate cannot combine two.
          # A merged multi-body fragment fails LOUDLY here rather than having one
          # of its bodies silently dropped.
          refuse {
            code = codes.bodyCount;
            blamed = party.caller;
            witness = {
              bodies = builtins.length fragment.bodies;
            };
          }
        else if unsatisfiedRequired != [ ] then
          refuse {
            code = codes.requiredImportUnsatisfied;
            blamed = party.supplier;
            witness = {
              names = unsatisfiedRequired;
              origins = builtins.map (n: fragment.signature.imports.${n}.origin) unsatisfiedRequired;
            };
          }
        else if badPlacement != null then
          badPlacement
        else
          andThen gateCheck (
            _:
            andThen (linksetLib.mkLinkset linkset) (
              ls:
              andThen (linksetLib.coherence {
                unit = targetId;
                crossings = nodeList;
                inherit projection;
                linkset = ls;
              }) (_: assemble a siblings fragment (builtins.map (r: r.value) placed))
            )
          )
      );

  # Contract checking is OPT-IN PER NAME: `Any` passes without forcing, so the
  # completeness price is paid where a contract was asked for and nowhere else.
  checkedValue =
    a: siblings: fragment: node:
    let
      decl = fragment.declared.imports.${node.import};
      v = substrateValue siblings node.record;
    in
    if decl.contract.__contractTerm == "Any" then
      v
    else
      andThen v (value: a.interpret decl.contract value);

  assemble =
    a: siblings: fragment: nodes:
    let
      byPlacement = ch: t: builtins.filter (n: n.placement.channel == ch && n.placement.time == t) nodes;

      substrateNodes = byPlacement adapterLib.channel.formals adapterLib.time.substrate;
      invokedNodes = byPlacement adapterLib.channel.formals adapterLib.time.targetInvoked;
      argEnvNodes = byPlacement adapterLib.channel.argEnv adapterLib.time.targetInvoked;

      valuesOf =
        ns:
        let
          results = builtins.map (n: {
            name = n.import;
            value = checkedValue a siblings fragment n;
          }) ns;
          bad = firstRefusal (builtins.map (r: r.value) results);
        in
        if bad != null then
          bad
        else
          ok (
            builtins.listToAttrs (
              builtins.map (r: {
                inherit (r) name;
                value = r.value.value;
              }) results
            )
          );

      # A TargetInvoked name is bound at target time from the TargetArgs the
      # adapter hands back. The Wrapped body is applied to them as its
      # ProducerScope — the substrate builds the wrapper and applies it, which is
      # what bounds the ARGUMENT channel and nothing lexical.
      #
      # ★ EVERY NON-`Wrapped` NODE REACHING HERE HAS ALREADY BEEN PROVEN
      # OBTAINABLE by `invokedGuard` below, which is why this may read `.value`.
      # An earlier revision read it UNGUARDED, so a `Termed` binding carrying a
      # `ReadFrom` — obtainable nowhere substrate-side — produced an uncatchable
      # `attribute 'value' missing` INSIDE the wrapFn closure, at target force
      # time, with no name of ours on it. The obtainability discipline the
      # sibling path already ran is now run on this path too, BEFORE the closure
      # is built, so the failure is a tagged refusal from `close`.
      invokedValue =
        targetArgs: n:
        if n.record.__binding == "Wrapped" then
          n.record.body targetArgs
        else
          (substrateValue siblings n.record).value;

      # Two obligations on the target-invoked channel, in one pass:
      #
      #   (1) VALUE OBTAINABILITY, for every non-`Wrapped` node and regardless of
      #       contract. A `Wrapped` body is applied to the TargetArgs at target
      #       time, so it is obtainable by construction; everything else must be
      #       obtainable SUBSTRATE-SIDE or the closure cannot be built at all.
      #   (2) THE CONTRACT, where one was declared. A contracted name whose value
      #       only exists at target time cannot be checked substrate-side, and no
      #       lazy-monitor construction delivers the invariant — so it refuses
      #       rather than crossing unchecked.
      invokedGuard =
        let
          contracted = n: fragment.declared.imports.${n.import}.contract.__contractTerm != "Any";
          results = builtins.map (
            n:
            if n.record.__binding == "Wrapped" then
              if contracted n then
                refuse {
                  code = codes.valueNotObtainable;
                  blamed = party.supplier;
                  witness = {
                    name = n.import;
                    constructor = "Wrapped";
                    reason = "a contract cannot be checked substrate-side on a target-time value";
                    missingCarrier = "ProducerScope";
                  };
                }
              else
                ok null
            else
              andThen (substrateValue siblings n.record) (
                v: if contracted n then a.interpret fragment.declared.imports.${n.import}.contract v else ok v
              )
          ) invokedNodes;
          bad = firstRefusal results;
        in
        if bad != null then bad else ok null;
    in
    andThen invokedGuard (
      _:
      andThen (valuesOf substrateNodes) (
        substrateValues:
        andThen (valuesOf argEnvNodes) (
          argEnvValues:
          # A value must reach an OPAQUE Body through `bindFormals`; there is no
          # other channel that places one, at either time.
          if (invokedNodes != [ ] || substrateNodes != [ ]) && !(adapterLib.offers a "bindFormals") then
            refuse {
              code = codes.adapterMissingBindFormals;
              blamed = party.adapterSelector;
              witness = {
                names = builtins.map (n: n.import) (substrateNodes ++ invokedNodes);
              };
            }
          else
            let
              body0 = builtins.head fragment.bodies;
              body1 = if substrateNodes == [ ] then body0 else a.bindFormals substrateValues body0;
              body2 =
                if invokedNodes == [ ] then
                  body1
                else
                  a.wrapFn (
                    targetArgs:
                    a.bindFormals (builtins.listToAttrs (
                      builtins.map (n: {
                        name = n.import;
                        value = invokedValue targetArgs n;
                      }) invokedNodes
                    )) body1
                  );
              subUnits = if argEnvNodes == [ ] then [ ] else [ (a.bindArgEnv argEnvValues) ];
            in
            # The TargetUnit is returned exactly as the adapter built it. The
            # substrate does not read its structure — that is what its opacity IS.
            ok (a.wrapUnit body2 subUnits)
        )
      )
    );

  # THE OPERATION SET EXISTS ONLY ONCE A CONSUMER INJECTS THE MINT. The published
  # surface carries the constructors and this function; it carries no bound
  # operation, so there is no path by which a caller reaches `link` without having
  # named an authority. `hashIdentity` is a TOTAL field of this argument —
  # omitting it is malformed, not defaulted — and the refusal is a value rather
  # than Nix's own uncatchable "called without required argument".
  mkOperations =
    args:
    if !(builtins.isAttrs args) || !(args ? hashIdentity) then
      refuse {
        code = codes.declarationMissingField;
        blamed = party.caller;
        witness = {
          object = "mkOperations";
          field = "hashIdentity";
          reason = "the substrate's minting authority is injected, never defaulted";
        };
      }
    else if !(builtins.isFunction args.hashIdentity) then
      refuse {
        code = codes.declarationMissingField;
        blamed = party.caller;
        witness = {
          object = "mkOperations";
          field = "hashIdentity";
          expected = "kind -> [label] -> (label -> identity) -> CrossingId";
          got = builtins.typeOf args.hashIdentity;
        };
      }
    else
      ok {
        inherit
          declare
          merge
          gate
          close
          residue
          ;
        link = mkLink args.hashIdentity;
      };
in
{
  inherit
    relationLabels
    mintIdentity
    mergePolicyNames
    importDeclFields
    exportDeclFields
    selectTerm
    mkOperations
    substrateValue
    obtainable
    ;

  inherit (refusalLib)
    isRefusal
    isOk
    codes
    party
    ;
  inherit (termLib)
    term
    inertBudget
    checkTerm
    checkInert
    resolveTerm
    readCtxHeads
    knownFormers
    prims
    ;
  inherit (bindingLib) binding mark;
  inherit (deltaLib)
    registerSupply
    strata
    deltaExact
    isExact
    demands
    exact
    ;
  inherit (contractLib) contractTerm interpret checkContract;
  contractFormers = contractLib.formers;
  contractPreds = builtins.attrNames contractLib.preds;
  inherit (adapterLib)
    mkAdapter
    placement
    channel
    time
    ;
  inherit (adapterSetLib)
    injectAdapter
    mkSystemTerminal
    mkFlakeTerminal
    ;
  inherit (linksetLib)
    mkLinkset
    environment
    linked
    coherence
    ;
}

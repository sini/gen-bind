# Binding — the three populations ARE the three constructors, plus `Plain`.
#
# Spec: specs/2026-08-18-gen-crossing-rederivation-spec.md §2.3.1 (the admission
# rule and its three populations), §2.10 (the declared surface), §2.6 item 3
# (`mark` is declared on every constructor, total and with no default).
#
# A binding's population is decidable from its TAG; no reader classifies
# anything, and the residue row of §2.11 conditions on a declared thing:
#
#   Plain    — carries no demand at all, but IS traversed by the crossing
#              queries, so it carries the floor mark like every other node.
#   Termed   — P-A. The substrate-assembled body: a first-order term the
#              substrate interprets, over which the demand set is COMPUTED.
#   Scoped   — P-B. A Nix expression in its own FILE, loaded with a
#              substrate-supplied scope. Caller-lexical closure is a property of
#              Nix's file import, not of the supplied scope; what the scope
#              contributes is that the substrate decides what the body can name.
#              The `import` channel is measured OPEN, so the demand set is
#              complete on the caller-lexical channel and not on that one.
#   Wrapped  — P-C. The foreign lambda, the shipped shape. The substrate builds a
#              wrapper and applies it, which bounds the ARGUMENT channel only;
#              the lexical channel is measured live. The residue lives here.
#
# ★ THERE IS NO `stratum` FIELD. The stratification is DERIVED from the terms
# (crossing-delta.nix) — a declared one would be a constructible fact standing
# declared, which is the defect the re-derivation exists to remove, and it gets
# no exemption for being the design's own field.
{ prelude }:
let
  refusalLib = import ./crossing-refusal.nix { inherit prelude; };
  inherit (refusalLib)
    ok
    refuse
    isRefusal
    codes
    party
    ;

  # ADR-0026's fail-closed floor. TOTAL, no default: an absent declaration is a
  # design choice nobody made, and "absent means everything" fails silently.
  mark = {
    open = "Open";
    floor = "Floor";
  };

  marks = [
    mark.open
    mark.floor
  ];

  markRefusal =
    tag: got:
    refuse {
      code = codes.bindingMarkMissing;
      blamed = party.supplier;
      witness = {
        constructor = tag;
        field = "mark";
        expected = marks;
        inherit got;
      };
    };

  guardMark =
    tag: m: build:
    if !(builtins.isString m) || !(prelude.elem m marks) then markRefusal tag m else build;

  plain =
    {
      value,
      mark,
    }:
    guardMark "Plain" mark {
      __binding = "Plain";
      inherit value mark;
    };

  termed =
    {
      term,
      mark,
    }:
    guardMark "Termed" mark (
      if isRefusal term then
        term
      else
        {
          __binding = "Termed";
          inherit term mark;
        }
    );

  scoped =
    {
      file,
      scope,
      producer,
      mark,
    }:
    guardMark "Scoped" mark {
      __binding = "Scoped";
      inherit
        file
        scope
        producer
        mark
        ;
    };

  # §2.11 row 1: a `Wrapped` binding whose body the substrate does not itself
  # apply is refused at registration. The substrate applies the body to a
  # ProducerScope, so a body it cannot apply is one that is not a function.
  wrapped =
    {
      producer,
      body,
      mark,
    }:
    guardMark "Wrapped" mark (
      if !(builtins.isFunction body) then
        refuse {
          code = codes.wrappedBodyNotApplicable;
          blamed = party.supplier;
          witness = {
            inherit producer;
            bodyType = builtins.typeOf body;
          };
        }
      else
        {
          __binding = "Wrapped";
          inherit producer body mark;
        }
    );

  isBinding = v: builtins.isAttrs v && v ? __binding;

  constructors = [
    "Plain"
    "Termed"
    "Scoped"
    "Wrapped"
  ];

  # The producer a non-`Termed` constructor contributes to the demand set;
  # null where the constructor carries none.
  producerOf = b: if b.__binding == "Scoped" || b.__binding == "Wrapped" then b.producer else null;
in
{
  inherit
    mark
    marks
    isBinding
    constructors
    producerOf
    ;

  binding = {
    inherit
      plain
      termed
      scoped
      wrapped
      ;
  };

  checkBinding =
    b:
    if isRefusal b then
      b
    else if !(isBinding b) then
      refuse {
        code = codes.declarationMissingField;
        blamed = party.supplier;
        witness = {
          field = "__binding";
          expected = constructors;
          got = builtins.typeOf b;
        };
      }
    else if !(prelude.elem b.__binding constructors) then
      refuse {
        code = codes.declarationMissingField;
        blamed = party.supplier;
        witness = {
          constructor = b.__binding;
          expected = constructors;
        };
      }
    else
      ok b;
}

# den-hoag-bme8i, the 2026-09-30 ruling (Q1a, Q1b = E2, C11). A binding's VALUE is part of its
# crossing identity, so user=alice and user=bob crossing one target are two crossings. Where two
# operands hold one crossing id, the pair is the same binding iff it was declared at the same
# site, the supplier's `origin` plus the source position of the binding's attribute; a pair
# declared apart is refused by name at MERGE (and at a gate's branch union), never dropped. Both
# per-binding maps are total at registration, and a value identity is a minted node, never a bare
# name. A pair whose sites are both null cannot show it was declared once and refuses too (K1, arm
# (b)). Spec: specs/2026-10-02-gen-bind-relata-identity-origin-merge-spec.md (den-ag-design) §3a.
#
# Every supply below is WRITTEN in this file, one literal each, so each `user` attribute carries
# its own source position.
{ genBind, ... }:
let
  f = import ./_crossing-fixtures.nix { inherit genBind; };
  inherit (f)
    x
    sig
    imp
    wrappedB
    entity
    _testHashIdentity
    ;
  c = x.contractTerm;

  fragment = (x.declare (sig { user = imp c.any; }) null).value;
  link = target: r: (x.link target r fragment).value;
  outcome =
    m:
    if x.isOk m then
      { nodes = builtins.length (builtins.attrNames m.value.nodes); }
    else
      { refused = m.refusal.code; };

  alice =
    (x.registerSupply {
      bindings.user = wrappedB "den" (_: "alice");
      proposals = { };
      origins.user = "users/alice.nix";
      valueIdentities.user = entity "alice";
    }).value;
  bob =
    (x.registerSupply {
      bindings.user = wrappedB "den" (_: "bob");
      proposals = { };
      origins.user = "users/bob.nix";
      valueIdentities.user = entity "bob";
    }).value;
  # Two DIFFERENT bodies declared in ONE file under one file-granular origin.
  aliceV1 =
    (x.registerSupply {
      bindings.user = wrappedB "den" (_: "alice-v1");
      proposals = { };
      origins.user = "users.nix";
      valueIdentities.user = entity "alice";
    }).value;
  aliceV2 =
    (x.registerSupply {
      bindings.user = wrappedB "den" (_: "alice-v2");
      proposals = { };
      origins.user = "users.nix";
      valueIdentities.user = entity "alice";
    }).value;
  imported =
    (x.registerSupply (import ./_crossing-origin-supply.nix { inherit wrappedB entity; })).value;
  importedAgain =
    (x.registerSupply (import ./_crossing-origin-supply.nix { inherit wrappedB entity; })).value;

  registerWith =
    maps:
    x.registerSupply (
      {
        bindings.user = wrappedB "den" (_: "alice");
        proposals = { };
        origins.user = "users/alice.nix";
        valueIdentities.user = entity "alice";
      }
      // maps
    );
  node = l: l.nodes.${builtins.head l.crossings};
  # R1: one factory, so one written `user` attribute for every body passed in.
  factory =
    body:
    (x.registerSupply {
      bindings.user = wrappedB "den" body;
      proposals = { };
      origins.user = "users.nix";
      valueIdentities.user = entity "alice";
    }).value;
  # R2: `mapAttrs` builds the attribute, so it carries no position.
  mapped =
    body:
    (x.registerSupply {
      bindings = builtins.mapAttrs (_: b: wrappedB "den" b) { user = body; };
      proposals = { };
      origins.user = "users.nix";
      valueIdentities.user = entity "alice";
    }).value;
  # One written binding, so ONE source position; only the declared origin differs.
  aliceHere = (registerWith { }).value;
  aliceElsewhere = (registerWith { origins.user = "users/alice-too.nix"; }).value;
in
{
  # Q1a: the den fan-out. One `{ user, ... }` fragment, alice and bob, one host target.
  flake.tests.crossing-binding-origin.test-bme8i-fanout-two-values-one-target-are-two-crossings = {
    expr = outcome (x.merge (link "igloo" alice) (link "igloo" bob));
    expected = {
      nodes = 2;
    };
  };

  flake.tests.crossing-binding-origin.test-bme8i-binding-relatum-carries-the-value = {
    expr = [
      ((node (link "igloo" alice)).binding == (node (link "igloo" bob)).binding)
      (
        (node (link "igloo" alice)).binding
        == _testHashIdentity "binding" [ "key" "value" ] (l: if l == "key" then "user" else entity "alice")
      )
    ];
    expected = [
      false
      true
    ];
  };

  # Q1b (E2): one written binding under two declared origins, refused by name in both orders.
  flake.tests.crossing-binding-origin.test-bme8i-different-origins-refuse-by-name = {
    expr = [
      (outcome (x.merge (link "igloo" aliceHere) (link "igloo" aliceElsewhere)))
      (outcome (x.merge (link "igloo" aliceElsewhere) (link "igloo" aliceHere)))
      (map (w: w.origins)
        (x.merge (link "igloo" aliceHere) (link "igloo" aliceElsewhere)).refusal.witness or [ ]
      )
    ];
    expected = [
      { refused = "crossing-origin-conflict"; }
      { refused = "crossing-origin-conflict"; }
      [
        [
          "users/alice.nix"
          "users/alice-too.nix"
        ]
      ]
    ];
  };

  # The stated obligation: one file, one origin, two bodies. The attribute's position separates them.
  flake.tests.crossing-binding-origin.test-bme8i-same-file-different-bodies-refuse-by-name = {
    expr = outcome (x.merge (link "igloo" aliceV1) (link "igloo" aliceV2));
    expected = {
      refused = "crossing-origin-conflict";
    };
  };

  # A gate's branches meet through the same union.
  flake.tests.crossing-binding-origin.test-bme8i-gate-branches-declared-apart-refuse-by-name = {
    expr = outcome (
      x.gate {
        enum = [
          "a"
          "b"
        ];
        select = x.selectTerm.literal "a";
        branches = {
          a = link "igloo" aliceHere;
          b = link "igloo" aliceElsewhere;
        };
      }
    );
    expected = {
      refused = "crossing-origin-conflict";
    };
  };

  # Origins and value identities are total: absent and null are refused at registration.
  flake.tests.crossing-binding-origin.test-bme8i-absent-or-null-origin-refuses = {
    expr = map (r: r.refusal.witness.entries or "registered") [
      (registerWith { origins = { }; })
      (registerWith { origins.user = null; })
    ];
    expected = [
      [
        {
          field = "origins";
          name = "user";
        }
      ]
      [
        {
          field = "origins";
          name = "user";
        }
      ]
    ];
  };

  flake.tests.crossing-binding-origin.test-bme8i-absent-value-identity-refuses = {
    expr = (registerWith { valueIdentities = { }; }).refusal.witness.entries or "registered";
    expected = [
      {
        field = "valueIdentities";
        name = "user";
      }
    ];
  };

  # Controls: one declaration reached twice collapses, whether as one value or one file
  # imported twice (the case Nix `==` split by evaluator); distinct targets never meet.
  flake.tests.crossing-binding-origin.test-control-bme8i-one-declaration-reached-twice-collapses = {
    expr = [
      (outcome (x.merge (link "igloo" alice) (link "igloo" alice)))
      (outcome (x.merge (link "igloo" imported) (link "igloo" importedAgain)))
    ];
    expected = [
      { nodes = 1; }
      { nodes = 1; }
    ];
  };

  flake.tests.crossing-binding-origin.test-control-bme8i-host-by-user-cells-are-two-crossings = {
    expr = outcome (x.merge (link "igloo/alice" alice) (link "igloo/bob" bob));
    expected = {
      nodes = 2;
    };
  };

  flake.tests.crossing-binding-origin.test-control-bme8i-a-total-supply-registers = {
    expr = x.isOk (registerWith { });
    expected = true;
  };

  # R2: `mapAttrs`-built bindings carry no position, so an equal-origin pair cannot show it was
  # declared once. Two bodies under one origin refuse by name rather than dropping one.
  flake.tests.crossing-binding-origin.test-bme8i-positionless-pair-refuses-by-name = {
    expr = [
      (outcome (x.merge (link "igloo" (mapped (_: "alice-v1"))) (link "igloo" (mapped (_: "alice-v2")))))
      (node (link "igloo" (mapped (_: "alice")))).site
    ];
    expected = [
      { refused = "crossing-origin-conflict"; }
      null
    ];
  };

  # R2's price, pinned: ONE positionless supply reached twice refuses too, since nothing shows it
  # is one declaration.
  flake.tests.crossing-binding-origin.test-bme8i-positionless-supply-reached-twice-refuses = {
    expr =
      let
        once = mapped (_: "alice");
      in
      outcome (x.merge (link "igloo" once) (link "igloo" once));
    expected = {
      refused = "crossing-origin-conflict";
    };
  };

  # ★ R1 SURVIVOR PIN, the ENUMERATED ARGUED EXCEPTION (ADR-0025 item 1; owner-ruled 2026-10-05,
  # den-hoag-yqz1j): one factory site called with two bodies under one origin shows every
  # non-content witness an honest diamond shows. It collapses, and the RIGHT operand's body
  # survives, so the survivor depends on merge order. The caller's contract is a per-occurrence
  # origin. The exception retires with the declaration key (den-hoag-8hlo3 / den-hoag-hpusp), and
  # this cell flips then, deliberately; it pins the released behaviour, not a guarantee.
  flake.tests.crossing-binding-origin.test-exception-yqz1j-one-site-two-closures-collapses-order-dependently = {
    expr = map (m: map (n: n.record.body null) (builtins.attrValues m.value.nodes)) [
      (x.merge (link "igloo" (factory (_: "alice-v1"))) (link "igloo" (factory (_: "alice-v2"))))
      (x.merge (link "igloo" (factory (_: "alice-v2"))) (link "igloo" (factory (_: "alice-v1"))))
    ];
    expected = [
      [ "alice-v2" ]
      [ "alice-v1" ]
    ];
  };
}

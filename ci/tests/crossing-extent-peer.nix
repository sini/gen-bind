# The extent peer-read shape's acceptance oracles — O-1 through O-6.
#
# Spec: specs/2026-09-08-gen-bind-extent-peer-read-shape-spec.md §3 (the six
# oracles, the fixture stated once, and the standing check that no column may
# be flipped by text the construction itself writes). Design of record: §2
# (the mechanism), §4.1/4.2/4.3 (Q1/Q2/Q3 — forks this construction does not
# pick), §4.4/4.5 (Q4 RULED, Q5 SCHEDULING — Arm A is what is built here).
#
# ★ EVERY CELL BELOW EVALUATES BOTH ITS RED AND GREEN ARM AS DATA, IN ONE
# PASSING nix-unit CELL, matching §3's own protocol verbatim: "That probe
# composes the construction in the probe file — no gen repository is edited —
# and evaluates RED and GREEN of every column against the same fixture." The
# RED arm is a SEEDED STAND-IN reproducing the literal pre-fix carriage
# (`{ nodes = extent; } // passthrough;`, unbounded) rather than a checkout of
# gen-bind `c5917d5` — composed here exactly as the spec's own probe was.
#
# ★★ Q5 ARM A IS THE ONLY ARM BUILT. `outEdges` (`lib/crossing-delta.nix`)
# still sees only `Termed` bindings, so δ still cannot see this carriage and
# `E(u)` still cannot count it — no cell here asserts otherwise, and none may
# be read as doing so.
{
  genBind,
  graph,
  genDelivery,
  genViewCarrier,
  ...
}:
let
  inherit (genBind.crossing) mkHostedTerminal;

  # ── the fixture, stated once (§3 "The fixture, stated once") ─────────────
  # Three-member class `host` over alpha/bravo/charlie, the complete peer
  # relation (including self-loops), alpha marked with one mark admitting no
  # label, bravo/charlie unmarked (`[ ]`).
  fixtureNodes = [
    "alpha"
    "bravo"
    "charlie"
  ];

  peerGraph = graph.labeledFrom {
    nodes = fixtureNodes;
    perLabel.peer = _id: fixtureNodes;
  };

  isolatingMarksOf =
    id:
    if id == "alpha" then
      [
        {
          name = "isolated";
          admits = _label: false;
        }
      ]
    else
      [ ];
  identityMarksOf = _id: [ ];

  # A hand-built `projected.nodes`, bypassing `gen-delivery.project`/`cnf`/
  # `aspects`/`algebra` entirely — `realize` consumes only `projected.nodes`
  # (`gen-delivery/lib/default.nix`, binding `realize`), so nothing else in
  # gen-delivery's own pipeline needs wiring for these six cells.
  projected.nodes = builtins.listToAttrs (
    map (n: {
      name = n;
      value = {
        bindings = { };
        classes.host = [ { } ];
      };
    }) fixtureNodes
  );

  # ── the GREEN terminal — the real construction, composed ─────────────────
  # `realize`'s own per-node carriage (`{name;modules;bindings;extent;
  # extraModules;passthrough?;}`) is a DIFFERENT shape from the Adapter's
  # carriage (`{extent;extraModules;peerGraph;marksOf;readerId;
  # passthrough?;thunkBindings?;}`), so composing them needs a thin wrapper —
  # exactly what O-1's own instrument text asks for: "wire the real
  # gen-delivery.realize into the real gen-bind mkHostedTerminal adapter",
  # composed in the probe file per §3's own protocol.
  mkGreenTerminal =
    {
      evaluator,
      marksOf,
      peerGraph,
    }:
    let
      t = mkHostedTerminal {
        inherit evaluator;
        locateConfig = x: x;
        class = "host";
      };
    in
    carriage:
    let
      a = t.adapter (
        {
          inherit (carriage) extent extraModules;
          inherit peerGraph marksOf;
          readerId = carriage.name;
        }
        // (if carriage ? passthrough then { passthrough = carriage.passthrough; } else { })
      );
    in
    a.wrapUnit (a.bindFormals carriage.bindings carriage.modules) [ ];

  # ── the RED terminals — the literal pre-fix carriage, seeded here ────────
  # `{ nodes = extent; } // passthrough;` unbounded — gen-bind `c5917d5`'s own
  # shape. `preFixTerminal` returns the handed KEYS (O-1); `preFixRawTerminal`
  # returns the handed VALUE itself, unforced (O-3, O-6).
  preFixTerminal = carriage: builtins.attrNames carriage.extent;
  preFixRawTerminal = carriage: carriage.extent;

  # ════════════════════════════════════════════════════════════════════════
  # O-1 — the handed peer set is narrowed by the reading node's marks
  # ════════════════════════════════════════════════════════════════════════
  o1Green = mkGreenTerminal {
    evaluator = a: builtins.attrNames a.specialArgs.nodes;
    marksOf = isolatingMarksOf;
    inherit peerGraph;
  };
  o1GreenRealized = genDelivery.realize {
    inherit projected;
    terminals.host = o1Green;
  };
  o1RedRealized = genDelivery.realize {
    inherit projected;
    terminals.host = preFixTerminal;
  };

  # ════════════════════════════════════════════════════════════════════════
  # O-2 — a withheld peer is named, with the mark that withheld it
  # ════════════════════════════════════════════════════════════════════════
  o2RedTerminal = carriage: {
    handed = builtins.attrNames carriage.extent;
    surface = builtins.sort builtins.lessThan (builtins.attrNames carriage);
  };
  o2RedRealized = genDelivery.realize {
    inherit projected;
    terminals.host = o2RedTerminal;
  };

  # `peerRelation` is reachable off the Adapter record directly — substrate
  # side, never spliced into `specialArgs` (§2.1, §4.2) — so this reads it
  # straight from `.adapter{...}`, bypassing `realize` entirely for this half.
  extentForAdapterProbe = builtins.listToAttrs (
    map (n: {
      name = n;
      value = { };
    }) fixtureNodes
  );

  greenHostedTerminal = mkHostedTerminal {
    evaluator = a: builtins.attrNames a.specialArgs.nodes;
    locateConfig = x: x;
    class = "host";
  };

  adapterFor =
    readerId:
    greenHostedTerminal.adapter {
      extent = extentForAdapterProbe;
      extraModules = [ ];
      inherit peerGraph;
      marksOf = isolatingMarksOf;
      inherit readerId;
    };

  o2AlphaAdapter = adapterFor "alpha";
  o2BravoAdapter = adapterFor "bravo";

  # ════════════════════════════════════════════════════════════════════════
  # O-3 — widening is unsayable, not merely unused
  # ════════════════════════════════════════════════════════════════════════
  o3RawGreen = mkGreenTerminal {
    evaluator = a: a.specialArgs.nodes;
    marksOf = isolatingMarksOf;
    inherit peerGraph;
  };
  o3GreenRealized = genDelivery.realize {
    inherit projected;
    terminals.host = o3RawGreen;
  };
  o3RedRealized = genDelivery.realize {
    inherit projected;
    terminals.host = preFixRawTerminal;
  };
  o3BoundedDirect = graph.boundedBy peerGraph isolatingMarksOf;

  # ════════════════════════════════════════════════════════════════════════
  # O-4 — the O-1 oracle's own instrument: the spine is readable without
  # forcing a peer artifact
  # ════════════════════════════════════════════════════════════════════════
  # A dedicated two-member fixture (alpha, bravo) with NO marks — "O-4's
  # fixture declares no marks, so the narrowing is the identity there".
  o4Nodes = [
    "alpha"
    "bravo"
  ];
  o4PeerGraph = graph.labeledFrom {
    nodes = o4Nodes;
    perLabel.peer = _id: o4Nodes;
  };
  o4Projected.nodes = builtins.listToAttrs (
    map (n: {
      name = n;
      value = {
        bindings = { };
        classes.host = [ { } ];
      };
    }) o4Nodes
  );

  o4RawGreen = mkGreenTerminal {
    evaluator = a: a.specialArgs.nodes;
    marksOf = identityMarksOf;
    peerGraph = o4PeerGraph;
  };
  # bravo's terminal is replaced by a throw — the positive control that a
  # peer READ (not a spine read) reaches and hits it.
  o4Terminal =
    carriage:
    if carriage.name == "bravo" then
      throw "gen-bind O-4 seed: peer artifact forced"
    else
      o4RawGreen carriage;
  o4Realized = genDelivery.realize {
    projected = o4Projected;
    terminals.host = o4Terminal;
  };

  # The regression half, on the ORIGINAL three-member fixture: the
  # construction must leave O-1's own instrument alone under empty marks.
  o4IdentityGreen3 = mkGreenTerminal {
    evaluator = a: builtins.attrNames a.specialArgs.nodes;
    marksOf = identityMarksOf;
    inherit peerGraph;
  };
  o4IdentityRealized = genDelivery.realize {
    inherit projected;
    terminals.host = o4IdentityGreen3;
  };

  # ════════════════════════════════════════════════════════════════════════
  # O-6 — the derived view is NAMED, and the name is checked
  # ════════════════════════════════════════════════════════════════════════
  # `refuse` in `gen-view/lib/refusal.nix` THROWS (never a tagged sentinel —
  # "AN EMPTY ANSWER IS NEVER A REFUSAL"), so `elementOf`'s failure arm is
  # read through `tryEval`, exactly as O-4's own reach probe is.
  o6RedHanded = o3RedRealized.host.alpha;
  o6GreenHanded = o2AlphaAdapter.peerRelation;
in
{
  flake.tests.crossing-extent-peer.test-o1-handed-peer-set-narrowed-by-reading-nodes-marks = {
    expr = {
      red = {
        alphaSees = o1RedRealized.host.alpha;
        bravoSees = o1RedRealized.host.bravo;
        classKeys = builtins.attrNames o1RedRealized.host;
      };
      green = {
        alphaSees = o1GreenRealized.host.alpha;
        bravoSees = o1GreenRealized.host.bravo;
        classKeys = builtins.attrNames o1GreenRealized.host;
      };
    };
    expected = {
      red = {
        alphaSees = [
          "alpha"
          "bravo"
          "charlie"
        ];
        bravoSees = [
          "alpha"
          "bravo"
          "charlie"
        ];
        classKeys = [
          "alpha"
          "bravo"
          "charlie"
        ];
      };
      green = {
        alphaSees = [ ];
        bravoSees = [
          "alpha"
          "bravo"
          "charlie"
        ];
        classKeys = [
          "alpha"
          "bravo"
          "charlie"
        ];
      };
    };
  };

  flake.tests.crossing-extent-peer.test-o2-withheld-peer-named-with-its-mark = {
    expr = {
      red = {
        alphaHanded = o2RedRealized.host.alpha.handed;
        carriageSurface = o2RedRealized.host.alpha.surface;
      };
      green = {
        alphaHanded = o2AlphaAdapter.peerRelation.admitted;
        withheldNamed = o2AlphaAdapter.peerRelation.withheld;
        bravoWithheldNamed = o2BravoAdapter.peerRelation.withheld;
      };
      invariantControl = {
        red = o2RedRealized.host.bravo.handed;
        green = o2BravoAdapter.peerRelation.admitted;
      };
    };
    expected = {
      red = {
        alphaHanded = [
          "alpha"
          "bravo"
          "charlie"
        ];
        carriageSurface = [
          "bindings"
          "extent"
          "extraModules"
          "modules"
          "name"
        ];
      };
      green = {
        alphaHanded = [ ];
        withheldNamed = [
          {
            label = "peer";
            marks = [ "isolated" ];
            target = "alpha";
          }
          {
            label = "peer";
            marks = [ "isolated" ];
            target = "bravo";
          }
          {
            label = "peer";
            marks = [ "isolated" ];
            target = "charlie";
          }
        ];
        bravoWithheldNamed = [ ];
      };
      invariantControl = {
        red = [
          "alpha"
          "bravo"
          "charlie"
        ];
        green = [
          "alpha"
          "bravo"
          "charlie"
        ];
      };
    };
  };

  flake.tests.crossing-extent-peer.test-o3-widening-is-unsayable-not-merely-unused = {
    expr = {
      red = {
        alphaReachesCharlie = o3RedRealized.host.alpha ? charlie;
        handedKeys = builtins.attrNames o3RedRealized.host.alpha;
      };
      green = {
        alphaReachesCharlie = o3GreenRealized.host.alpha ? charlie;
        handedKeys = builtins.attrNames o3GreenRealized.host.alpha;
        boundedSurface = builtins.sort builtins.lessThan (builtins.attrNames o3BoundedDirect);
        boundedNodesFieldForIsolatedAlpha = o3BoundedDirect.nodes;
      };
    };
    expected = {
      red = {
        alphaReachesCharlie = true;
        handedKeys = [
          "alpha"
          "bravo"
          "charlie"
        ];
      };
      green = {
        alphaReachesCharlie = false;
        handedKeys = [ ];
        boundedSurface = [
          "labeledEdges"
          "nodes"
          "withheld"
        ];
        boundedNodesFieldForIsolatedAlpha = [
          "alpha"
          "bravo"
          "charlie"
        ];
      };
    };
  };

  flake.tests.crossing-extent-peer.test-o4-spine-reads-force-no-peer-artifact = {
    expr = {
      spineOnly = builtins.tryEval (builtins.attrNames o4Realized.host.alpha);
      positiveControl = builtins.tryEval o4Realized.host.alpha.bravo;
      regression = {
        redSpine = o1RedRealized.host.alpha;
        underEmptyMarks = o4IdentityRealized.host.alpha;
      };
    };
    expected = {
      spineOnly = {
        success = true;
        value = [
          "alpha"
          "bravo"
        ];
      };
      positiveControl = {
        success = false;
        value = false;
      };
      regression = {
        redSpine = [
          "alpha"
          "bravo"
          "charlie"
        ];
        underEmptyMarks = [
          "alpha"
          "bravo"
          "charlie"
        ];
      };
    };
  };

  flake.tests.crossing-extent-peer.test-o6-derived-view-is-named-and-the-name-is-checked = {
    expr = {
      red = {
        handedIsPeerRelationElement =
          (builtins.tryEval (genViewCarrier.elementOf "o6-probe" "handed" "peerRelation" o6RedHanded))
          .success;
        handedElementTag = o6RedHanded.__element or "«no __element»";
      };
      green = {
        handedIsPeerRelationElement =
          (builtins.tryEval (genViewCarrier.elementOf "o6-probe" "handed" "peerRelation" o6GreenHanded))
          .success;
        viewName = o6GreenHanded.name;
        viewSurface = builtins.sort builtins.lessThan (builtins.attrNames o6GreenHanded);
      };
    };
    expected = {
      red = {
        handedIsPeerRelationElement = false;
        handedElementTag = "«no __element»";
      };
      green = {
        handedIsPeerRelationElement = true;
        viewName = "peers/host";
        viewSurface = [
          "__element"
          "admitted"
          "name"
          "withheld"
        ];
      };
    };
  };
}

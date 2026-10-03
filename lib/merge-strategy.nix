# Merge strategy resolution and collision detection.
#
# When a binding name collides with a module-system arg (e.g., both gen-bind
# and evalModules provide `lib`), the merge strategy determines resolution:
# - bind-wins: binding shadows module-system arg (default)
# - system-wins: module-system arg wins, binding dropped
# - error: throw at evaluation time
#
# Academic: Leijen 2005 §2 — scoped labels with duplicate resolution.
# When two scopes provide the same label, resolution follows a strategy:
# first-wins (our "bind-wins" via // ordering), or explicit disambiguation.
# Our "error" strategy mirrors Leijen's strict-extension mode where
# duplicate labels are rejected.
{ prelude }:
let
  provenanceLib = import ./provenance.nix { inherit prelude; };
  applicable = import ./applicable.nix { };

  # The declared policies are one closed set, and every reader of a policy decodes against it here
  # (den-hoag-bvpuo): `decodePolicy refuse v` is `v` when declared, else a refusal, by name and
  # catchably, whose subject `refuse` renders from the value it read — the field the caller wrote.
  policyNames = [
    "bind-wins"
    "system-wins"
    "error"
  ];
  decodePolicy =
    refuse: v:
    if builtins.elem v policyNames then
      v
    else
      throw "${
        refuse (if builtins.isString v then builtins.toJSON v else "a ${builtins.typeOf v}")
      }, not one of ${builtins.concatStringsSep ", " (map builtins.toJSON policyNames)}";

  # ★★★ ADR-0023 (b) — POINTER DECLARATION, PARITY WITH `thunk.nix`'s. The full
  # four-part declaration for the crossing route this validator gets carried
  # into lives at gen-bind `crossing-adapter-set.nix`'s `mkHostedTerminal`
  # collision-class header (write-list entry 1, SITE 2) — that is the SPLICING
  # POINT, where `bindFormals` returns `.all` (`mods ++ vals`) and this
  # validator lands in the target's own module set.
  #
  # (i) THIS VALIDATOR DOES NOT MEET ADR-0023 (c) once spliced: it is a
  # substrate-built lambda placed into a foreign module set.
  # (ii) THE PRICE, stated here as it is stated at the splicing point: a
  # substrate closure — this function — executes inside the target's
  # evaluation whenever a bound name collides with a module-system arg,
  # reading `provenance` and the resolved policy, and it throws on a
  # `_mergeStrategy = "error"` opt-in and on a policy outside the declared three.
  # (iii) THE ARGUED IMPOSSIBILITY is `crossing-adapter-set.nix`'s: closing this
  # would have to move collision detection substrate-side, before any target
  # module set exists — SITE-2's argued impossibility under ADR-0013, not a
  # scope limit on either record. See `crossing-adapter-set.nix`'s SITE-2
  # declaration for the full argument and O-3's measured ground.
  #
  # Academic: Findler 2002 §2.2 — blame assignment at collision detection.
  #
  # `mkMergeValidator { resolvePolicy; boundArgNames; provenance; } moduleArgs` (den-hoag-7gp66 P2,
  # R7 (a)): the module-system args are the subject, last, and the three fields before them — a
  # policy function, a name list and a provenance map — have no order among them, so they stay ONE
  # required-argument record rather than an arbitrary positional order. The record is a
  # `prelude.door` (open, R5): a missing field is refused by name, catchably, when it is applied.
  # `cores.mkMergeValidator` is the unchecked core `wrap.nix` calls.
  mkMergeValidatorCore =
    args:
    let
      inherit (args) boundArgNames provenance;
      # `wrap` hands the core its own lambda, which passes on the builtin alone (den-hoag-k0whn).
      resolvePolicy =
        if builtins.isFunction args.resolvePolicy then
          args.resolvePolicy
        else
          applicable.door "mkMergeValidator" "resolvePolicy" args.resolvePolicy;
    in
    (
      moduleArgs:
      let
        checks = builtins.concatMap (
          name:
          let
            mArgs = moduleArgs.config._module.args or { };
            hasReal =
              (builtins.tryEval (builtins.seq (mArgs.${name} or null) (mArgs ? ${name}))).value or false;
            # `resolvePolicy`'s codomain is the three declared policies: a result outside them is
            # refused by name, where it is read, rather than read as `bind-wins` (den-hoag-d65u4).
            strategy = decodePolicy (
              shown: "gen-bind.mkMergeValidator: `resolvePolicy` returned ${shown} for '${name}'"
            ) (resolvePolicy name);
            prov = provenance.${name} or null;
            provStr =
              let
                s = provenanceLib.format prov;
              in
              if s == "" then "" else " (${s})";
          in
          if !hasReal then
            [ ]
          else if strategy == "error" then
            throw "gen-bind: binding '${name}'${provStr} collides with module-system arg — set mergeStrategy to resolve"
          else if strategy == "system-wins" then
            [
              "gen-bind: binding '${name}'${provStr} collision — system-wins, binding value dropped"
            ]
          else
            [
              "gen-bind: binding '${name}'${provStr} collision — bind-wins, module-system value shadowed"
            ]
        ) boundArgNames;
      in
      # Lazy `config.warnings` — NOT `builtins.seq checks { … }`. The validator is a
      # top-level module in the wrapAll `.all` set (modules ++ validators). evalModules
      # forces every top-level module to WHNF during module *collection* (to read
      # imports/key/_file); an eager `seq checks` would force `config._module.args` at
      # that point, before the config fixpoint exists → infinite recursion. Emitting a
      # bare (config-implicit) `warnings` keeps the module's WHNF free of `checks`, so
      # `config._module.args` is read only when `config.warnings` is demanded (post-fixpoint,
      # the NixOS-idiomatic point). error-strategy still throws — lazily, on `.warnings` access.
      {
        warnings = checks;
      }
    );
in
{
  mergeStrategy = {
    bindWins = "bind-wins";
    systemWins = "system-wins";
    error = "error";

    fromBindings =
      bindings:
      builtins.mapAttrs (
        _: v: if builtins.isAttrs v && v ? _mergeStrategy then v._mergeStrategy else null
      ) bindings;
  };

  mkMergeValidator = prelude.door {
    name = "gen-bind.mkMergeValidator";
    required = [
      "resolvePolicy"
      "boundArgNames"
      "provenance"
    ];
    open = true;
  } mkMergeValidatorCore;
  cores = {
    mkMergeValidator = mkMergeValidatorCore;
    inherit decodePolicy;
  };
}

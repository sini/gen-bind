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
  # `_mergeStrategy = "error"` opt-in, on a policy outside the declared three, and on a
  # `system-wins` collision at a fully-applied module.
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
  # `cores.mkMergeValidator` is the unchecked core `wrap.nix` calls; it also takes `fullyApplied`,
  # which only `wrap` knows and which the published door pins `false`.
  #
  # The hosted module system's value for `name`, read where that system reads a module argument:
  # the call's own args (`specialArgs` and every arg `evalModules` passes itself, `config` included),
  # then `config._module.args` — nixpkgs `lib/modules.nix` `applyModuleArgs`,
  # `args.${name} or config._module.args.${name}`. Presence is membership alone, never a forced
  # value. The validator's collision test and `wrap`'s `system-wins` value both read this one record,
  # so a warning and the value it describes cannot come apart (den-hoag-34i06).
  systemArg =
    moduleArgs: name:
    let
      mArgs = moduleArgs.config._module.args or { };
    in
    if moduleArgs ? ${name} then
      {
        present = true;
        value = moduleArgs.${name};
      }
    else if mArgs ? ${name} then
      {
        present = true;
        value = mArgs.${name};
      }
    else
      { present = false; };

  mkMergeValidatorCore =
    args:
    let
      inherit (args) boundArgNames provenance fullyApplied;
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
            hasReal = (systemArg moduleArgs name).present;
            strategy = resolvePolicy name;
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
          # A fully-applied module was called at wrap time, so no module-system value can reach it:
          # `system-wins` cannot be honoured there, and the collision is refused by name.
          else if strategy == "system-wins" && fullyApplied then
            throw "gen-bind.mkMergeValidator: binding '${name}'${provStr} collides with a module-system arg under system-wins, but the module is fully applied (every formal bound), so the module-system value cannot be served"
          else if strategy == "system-wins" then
            [
              "gen-bind: binding '${name}'${provStr} collision — system-wins, binding value dropped"
            ]
          else if strategy == "bind-wins" then
            [
              "gen-bind: binding '${name}'${provStr} collision — bind-wins, module-system value shadowed"
            ]
          # `resolvePolicy`'s codomain is the three declared policies: a result outside them is
          # refused by name, where it is read, rather than read as `bind-wins` (den-hoag-d65u4).
          else
            throw "gen-bind.mkMergeValidator: `resolvePolicy` returned ${
              if builtins.isString strategy then builtins.toJSON strategy else "a ${builtins.typeOf strategy}"
            } for '${name}', not one of \"bind-wins\", \"system-wins\", \"error\""
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
  } (args: mkMergeValidatorCore (args // { fullyApplied = false; }));
  cores.mkMergeValidator = mkMergeValidatorCore;
  cores.systemArg = systemArg;
}

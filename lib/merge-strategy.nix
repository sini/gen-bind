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

  # Academic: Findler 2002 §2.2 — blame assignment at collision detection.
  mkMergeValidator =
    {
      resolvePolicy,
      boundArgNames,
      provenance,
    }:
    moduleArgs:
    let
      checks = builtins.concatMap (
        name:
        let
          mArgs = moduleArgs.config._module.args or { };
          hasReal =
            (builtins.tryEval (builtins.seq (mArgs.${name} or null) (mArgs ? ${name}))).value or false;
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
    };
}

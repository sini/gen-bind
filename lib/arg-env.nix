# Terminal-crossing arg-environment transforms.
#
# The wrap/thunk pipeline injects bindings BEFORE `evalModules` — it rewrites a module's
# FORMAL parameters. But a reach/delivery edge that crosses a module-system boundary must
# also rewrite the ARG ENVIRONMENT the placed slice resolves against AT the `evalModules`
# boundary (`_module.args` / `specialArgs`), and may gate the slice's resolved CONFIG on an
# eval-time predicate. Content rewriters (gen-edge `adapt`: content → Π → content, applied
# in the pre-eval fold) structurally cannot reach that boundary — they never see
# `_module.args`/`specialArgs`. These three primitives do.
#
# Academic: Cardelli 1997 (Program Fragments, Linking, Modularization) §5. The arg
# environment is the LINKSET a fragment (module) resolves its free names against; adaptArgs
# and crossEval EXTEND that linkset at the crossing (the two module-system channels —
# `_module.args` and `specialArgs`), and crossEval performs the separate-compilation of an
# opaque fragment against a sub-linkset, lifting its resolved config.
#
# nixpkgs-lib-free discipline (Class B): these primitives touch `evalModules`/`mkIf`/`types`
# — but ONLY via a `lib` the TERMINAL threads in at the crossing (adaptArgs/configGate read
# `args.lib`; crossEval takes `lib` as a parameter). gen-bind itself imports no `nixpkgs.lib`.
{ ... }:
let
  # crossEval — separate-compilation of an opaque slice in the TERMINAL's own evaluator.
  #
  # Resolves `module` through a FRESH nested `evalModules` (the terminal's `lib`, threaded in
  # — gen-bind imports no `nixpkgs.lib`), returning the eval RESULT (read `.config`). This is
  # what the `specialArgs` arg-env channel requires: `specialArgs` cannot be set from inside a
  # module, so rewriting it means OWNING the `evalModules` call.
  #
  #   - `specialArgs`   the caller-only arg env, available during imports resolution.
  #   - `moduleArgs`    a config-level `_module.args` env (null ⇒ omit; {} threads an empty env).
  #   - `absorb`        installs a freeform absorber (`types.lazyAttrsOf types.raw`) so an
  #                     OPAQUE slice's config keys land regardless of the terminal type
  #                     universe (nixpkgs / gen-merge). Default true.
  #
  # Laziness: `evalModules` builds config lazily; the RESULT is a WHNF attrset and no slice
  # config value is forced until `.config.<key>` is demanded.
  crossEval =
    {
      lib,
      module,
      specialArgs ? { },
      moduleArgs ? null,
      absorb ? true,
    }:
    lib.evalModules {
      inherit specialArgs;
      modules =
        (if absorb then [ { config._module.freeformType = lib.types.lazyAttrsOf lib.types.raw; } ] else [ ])
        ++ [ module ]
        ++ (if moduleArgs == null then [ ] else [ { config._module.args = moduleArgs; } ]);
    };
in
{
  inherit crossEval;

  # adaptArgs — the `_module.args` sibling-injection channel (in-module, non-nested).
  #
  # Returns a terminal module-FUNCTION fired at the `evalModules` crossing that injects
  # `_module.args = adapt args` — visible to every SIBLING module in the eval — and imports
  # the placed `module`. `adapt : crossingArgs -> attrset` derives the extended arg
  # environment from the terminal args (config/options/pkgs/lib/…) available at the crossing.
  #
  # `_module.args` is the ONLY arg-env channel a module can write from INSIDE the eval;
  # `specialArgs` is caller-only (see crossEval). Laziness: `adapt` and `module` are forced
  # only when the returned function is applied by `evalModules`, never at construction.
  adaptArgs =
    {
      adapt,
      module,
    }:
    args: {
      imports = [ module ];
      _module.args = adapt args;
    };

  # configGate — an eval-time `mkIf` gate over a slice's nested-eval'd CONFIG.
  #
  # Returns a terminal module-FUNCTION that, at the crossing, resolves `module` in a nested
  # `crossEval` (threading `adapt args` as its `_module.args`) and contributes the result via
  # `mkIf (gate args) nested.config`. `gate : crossingArgs -> bool` is the eval-time predicate;
  # it reads the terminal args (config/options/pkgs) available only at the boundary.
  #
  # ★ LOAD-BEARING MODULE-SYSTEM BOUND (den-hoag adversarially proved this).
  #   The gate MUST gate CONFIG (`mkIf`), NEVER `imports`. Gating `imports` on a predicate that
  #   reads `options`/`config` is the fixpoint cycle
  #       imports ← guard(options) ← options ← imports  ⇒  infinite recursion.
  #   `mkIf` gates config while leaving `imports` unconditional, so the outer `options` set is
  #   guard-INDEPENDENT and well-defined. CONSEQUENCE: a config-gate can conditionally SUPPLY
  #   config but CANNOT conditionally DECLARE an option — a gated slice's option declarations
  #   live in the nested eval and never reach the outer option-set. The COMMON case (a slice
  #   contributes config; the guard checks an option declared ELSEWHERE, e.g. a wsl module
  #   declares `wsl`, the guard gates OTHER content on `options ? wsl`) is sound. Conditional
  #   option DECLARATION is unsupported BY CONSTRUCTION — a module-system bound, not a gen-bind
  #   limit. (den-hoag ruling: output-modules Phase-4, argEnvWrap case-3.)
  #
  # Laziness: `gate`, `module`, and `adapt` are forced only when the returned function is
  # applied by `evalModules`.
  configGate =
    {
      gate,
      module,
      adapt ? (_: { }),
      absorb ? true,
    }:
    args: {
      config =
        args.lib.mkIf (gate args)
          (crossEval {
            inherit (args) lib;
            inherit module absorb;
            moduleArgs = adapt args;
          }).config;
    };
}

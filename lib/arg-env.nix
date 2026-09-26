# Terminal-crossing arg-environment transforms.
#
# The wrap/thunk pipeline injects bindings BEFORE `evalModules` — it rewrites a module's
# FORMAL parameters. But a reach/delivery edge that crosses a module-system boundary must
# also rewrite the ARG ENVIRONMENT the placed slice resolves against AT the `evalModules`
# boundary (`_module.args` / `specialArgs`), and may gate the slice's resolved CONFIG on an
# eval-time predicate. Content rewriters (content → content, applied in the pre-eval fold —
# gen-view's `transform.map`, and gen-edge's `adapt` before ADR-0010 §3 retired that library)
# structurally cannot reach that boundary — they never see `_module.args`/`specialArgs`. The
# claim is about the SHAPE of a content-to-content rewriter and holds under any host for it.
# These three primitives do reach it.
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
  #                     OPAQUE slice's config keys land regardless of the terminal's option
  #                     vocabulary. Default true.
  #
  # `lib` here MUST be nixpkgs-shaped: the call two lines down is `lib.evalModules`, and that is
  # the ONLY arm that exists — no other module-merge engine in this ecosystem has ever published
  # an export under that name (only under `evalModuleTree`), so a `lib` bound to one would throw
  # `attribute 'evalModules' missing` rather than run. Reaching nixpkgs' evaluator from here is
  # BRIDGING, not a second engine (ADR-0008 §1: "a foreign module-system fixpoint reached across a
  # boundary is bridging. No exception entry is owed"). A second arm here is unbuilt aspiration,
  # not a regression — nothing in this repo's history ever called one.
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
  # ★★★ ADR-0023 (b) SITE 4 — `configGate` — OFF-CROSSING, UNREACHED.
  #
  # (i) THIS SITE DOES NOT MEET, AND DOES NOT NEED TO: `configGate` evaluates the
  # caller-supplied `adapt` closure inside the nested `crossEval` fixpoint it
  # builds — mechanically the same shape as site 3's closure execution — but no
  # shipped Adapter offers a `bindArgEnv` position for it to be reached through:
  # `injectAdapter`, `mkSystemTerminal` and `mkFlakeTerminal` all set
  # `bindArgEnv = null` (crossing-adapter-set.nix), and no `lib/` binding in this
  # repo calls `configGate` at all — measured, a repo-wide search for callers
  # returns none. It is exported and reachable only by a CALLER building a
  # terminal module directly, off every Adapter.
  #
  # (ii) THE PRICE, STATED CONDITIONALLY BECAUSE IT IS NOT INCURRED THROUGH ANY
  # ADAPTER: were `bindArgEnv` ever wired to this function by an Adapter, a
  # substrate closure — the caller's `adapt`/`gate` pair — would execute inside
  # the target's evaluation (here, inside the nested `crossEval` this function
  # builds), reading whatever `args` the crossing terminal supplies and able to
  # throw anything `adapt`/`gate` throw.
  #
  # (iii) THE ARGUED IMPOSSIBILITY OF NEEDING ONE: there is no crossing route
  # through an Adapter to close, so a by-construction repair is not available to
  # this unit — there is nothing here for `den-hoag-i546n` to fix. Wiring
  # `bindArgEnv` to this function on some future Adapter is a reach widening,
  # out of scope for a record that only prices what already exists.
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

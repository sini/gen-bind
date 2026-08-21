# arg-env — terminal-crossing arg-environment transforms.
#
# adaptArgs / crossEval / configGate cross the `evalModules` boundary that content
# rewriters (gen-view's `transform.map`; gen-edge's `adapt` before ADR-0010 §3 retired that
# library) cannot reach: they rewrite the ARG ENVIRONMENT
# (`_module.args` / `specialArgs`) a placed module slice resolves against, and gate a
# slice's nested-eval'd CONFIG via `mkIf`. `lib` is the REAL nixpkgs lib supplied by the
# test harness — the same shape a terminal threads in as `args.lib` at the crossing.
{ lib, genBind, ... }:
let
  inherit (genBind) adaptArgs crossEval configGate;
in
{
  # ── adaptArgs — `_module.args` sibling injection ────────────────────────────────────
  # The placed slice reads `injected`, an arg that exists ONLY because adaptArgs put it in
  # `_module.args` at the crossing. Driven through a real evalModules.
  flake.tests.arg-env.test-adaptArgs-injects-module-args = {
    expr =
      (lib.evalModules {
        modules = [
          { config._module.freeformType = lib.types.lazyAttrsOf lib.types.raw; }
          (adaptArgs {
            adapt = _args: { injected = "from-adaptArgs"; };
            module =
              { injected, ... }:
              {
                out = injected;
              };
          })
        ];
      }).config.out;
    expected = "from-adaptArgs";
  };

  # adaptArgs' `adapt` receives the crossing ARG ENVIRONMENT and rewrites it: it reads a base
  # crossing arg (`base`, threaded via `specialArgs`, exactly as den's real adaptArgs reads
  # `config`/`pkgs`) and derives a NEW `_module.args` key the slice consumes. Proves the
  # transform is over the boundary arg-env, not static content.
  flake.tests.arg-env.test-adaptArgs-adapt-reads-crossing-args = {
    expr =
      (lib.evalModules {
        specialArgs = {
          base = "hello";
        };
        modules = [
          { config._module.freeformType = lib.types.lazyAttrsOf lib.types.raw; }
          (adaptArgs {
            adapt = args: { derived = "${args.base}-adapted"; };
            module =
              { derived, ... }:
              {
                out = derived;
              };
          })
        ];
      }).config.out;
    expected = "hello-adapted";
  };

  # ── crossEval — nested eval in the terminal's own evaluator, `specialArgs` threading ──
  # The `specialArgs` arg-env channel is CALLER-ONLY (a module cannot set another module's
  # specialArgs) — so rewriting it requires OWNING the evalModules call, which crossEval is.
  # A slice reads `peer` from the threaded specialArgs.
  flake.tests.arg-env.test-crossEval-threads-specialArgs = {
    expr =
      (crossEval {
        inherit lib;
        specialArgs = {
          peer = "peer-val";
        };
        module =
          { peer, ... }:
          {
            out = peer;
          };
      }).config.out;
    expected = "peer-val";
  };

  # crossEval's freeform absorber lets an OPAQUE slice's config keys land regardless of the
  # terminal type universe — the slice declares no options yet its `k` resolves.
  flake.tests.arg-env.test-crossEval-freeform-absorbs-opaque-keys = {
    expr =
      (crossEval {
        inherit lib;
        module = {
          k = "opaque-value";
        };
      }).config.k;
    expected = "opaque-value";
  };

  # crossEval's `moduleArgs` threads a config-level `_module.args` env (the channel
  # configGate uses); a slice reads the threaded arg.
  flake.tests.arg-env.test-crossEval-threads-moduleArgs = {
    expr =
      (crossEval {
        inherit lib;
        moduleArgs = {
          extra = "via-module-args";
        };
        module =
          { extra, ... }:
          {
            out = extra;
          };
      }).config.out;
    expected = "via-module-args";
  };

  # ── configGate — eval-time `mkIf` gate over the nested eval ──────────────────────────
  # NOTE on the OUTER absorber: nixpkgs strips `_module` from the public `.config`, so the
  # NESTED freeform absorber does NOT bleed up — the OUTER terminal must itself hold the
  # gated keys. In den-hoag the outer is the real host (the keys are real options); here the
  # synthetic outer supplies its own freeform absorber. This is faithful crossing behavior.
  #
  # gate TRUE ⇒ the slice's nested-eval'd config is contributed.
  flake.tests.arg-env.test-configGate-true-contributes-config = {
    expr =
      (lib.evalModules {
        modules = [
          { config._module.freeformType = lib.types.lazyAttrsOf lib.types.raw; }
          (configGate {
            gate = _args: true;
            module = {
              out = "gated-content";
            };
          })
        ];
      }).config.out;
    expected = "gated-content";
  };

  # gate FALSE ⇒ `mkIf false` ⇒ NO config contributed ⇒ a DECLARED outer option keeps its
  # DEFAULT (the gated slice's definition is suppressed). Asserting a declared option's
  # default — not freeform key-presence — is the unambiguous suppression probe: under a
  # `lazyAttrsOf` freeform absorber `config ? out` reports the key present even behind
  # `mkIf false` (the key set is unioned before the property is discharged).
  flake.tests.arg-env.test-configGate-false-suppresses-config = {
    expr =
      (lib.evalModules {
        modules = [
          {
            options.gated = lib.mkOption {
              type = lib.types.str;
              default = "DEFAULT";
            };
          }
          (configGate {
            gate = _args: false;
            module = {
              gated = "gated-content";
            };
          })
        ];
      }).config.gated;
    expected = "DEFAULT";
  };

  # configGate threads adaptArgs into the nested eval via `_module.args`: the gated slice
  # reads an arg the gate's `adapt` derived from the crossing args.
  flake.tests.arg-env.test-configGate-adapt-threads-into-nested-eval = {
    expr =
      (lib.evalModules {
        modules = [
          { config._module.freeformType = lib.types.lazyAttrsOf lib.types.raw; }
          (configGate {
            gate = _args: true;
            adapt = _args: { fromAdapt = "adapted-arg"; };
            module =
              { fromAdapt, ... }:
              {
                out = fromAdapt;
              };
          })
        ];
      }).config.out;
    expected = "adapted-arg";
  };

  # ── The LOAD-BEARING module-system bound (den-hoag adversarially proved this) ─────────
  # SOUND COMMON CASE: the guard reads an option DECLARED ELSEWHERE (an outer sibling) and
  # gates OTHER content. `imports` are unconditional, so `options` is guard-independent —
  # no `imports ← guard(options) ← options ← imports` cycle. Guard true ⇒ content lands.
  flake.tests.arg-env.test-configGate-common-case-guard-reads-outer-option = {
    expr =
      (lib.evalModules {
        modules = [
          { config._module.freeformType = lib.types.lazyAttrsOf lib.types.raw; }
          {
            options.marker = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
          }
          (configGate {
            gate = args: args.options ? marker; # eval-time read of the OUTER option-set
            module = {
              fromSlice = "content";
            };
          })
        ];
      }).config.fromSlice;
    expected = "content";
  };

  # THE BOUND: a config-gate gates CONFIG, never option DECLARATION. A gated slice that
  # DECLARES an option keeps that declaration trapped in the NESTED eval — it does NOT
  # reach the outer option-set (its config value still lands via the bled freeform). This
  # is fundamental to the module system: you cannot conditionally declare an option without
  # the import-cycle. Proof: outer `options ? gatedOnly` is false while `config.gatedOnly`
  # is present.
  flake.tests.arg-env.test-configGate-cannot-declare-option-in-outer = {
    expr =
      let
        evaluated = lib.evalModules {
          modules = [
            { config._module.freeformType = lib.types.lazyAttrsOf lib.types.raw; }
            (configGate {
              gate = _args: true;
              module =
                { lib, ... }:
                {
                  options.gatedOnly = lib.mkOption {
                    type = lib.types.str;
                    default = "d";
                  };
                  config.gatedOnly = "v";
                };
            })
          ];
        };
      in
      {
        outerDeclares = evaluated.options ? gatedOnly; # false — declaration trapped in nested
        configLands = evaluated.config.gatedOnly; # "v" — config still contributed
      };
    expected = {
      outerDeclares = false;
      configLands = "v";
    };
  };

  # ── Laziness — the transform CONSTRUCTORS force nothing at wrap time ─────────────────
  # Building the adaptArgs wrapper forces neither `adapt` nor `module`.
  flake.tests.arg-env.test-adaptArgs-lazy-no-force = {
    expr = builtins.isFunction (adaptArgs {
      adapt = throw "adapt forced at wrap time";
      module = throw "module forced at wrap time";
    });
    expected = true;
  };

  # Building the configGate wrapper forces neither `gate`, `module`, nor `adapt`.
  flake.tests.arg-env.test-configGate-lazy-no-force = {
    expr = builtins.isFunction (configGate {
      gate = throw "gate forced at wrap time";
      module = throw "module forced at wrap time";
      adapt = throw "adapt forced at wrap time";
    });
    expected = true;
  };

  # crossEval returns the evalModules result at WHNF without forcing a slice config value.
  flake.tests.arg-env.test-crossEval-lazy-result-not-forced = {
    expr = builtins.isAttrs (crossEval {
      inherit lib;
      module = {
        out = throw "config value forced at wrap time";
      };
    });
    expected = true;
  };
}

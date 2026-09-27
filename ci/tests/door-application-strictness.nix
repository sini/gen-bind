# den-hoag-7gp66 P1 gen-bind lazy-door fix — door APPLICATION strictness, not downstream forcing.
#
# `door-checks.nix` already pins that a bad record is refused SOMEWHERE (often by forcing a
# returned field, e.g. `((adaptArgs { adapt = _: { }; }) { }).imports`); it does not pin WHEN.
# Seven doors admitted a bad record silently at their own APPLICATION — `door bad` returned a
# value (a function or a plain attrset literal) without the return's own WHNF ever forcing
# `checkRequired`/`checkOptions`, so the check fired later only if a caller happened to force one
# of the admitted fields (den-hoag-7gp66 P2 spec finding, `reports/den-hoag-7gp66-p2-spec-v0.md`
# §5). Fixed via `builtins.seq checked` threaded through each door's own return (idiom:
# gen-settings 0474486, gen-inspect 440336c).
#
# `laz door bad` is the P2 spec's own probe: `tryEval (seq (door bad) null)`. `success = true`
# means the door's own application admitted `bad` with no check fired — LAZY. `success = false`
# means the door threw at its own application — STRICT.
{ genBind, ... }:
let
  inherit (genBind)
    adaptArgs
    configGate
    buildSignature
    mkMergeValidator
    wrapIdentity
    crossEval
    ;
  inherit (genBind.contract) mk;
  inherit (genBind.crossing) mkFlakeTerminal mkHostedTerminal;

  laz = door: bad: (builtins.tryEval (builtins.seq (door bad) null)).success;
  strictAtApplication = door: bad: !(laz door bad);
in
{
  flake.tests = {
    door-application-strictness = {
      # ── controls, same predicate, same run ──────────────────────────────────
      # Already strict before this landing (its own top-level `if isAnon then … else …` forces
      # `args.isAnon`, which forces the door's own check) — unaffected by this landing.
      test-control-wrapIdentity-already-strict = {
        expr = strictAtApplication wrapIdentity { };
        expected = true;
      };
      # Already strict before this landing (its return selects `lib.evalModules`, forcing the
      # door's own check to resolve `lib`) — unaffected by this landing.
      test-control-crossEval-already-strict = {
        expr = strictAtApplication crossEval { };
        expected = true;
      };
      # A deliberately-lazy construction, the same shape as the seven doors below (the check sits
      # in a `let`, behind a returned value that never references it) — proves this run's
      # predicate can still see a LAZY door, so the seven `expected = true` cells below are not
      # vacuously true.
      test-control-lazy-construction-reads-lazy = {
        expr =
          let
            door =
              args:
              let
                checked = if args ? a then args else throw "missing a";
              in
              {
                x = 1;
              };
          in
          !(strictAtApplication door { });
        expected = true;
      };

      # ── the seven doors this landing fixed ──────────────────────────────────
      test-adaptArgs-strict-at-application = {
        expr = strictAtApplication adaptArgs { };
        expected = true;
      };
      test-configGate-strict-at-application = {
        expr = strictAtApplication configGate { };
        expected = true;
      };
      test-buildSignature-strict-at-application = {
        expr = strictAtApplication buildSignature { };
        expected = true;
      };
      test-contractMk-strict-at-application = {
        expr = strictAtApplication mk { };
        expected = true;
      };
      test-crossingMkFlakeTerminal-strict-at-application = {
        expr = strictAtApplication mkFlakeTerminal { };
        expected = true;
      };
      test-crossingMkHostedTerminal-strict-at-application = {
        expr = strictAtApplication mkHostedTerminal { };
        expected = true;
      };
      test-mkMergeValidator-strict-at-application = {
        expr = strictAtApplication mkMergeValidator { };
        expected = true;
      };
    };
  };
}

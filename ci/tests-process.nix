# THE PER-PROCESS RUNNER (den-hoag-ien5k G6). Evaluates each cell in `tests-process-cells.nix` in its
# OWN evaluator process and asserts on the exit status, the printed value and the evaluator's thunk
# count — gen-aspects' `ci/tests-process.nix` is the pattern. A count is evidence only for the
# evaluator that computed it, so as `apps.<system>.tests-process` it calls the `nix-instantiate` on
# PATH, and gen-harness's `ci --tests-process` runs it in every column of `evaluators.yml`. Locally:
#   nix develop ./ci --command ci --tests-process
#
# gen-identity is read off gen-scope's own `inputs`, the edge `flake.lock` already records, so the
# plane adds no pin.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      apps.tests-process.program = pkgs.writeShellScriptBin "tests-process" (
        ''
          set -e
          # The tools the body calls, declared rather than ambient — and never an evaluator.
          export PATH=${
            pkgs.lib.makeBinPath [
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.gnused
            ]
          }:$PATH
          export cells=${./tests-process-cells.nix} libSrc=${../lib}
          export genPreludeSrc=${inputs.gen-prelude} genAlgebraSrc=${inputs.gen-algebra}
          export genGraphSrc=${inputs.gen-graph} genScopeSrc=${inputs.gen-scope}
          export genIdentitySrc=${inputs.gen-scope.inputs.gen-identity}
          # A fresh working directory per run (gen-harness `process-plane.nix`).
          TMPDIR=$(mktemp -d) out=$(mktemp)
          export TMPDIR out
          trap 'rm -rf "$TMPDIR" "$out"' EXIT
          cd "$TMPDIR"
          # The evaluator the cells run under, from this process and the binary they call.
          echo "evaluator: $(nix-instantiate --version | sed -n 1p)"
        ''
        + ''
          export NIX_STATE_DIR=$TMPDIR/nix-state NIX_LOG_DIR=$TMPDIR/nix-log
          ran=0
          die() {
            echo "tests-process: FAILED at cell $1: $2" >&2
            exit 1
          }
          # at <arm> <n> <expected value>: runs one cell in its own process with the evaluator's
          # statistics on, and leaves `thunks` set. Statistics that were not written die as COULD NOT
          # MEASURE, never read as a count.
          at() {
            rm -f "$TMPDIR/stats"
            rc=0
            val=$(NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$TMPDIR/stats" \
              nix-instantiate --eval --strict --readonly-mode \
              --argstr arm "$1" \
              --argstr libSrc "$libSrc" \
              --argstr genPreludeSrc "$genPreludeSrc" \
              --argstr genAlgebraSrc "$genAlgebraSrc" \
              --argstr genGraphSrc "$genGraphSrc" \
              --argstr genIdentitySrc "$genIdentitySrc" \
              --argstr genScopeSrc "$genScopeSrc" \
              --argstr n "$2" \
              "$cells" 2> "$TMPDIR/err") || rc=$?
            ran=$((ran + 1))
            [ "$rc" -eq 0 ] || die "$1" "n=$2: expected exit 0, got $rc: $(grep error "$TMPDIR/err" | head -2)"
            [ "$val" = "$3" ] || die "$1" "n=$2: expected $3, got '$val'"
            [ -s "$TMPDIR/stats" ] || die "$1" "n=$2: could not measure, no statistics written"
            thunks=$(sed -n 's/.*"nrThunks": *\([0-9][0-9]*\).*/\1/p' "$TMPDIR/stats")
            [ -n "$thunks" ] || die "$1" "n=$2: could not measure, no nrThunks in the statistics"
          }

          # den-hoag-ien5k G6: a reader with one declared peer pays the class only for building it.
          # One `peer` step reads the reader and its peers, so the lift holds those; a lift over the
          # whole class reads 6 thunks per node (measured on all three evaluators).
          at peers 16 1; p16=$thunks
          at peers 64 1; p64=$thunks
          at floor 16 16; f16=$thunks
          at floor 64 64; f64=$thunks
          s=$(((p64 - p16) - (f64 - f16)))
          echo "peer-read-slope: $s thunks above the class's own cost from 16 to 64 nodes ($p16 / $p64 read, $f16 / $f64 floor)"
          [ "$((f64 - f16))" -gt 0 ] || die peer-read-slope "could not measure: the class costs nothing to build ($f16 / $f64)"
          [ "$s" -le 0 ] || die peer-read-slope "the peer read grows with the class: $s thunks from 16 to 64 nodes"

          # 0/0 is a false pass: the runner must have executed every evaluation above.
          [ "$ran" = "4" ] || die runner "expected 4 evaluations, ran $ran"
          echo "tests-process: 1 cell, every exit read unpiped, every count read" > $out
        ''
        + ''
          cat "$out"
        ''
      );
    };
}

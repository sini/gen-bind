# Purity invariant (gen-prelude design §5): gen-bind depends only on gen-prelude and
# must import NO `nixpkgs.lib`. This pins "pure" as a checked property, not an
# aspiration — a stray `lib.foo` / `lib.types` / `evalModules` / nixpkgs input creeping
# back into the library source fails CI.
#
# Scope: lib/**.nix + the root flake.nix (the library + its flake). NOT ci/ — the
# test harness legitimately uses nixpkgs.lib (including, here, to do this scan).
{ genPrelude, lib, ... }:
let
  libDir = ../../lib;

  # Comment-stripped source: drop everything from the first `#` on each line. Safe here
  # because `#` appears only in comments across these files (no `#` in string literals);
  # documentation may freely mention forbidden tokens (e.g. the vendored helpers' nixpkgs
  # provenance) without tripping the invariant.
  stripComments =
    text:
    lib.concatStringsSep "\n" (
      map (line: lib.head (lib.splitString "#" line)) (lib.splitString "\n" text)
    );

  # ★ THE STRIP'S PREMISE, asserted rather than assumed. `stripComments` cuts each line at a comment
  # marker, and that cut is sound only while the `#` it cuts at stands OUTSIDE a string literal.
  # Where it does not, live code is truncated to the end of that line and every cell below goes
  # blind on what was removed, with no signal at all — a green suite over source nothing scanned.
  #
  # The predicate asks the strip ITSELF where it cut: `stripComments` of a single line is exactly
  # the text before that line's cut. It then asks whether that text closed every double quote it
  # opened, an odd count meaning the cut stands inside a string. Deriving it from `stripComments`
  # rather than restating the cut rule is what keeps premise and strip from drifting apart when one
  # of them is edited, and it is why one block serves both strip families in this ecosystem.
  #
  # It is LINE-LOCAL and so cannot conclude about string content that spans lines — an indented
  # multi-line string block. Those files are declared as a list of their own by
  # `test-strip-premise-multiline-strings` rather than trusted in silence.
  countQuotes = s: (lib.length (lib.splitString "\"" s)) - 1;
  cutIsInString =
    line:
    let
      kept = stripComments line;
    in
    kept != line && lib.mod (countQuotes kept) 2 == 1;

  # premiseBreaches : [ { name; text; } ] -> [ "file:line" ]. A breach is reported at its line as
  # well as its file, because what it says is that one particular line's code was truncated.
  premiseBreaches =
    srcs:
    lib.concatMap (
      src:
      lib.concatLists (
        lib.imap1 (i: line: lib.optional (cutIsInString line) "${src.name}:${toString i}") (
          lib.splitString "\n" src.text
        )
      )
    ) srcs;

  # ★ THE WALK DESCENDS, AND CARRIES ITS PREFIX. A flat `readDir` sees `lib/` one level deep, so a
  # file added under a new subdirectory leaves the invariant SILENTLY — the scan reports clean over a
  # tree it no longer covers, which is the failure this scope is written to exclude rather than to
  # survive. `lib/` is flat today, so the invariant cell exercises the recursive branch not at all;
  # `test-walk-descends-into-subdirectories` is what holds it.
  #
  # Labels are repo-root-relative paths, never bare basenames: `lib/default.nix` and the root
  # `default.nix` are both in scope and a bare basename names them with the same string, so a red CI
  # would name a file the reader cannot open. The walk therefore carries a prefix down from the root
  # it was handed.
  walk =
    prefix: dir:
    lib.concatLists (
      lib.mapAttrsToList (
        entry: type:
        if type == "directory" then
          walk "${prefix}${entry}/" (dir + "/${entry}")
        else if lib.hasSuffix ".nix" entry then
          [
            {
              name = "${prefix}${entry}";
              path = dir + "/${entry}";
            }
          ]
        else
          [ ]
      ) (builtins.readDir dir)
    );

  # ★ THE READ AND THE STRIP ARE SEPARATE STAGES, one `readFile` per file feeding both. The premise
  # cell has to speak about the RAW text, which is only a value once the strip stops happening inside
  # the read; and `sources` is then a total per-element function of `rawSources` — the name passes
  # through, the code is the strip of the text — so pinning either one pins the other, and the cells
  # over each COMPOSE instead of hoping two independent reads of the same tree agree.
  raw =
    entries:
    map (e: {
      inherit (e) name;
      text = builtins.readFile e.path;
    }) entries;

  strip =
    entries:
    map (e: {
      inherit (e) name;
      code = stripComments e.text;
    }) entries;

  libEntries = walk "lib/" libDir;

  rawSources = raw libEntries ++ [
    {
      name = "flake.nix";
      text = builtins.readFile ../../flake.nix;
    }
    {
      name = "default.nix";
      text = builtins.readFile ../../default.nix;
    }
  ];

  sources = strip rawSources;

  # Tokens that signal a nixpkgs-lib tether or the module-system (Korora-class) tier.
  forbidden = [
    "nixpkgs" # a nixpkgs flake input / reference
    "lib." # any nixpkgs lib call (lib.types, lib.genAttrs, lib.setFunctionArgs, …)
    "{ lib }" # the old `{ lib }` parameter signature
    "{ lib," # `{ lib, … }` parameter signature
    "evalModules" # module-system tier
    "mkOption" # module-system tier
  ];

  # arg-env.nix is the ONE module-system-OPERATING file: `crossEval`/`configGate` drive a
  # NESTED `evalModules` and call `mkIf`/`types` at the terminal crossing — but ONLY via a
  # `lib` THREADED IN at runtime (crossEval's `lib` parameter; the module functions'
  # `args.lib`), NEVER an imported `nixpkgs.lib`. Its file signature is `{ ... }:` and the lib
  # is wired as `import ./arg-env.nix { }` (no lib passed at the file boundary), so it CANNOT
  # receive nixpkgs at import — structurally lib-import-free.
  #
  # The exemption whitelists EXACTLY the two tokens this file legitimately uses — `lib.` (the
  # threaded lib's members) and `evalModules` (the nested eval). Every OTHER forbidden token
  # stays banned even here, deliberately:
  #   - `{ lib }` / `{ lib,` — a file-sig change to `{ lib, ... }:` (which nixfmt renders
  #     single-line, matching `{ lib,`) would inject nixpkgs.lib as a DEPENDENCY yet still
  #     ride the `lib.`/`evalModules` exemption. Keeping the sig tokens banned closes that
  #     latent regression: the lib must stay RUNTIME-THREADED, never a file parameter.
  #   - `mkOption` — this file EVALUATES modules; it must never DECLARE options.
  #   - `nixpkgs` — P1 (no-nixpkgs-dependency) stays global, unconditionally.
  # So "no nixpkgs DEPENDENCY" holds for every file; only "never operates the module system"
  # is relaxed, for THIS one crossing file, BY DESIGN (gen-bind G4 charter — see README).
  moduleSystemOperators = [ "lib/arg-env.nix" ];
  argEnvExempt = [
    "lib."
    "evalModules"
  ];
  forbiddenFor =
    name:
    if lib.elem name moduleSystemOperators then
      lib.filter (tok: !(lib.elem tok argEnvExempt)) forbidden
    else
      forbidden;

  scan =
    srcs:
    lib.concatMap (
      src:
      map (tok: "${src.name}: '${tok}'") (
        lib.filter (tok: genPrelude.hasInfix tok src.code) (forbiddenFor src.name)
      )
    ) srcs;

  violations = scan sources;

  # The stripped code of one scanned file, by its repo-root-relative label. `lib.head` of an empty
  # filter aborts, so a subject that has lost the file arrives as a red rather than as a silent [ ].
  codeOf = name: (lib.head (lib.filter (s: s.name == name) sources)).code;

  # A file's SIGNATURE is its first line of code — the parameters it can be applied to. Taken from
  # the stripped text so the 21 lines of header above `arg-env.nix`'s signature do not stand in for
  # it, and compared as a whole line rather than as an infix, because `{ ... }:` occurring SOMEWHERE
  # in a file says nothing about what that file takes.
  signatureOf =
    name:
    lib.head (
      lib.filter (l: lib.stringLength (lib.replaceStrings [ " " ] [ "" ] l) > 0) (
        lib.splitString "\n" (codeOf name)
      )
    );
in
{
  flake.tests.purity.test-library-source-is-nixpkgs-lib-free = {
    expr = violations;
    expected = [ ];
  };
  # THE WALK DESCENDS, AND CARRIES ITS PREFIX. lib/ is flat today, so the invariant cell exercises
  # the recursive branch not at all and would keep passing if the walk quietly flattened — which is
  # precisely the state this replaced. The fixture tree is nested on purpose and carries a planted
  # tether at each of its two depths; handing the walk a non-empty prefix pins both halves of the
  # naming rule, that the given prefix is threaded through and that a subdirectory's prefix extends
  # it rather than replacing it.
  flake.tests.purity.test-walk-descends-into-subdirectories = {
    expr = scan (strip (raw (walk "ci/tests/_fixtures/purity-walk/" ./_fixtures/purity-walk)));
    expected = [
      "ci/tests/_fixtures/purity-walk/nested/tethered.nix: 'lib.'"
      "ci/tests/_fixtures/purity-walk/surface.nix: 'mkOption'"
    ];
  };

  # ★ THE PREMISE THE `arg-env.nix` EXEMPTION RESTS ON, WRITTEN DOWN. The header argues that the one
  # module-system-operating file cannot receive a nixpkgs `lib` at import — its file signature takes
  # no parameters and its one call site passes none — and that is what makes relaxing `lib.` and
  # `evalModules` for it safe rather than a hole. Until now the argument was held by a comment.
  #
  # The `{ lib }` / `{ lib,` bans do NOT close it, and the demonstration sits in this repository:
  # nixfmt renders a multi-argument attribute set MULTI-LINE, so a signature changed to
  # `{ lib, ... }:` and then formatted matches no contiguous `{ lib,` and passes every token cell
  # here. A ban whose pattern the repo's own formatter dissolves is not a ban; the signature and the
  # call site are therefore stated directly, as whole lines a reader can diff.
  #
  # Both halves ride in one expectation because they are one property: a signature that takes a lib
  # with no caller passing one is dead, and a caller passing one to a signature that refuses it is a
  # type error — it is the PAIR that makes the import boundary lib-free.
  flake.tests.purity.test-arg-env-takes-no-lib-at-its-import-boundary = {
    expr = {
      signature = signatureOf "lib/arg-env.nix";
      callSites = lib.filter (l: genPrelude.hasInfix "arg-env.nix" l) (
        lib.splitString "\n" (codeOf "lib/default.nix")
      );
    };
    expected = {
      signature = "{ ... }:";
      callSites = [ "  argEnvLib = import ./arg-env.nix { };" ];
    };
  };

  # ★ THE PREMISE HOLDS OF THE TEXT THAT WAS ACTUALLY SCANNED. This is an absence claim over text
  # read from disk and it is NOT non-vacuous on its own: its expectation is `[ ]`, which an emptied
  # or constant subject satisfies exactly as a sound corpus does — a scan of nothing breaches no
  # premise. What arms it is the subject-pinning asserted over this same `rawSources` read, together
  # with the live control below for the predicate itself; green here means the premise holds of the
  # text those cells pin, and nothing more.
  flake.tests.purity.test-strip-premise-holds = {
    expr = premiseBreaches rawSources;
    expected = [ ];
  };

  # And the predicate is capable of saying no. Its subject is a literal written inside this cell
  # rather than anything on disk, so it is UNSEVERABLE from the tree and establishes exactly that the
  # test discriminates an in-string `#` from an ordinary trailing comment — it says nothing whatever
  # about what the cell above was pointed at, and it is NOT that cell's arming. Both directions ride
  # in one expectation: line 1 must be caught and line 2 must not, so a predicate stuck at either
  # constant reds here. The literal cuts under BOTH strip families in this ecosystem — its `#` is
  # whitespace-preceded, so a comment-start strip cuts there too and the control cannot go dead by
  # being pasted into a repository whose strip is the other one.
  flake.tests.purity.test-strip-premise-scan-is-live = {
    expr = premiseBreaches [
      {
        name = "<in-string-hash>";
        text = ''
          url = "a b # c";
          x = 1; # an ordinary trailing comment
        '';
      }
    ];
    expected = [ "<in-string-hash>:1" ];
  };

  # The declared surface: the files the line-local predicate cannot conclude about. An indented
  # multi-line string block carries string content across line boundaries, where a per-line quote
  # count cannot follow it, so those files are written down rather than trusted in silence. The first
  # file to grow one arrives as a red that has to be READ, exactly as a new library file arrives as a
  # red on a membership manifest.
  flake.tests.purity.test-strip-premise-multiline-strings = {
    expr = map (s: s.name) (lib.filter (s: genPrelude.hasInfix "''" s.text) rawSources);
    expected = [ ];
  };
}

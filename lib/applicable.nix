# What Nix can apply (den-hoag-k0whn): the door of every intake that APPLIES a caller's value and
# never reads its formals. (A site that reads formals uses nixpkgs' one-level `isFunction` domain
# instead: `wrap.nix`, `signature.nix`, `thunk.nix`, den-hoag-k5ohf.)
#
# Nix calls a function directly, and calls a set carrying `__functor` by pushing the set itself
# and calling its `__functor` (`callFunction`'s functor arm): `f x` is `(f.__functor f) x`, and
# `__functor` may itself be such a set. The machine is gen-prelude's `applicability`
# (den-hoag-b6nyh), one definition for the roster: it answers true when Nix's call reaches a function
# with nothing left to push, false when Nix would call a non-function or a pattern that cannot bind
# the pushed set, and null when no answer comes within `applicableLevels` `__functor` steps.
# Applicability is only semi-decidable (a `__functor` may return its own set forever, and Nix's call
# then overflows the stack), so the walk is fuelled, and an exhausted walk is refused: a door that
# answers is total. Evaluating `f.__functor f` runs the caller's code; what that code throws, the
# door throws.
{ prelude }:
let
  # Read from gen-prelude, so the text below cannot drift from the walk's bound.
  levels = prelude.applicableLevels;
  verdict = f: (prelude.applicability f).verdict;
  describe =
    r: f:
    if r == null then
      "a functor that reaches no function within ${toString levels} `__functor` steps"
    else if builtins.isAttrs f && f ? __functor then
      "a functor that does not reach a function"
    else
      "a ${builtins.typeOf f}";
in
{
  inherit verdict describe;
  # `f` itself, or a named refusal. A caller on a per-application path tests `builtins.isFunction`
  # inline first, so a plain function costs no call.
  door =
    site: field: f:
    let
      r = verdict f;
    in
    if r == true then
      f
    else
      throw "gen-bind.${site}: `${field}` must be a function, or a functor whose `__functor` reaches one, not ${describe r f}";
}

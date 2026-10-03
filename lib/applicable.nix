# What Nix can apply (den-hoag-k0whn): the door of every intake that APPLIES a caller's value and
# never reads its formals. (A site that reads formals uses nixpkgs' one-level `isFunction` domain
# instead: `wrap.nix`, `signature.nix`, `thunk.nix`, den-hoag-k5ohf.)
#
# Nix calls a function directly, and calls a set carrying `__functor` by pushing the set itself
# and calling its `__functor` (`callFunction`'s functor arm): `f x` is `(f.__functor f) x`, and
# `__functor` may itself be such a set. `verdict` runs that machine for one unknown argument,
# `known` holding the arguments already pushed. It answers true when the head is a function with
# nothing left to push, false when Nix would call a non-function, and null when no answer comes
# within `levels` `__functor` steps. Applicability is only semi-decidable (a `__functor` may
# return its own set forever, and Nix's call then overflows the stack), so the walk is fuelled,
# and an exhausted walk is refused: a door that answers is total. Evaluating `f.__functor f` runs
# the caller's code; what that code throws, the door throws.
{ }:
let
  levels = 32;
  walk =
    fuel: h: known:
    if builtins.isFunction h then
      if known == [ ] then true else walk fuel (h (builtins.head known)) (builtins.tail known)
    else if builtins.isAttrs h && h ? __functor then
      if fuel == 0 then null else walk (fuel - 1) h.__functor ([ h ] ++ known)
    else
      false;
  verdict = f: walk levels f [ ];
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

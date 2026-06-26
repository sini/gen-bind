# Module-convention helpers — vendored byte-for-byte from nixpkgs `lib`.
#
# These set the *convention attributes* a downstream `evalModules` reads:
#   - setFunctionArgs stamps `__functor`/`__functionArgs` so nixpkgs'
#     `lib.functionArgs` (f: if f ? __functor then f.__functionArgs or ... else ...)
#     reports the wrapper's residual interface.
#   - setDefaultModuleLocation stamps `_file` so an anonymous module's declarations
#     are attributed to a stable location.
#
# gen-bind is module-system-*aware*, not module-system-*dependent*: it speaks this
# convention to emit modules a real `evalModules` consumes, but owns the ~6 LOC rather
# than importing `nixpkgs.lib`. Kept gen-bind-local (not in gen-prelude) — they are
# gen-bind-only and module-convention-specific; a general util lib should not know about
# `__functionArgs`/`_file`. Production-safety is gated by the evalModules equivalence
# suite (ci/tests/evalmodules-equivalence.nix).
#
# Provenance: copied verbatim from nixpkgs `lib/trivial.nix` (setFunctionArgs) and
# `lib/modules.nix` (setDefaultModuleLocation). Do not reimplement from memory — the
# `__functor`/`__functionArgs`/`_file` shapes must match exactly what nixpkgs' module
# probe expects.
{ ... }:
{
  setFunctionArgs = f: args: {
    # TODO: Should we add call-time "type" checking like built in?
    __functor = self: f;
    __functionArgs = args;
  };

  setDefaultModuleLocation = file: m: {
    _file = file;
    imports = [ m ];
  };
}

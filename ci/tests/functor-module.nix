# A FUNCTOR MODULE IS A FUNCTION MODULE (den-hoag-k5ohf). nixpkgs reads a module with `lib.isFunction`
# and `lib.functionArgs`, which see through `__functor`: a `setFunctionArgs` wrapper publishes its
# formals as `__functionArgs`, and a functor without them is read through `__functor`. `wrap` binds
# into such a module exactly as into the equivalent lambda, and the wrapped module evaluates under a
# REAL `lib.evalModules` to the value nixpkgs serves the unwrapped module from `_module.args`. A functor
# whose `__functor` yields a non-function is not a function to nixpkgs, and stays a passthrough.
{ lib, genBind, ... }:
let
  inherit (genBind) wrap stripBindingArgs;

  onArg = { myArg, config, ... }: { config.x = myArg; };
  onArgOnly = { myArg }: { config.x = myArg; };
  published = f: lib.setFunctionArgs (args: f args) (builtins.functionArgs f);
  unpublished = f: { __functor = _: f; };

  bind = wrap { bindings.myArg = "bound"; };
  opt = {
    options.x = lib.mkOption { type = lib.types.str; };
  };
  evalX = mods: (lib.evalModules { modules = [ opt ] ++ mods; }).config.x;
  wrappedX = m: evalX [ (bind m).module ];
  # nixpkgs' own answer on the unwrapped module, `myArg` served from `_module.args`.
  servedX =
    m:
    evalX [
      m
      { config._module.args.myArg = "bound"; }
    ];
  names = builtins.attrNames;
in
{
  flake.tests.functor-module = {
    test-a-published-functor-is-wrapped-as-its-lambda = {
      expr = map (m: (bind m).wrapped) [
        onArg
        (published onArg)
        (unpublished onArg)
      ];
      expected = [
        true
        true
        true
      ];
    };

    test-a-wrapped-published-functor-evaluates-to-the-nixpkgs-value = {
      expr = wrappedX (published onArg);
      expected = servedX (published onArg);
    };

    test-a-wrapped-unpublished-functor-evaluates-to-the-nixpkgs-value = {
      expr = wrappedX (unpublished onArg);
      expected = servedX (unpublished onArg);
    };

    test-a-fully-bound-functor-is-applied-as-its-lambda = {
      expr = wrappedX (published onArgOnly);
      expected = wrappedX onArgOnly;
    };

    # gen-bind's own partial-application output is a `setFunctionArgs` functor: a second `wrap`
    # binds into it.
    test-wrap-binds-into-its-own-partial-output = {
      expr = wrappedX (
        (wrap { bindings.a = "A"; } (
          {
            a,
            myArg,
            config,
            ...
          }:
          {
            config.x = a + myArg;
          }
        )).module
      );
      expected = "Abound";
    };

    test-an-imported-functor-is-wrapped = {
      expr = (bind { imports = [ (published onArg) ]; }).wrapped;
      expected = true;
    };

    test-the-signature-reads-a-functor-formals = {
      expr =
        let
          s = (bind (published onArg)).signature;
        in
        {
          requires = names s.requires;
          bound = names s.bound;
        };
      expected = {
        requires = [ "config" ];
        bound = [ "myArg" ];
      };
    };

    test-strip-reads-an-unpublished-functor-formals = {
      expr = names (lib.functionArgs (stripBindingArgs [ "myArg" ] (unpublished onArg)));
      expected = [ "config" ];
    };

    # gen-merge's `pureModule` shape is a functor without `__functionArgs`. Binding into it yields
    # gen-bind's own output, which drops the `__pureModule` marker: a binding may be fixpoint-derived,
    # so the bound module is not certified pure.
    test-a-pure-module-is-bound-and-loses-its-marker =
      let
        r = bind {
          __pureModule = true;
          __functor = _self: onArg;
        };
      in
      {
        expr = r.wrapped && !(r.module ? __pureModule);
        expected = true;
      };

    # Controls: unchanged by this unit.
    test-a-functor-yielding-an-attrset-stays-a-passthrough = {
      expr = [
        (lib.isFunction { __functor = _: { config.x = "h"; }; })
        (bind { __functor = _: { config.x = "h"; }; }).wrapped
      ];
      expected = [
        false
        false
      ];
    };

    test-the-lambda-evaluates-to-the-nixpkgs-value = {
      expr = wrappedX onArg;
      expected = servedX onArg;
    };
  };
}

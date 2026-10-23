{ lib, genBind, ... }:
let
  den =
    name: _:
    "den: class module arg '${name}' collides with module-system arg — set collisionPolicy to resolve";
  warningsOption.options.warnings = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
  };
  hosted = { lib, other, ... }: { };
  warningsOf =
    modules:
    (lib.evalModules {
      modules = modules ++ [ warningsOption ];
      specialArgs.other = 1;
    }).config.warnings;
  viaWrap =
    opts:
    let
      w = genBind.wrap (
        {
          bindings.lib = "bound";
          defaultMergeStrategy = "error";
        }
        // opts
      ) hosted;
    in
    warningsOf [
      w.module
      w.validator
    ];
  viaWrapAll =
    opts:
    let
      w = genBind.wrapAll (
        {
          bindings.lib = "bound";
          defaultMergeStrategy = "error";
        }
        // opts
      ) [ hosted ];
    in
    warningsOf w.all;
  refused = msg: {
    type = "ThrownError";
    inherit msg;
  };
in
{
  # G1: a caller's `refusal` is the text the error policy throws.
  flake.testsError.refusal = {
    test-G1-caller-text-is-thrown = {
      expr = viaWrap { refusal = den; };
      expectedError = refused "^den: class module arg 'lib' collides with module-system arg — set collisionPolicy to resolve$";
    };
    test-G1-caller-text-is-thrown-by-wrapAll = {
      expr = viaWrapAll { refusal = den; };
      expectedError = refused "^den: class module arg 'lib' collides with module-system arg — set collisionPolicy to resolve$";
    };
    # G2: a refusal that is not usable is refused by name, naming the door the caller invoked.
    test-G2-non-string-result-wrap = {
      expr = viaWrap { refusal = _: _: 1; };
      expectedError = refused "^gen-bind[.]wrap: `refusal` returned a int for 'lib', not a string$";
    };
    test-G2-non-string-result-wrapAll = {
      expr = viaWrapAll { refusal = _: _: 1; };
      expectedError = refused "^gen-bind[.]wrapAll: `refusal` returned a int for 'lib', not a string$";
    };
    test-G2-non-function = {
      expr = viaWrap { refusal = 1; };
      expectedError = refused "^gen-bind[.]wrap: `refusal` must be a function, or a functor whose `__functor` reaches one, not a int$";
    };
    # C1: one operand where two are needed is the named refusal, not Nix's "not a function".
    test-G2-one-operand-refusal = {
      expr = viaWrap { refusal = name: "one operand for ${name}"; };
      expectedError = refused "^gen-bind[.]wrap: `refusal` must take the binding's name, then its provenance, and return a string; applied to 'lib' it returned a string, not a function$";
    };
    # G3: no `refusal` ⇒ gen-bind's own text.
    test-G3-default-text = {
      expr = viaWrap { };
      expectedError = refused "^gen-bind: binding 'lib' collides with module-system arg — set mergeStrategy to resolve$";
    };
  };

  # G3: a `refusal` leaves the warnings alone.
  flake.tests.refusal.test-G3-warnings-keep-gen-bind-text = {
    expr = viaWrap {
      refusal = den;
      defaultMergeStrategy = "bind-wins";
    };
    expected = [ "gen-bind: binding 'lib' collision — bind-wins, module-system value shadowed" ];
  };
}

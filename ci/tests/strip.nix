{ lib, bindLib, ... }:
let
  inherit (bindLib) stripBindingArgs;
in
{

  flake.tests.strip.test-strips-from-functionArgs-attr = {
    expr =
      let
        mod = {
          __functionArgs = {
            host = false;
            config = true;
            lib = true;
          };
          __functor = _: _: { };
        };
        stripped = stripBindingArgs {
          module = mod;
          bindingNames = [ "host" ];
        };
      in
      stripped.__functionArgs;
    expected = {
      config = true;
      lib = true;
    };
  };

  flake.tests.strip.test-strips-from-raw-function = {
    # lib.setFunctionArgs returns a wrapped attrset; check __functionArgs directly
    expr =
      let
        mod =
          {
            host,
            config,
            lib,
            ...
          }:
          { };
        stripped = stripBindingArgs {
          module = mod;
          bindingNames = [ "host" ];
        };
      in
      stripped.__functionArgs;
    expected = {
      config = false;
      lib = false;
    };
  };

  flake.tests.strip.test-noop-when-nothing-to-strip = {
    # nothing to strip: raw function returned unchanged; required args are false
    expr =
      let
        mod = { config, lib, ... }: { };
        stripped = stripBindingArgs {
          module = mod;
          bindingNames = [ "host" ];
        };
      in
      builtins.functionArgs stripped;
    expected = {
      config = false;
      lib = false;
    };
  };

  flake.tests.strip.test-noop-for-attrset = {
    expr =
      let
        mod = {
          services.nginx.enable = true;
        };
        stripped = stripBindingArgs {
          module = mod;
          bindingNames = [ "host" ];
        };
      in
      mod == stripped;
    expected = true;
  };
}

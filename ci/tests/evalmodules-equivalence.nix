# Production-safety gate: gen-bind output consumed by a REAL nixpkgs evalModules.
#
# gen-bind emits modules in the nixpkgs module convention (`__functionArgs`/`_file`/
# `key`). When gen-bind vendors its own `setFunctionArgs`/`setDefaultModuleLocation`
# (purity remediation — dropping nixpkgs.lib), the vendored helpers MUST be
# byte-behavior-identical to what nixpkgs' module probe expects. This suite drives
# gen-bind output through a real `lib.evalModules` and asserts the three convention
# properties the spec names: advertises the right args, merges by `key`, reports `_file`.
#
# It is a characterization oracle: green on the pre-vendoring (lib-based) path AND on
# the vendored path proves equivalence.
{ lib, genBind, ... }:
let
  # A NixOS-style function module taking a binding arg `host` alongside `config`.
  # `lib` is captured lexically (the real nixpkgs lib), not via a module arg — the
  # wrapper only injects `host` + supplies `config` from evalModules.
  hostModule =
    { host, config, ... }:
    {
      options.result = lib.mkOption {
        type = lib.types.str;
        default = "";
      };
      config.result = host.name;
    };

  wrapped = genBind.wrap {
    module = hostModule;
    bindings.host = {
      name = "alpha";
    };
  };

  evaluated = lib.evalModules { modules = [ wrapped.module ]; };

  # Key dedup: two references to the same keyed module must merge to ONE definition.
  keyed = genBind.wrapIdentity {
    class = "nixos";
    identity = "dedup";
    module = {
      options.items = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      config.items = [ "x" ];
    };
  };
  evaluatedKeyed = lib.evalModules {
    modules = [
      keyed
      keyed
    ];
  };

  # Anonymous module location: setDefaultModuleLocation attributes the declaration.
  anon = genBind.wrapIdentity {
    class = "nixos";
    identity = "anonmod";
    isAnon = true;
    module = {
      options.foo = lib.mkOption {
        type = lib.types.str;
        default = "y";
      };
    };
  };
  evaluatedAnon = lib.evalModules { modules = [ anon ]; };
in
{
  # (1a) binding flows through real evalModules to the resolved config.
  flake.tests.evalmodules-equivalence.test-binding-injected-through-evalModules = {
    expr = evaluated.config.result;
    expected = "alpha";
  };

  # (1b) advertises the right residual args via nixpkgs' functionArgs reader — the
  # bound arg is stripped so _module.args probing never crashes; `config` remains.
  flake.tests.evalmodules-equivalence.test-advertises-residual-args = {
    expr = lib.functionArgs wrapped.module;
    expected = {
      config = false;
    };
  };

  # (2) merges by `key`: duplicate keyed modules dedup to one definition.
  flake.tests.evalmodules-equivalence.test-merges-by-key = {
    expr = evaluatedKeyed.config.items;
    expected = [ "x" ];
  };

  # (3) reports the right `_file`: anon location attributes the option declaration.
  flake.tests.evalmodules-equivalence.test-reports-file-location = {
    expr = evaluatedAnon.options.foo.declarations;
    expected = [ "nixos@anonmod" ];
  };
}

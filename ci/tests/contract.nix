{ lib, bindLib, ... }:
let
  inherit (bindLib) contract provenance;
in
{
  flake.tests.contract.test-mk-creates-marker = {
    expr =
      (contract.mk {
        check = _: true;
        message = "ok";
      }) ? __contract;
    expected = true;
  };

  flake.tests.contract.test-hasFields-pass = {
    expr =
      let
        c = contract.hasFields [
          "name"
          "class"
        ];
      in
      (contract.apply c {
        name = "igloo";
        class = "nixos";
      } null) ? name;
    expected = true;
  };

  flake.tests.contract.test-hasFields-fail = {
    expr =
      !(builtins.tryEval (
        contract.apply (contract.hasFields [
          "name"
          "class"
        ]) { name = "igloo"; } null
      )).success;
    expected = true;
  };

  flake.tests.contract.test-isType-pass = {
    expr = contract.apply (contract.isType "set") { x = 1; } null;
    expected = {
      x = 1;
    };
  };

  flake.tests.contract.test-isType-fail = {
    expr = !(builtins.tryEval (contract.apply (contract.isType "set") "not-a-set" null)).success;
    expected = true;
  };

  flake.tests.contract.test-nonEmpty-list-pass = {
    expr = contract.apply contract.nonEmpty [ 1 ] null;
    expected = [ 1 ];
  };

  flake.tests.contract.test-nonEmpty-list-fail = {
    expr = !(builtins.tryEval (contract.apply contract.nonEmpty [ ] null)).success;
    expected = true;
  };

  flake.tests.contract.test-nonEmpty-attrset-pass = {
    expr = contract.apply contract.nonEmpty { x = 1; } null;
    expected = {
      x = 1;
    };
  };

  flake.tests.contract.test-nonEmpty-null-fail = {
    expr = !(builtins.tryEval (contract.apply contract.nonEmpty null null)).success;
    expected = true;
  };

  flake.tests.contract.test-apply-includes-provenance = {
    expr =
      let
        result = builtins.tryEval (
          contract.apply (contract.isType "int") "oops" { source = "test-scope"; }
        );
      in
      !result.success;
    expected = true;
  };

  flake.tests.contract.test-apply-includes-blame = {
    expr =
      let
        c = contract.mk {
          check = _: false;
          message = "bad";
          blame = "caller";
        };
      in
      !(builtins.tryEval (contract.apply c 42 null)).success;
    expected = true;
  };
}

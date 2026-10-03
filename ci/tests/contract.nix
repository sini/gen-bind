{ lib, genBind, ... }:
let
  inherit (genBind) contract provenance;
in
{
  flake.tests.contract.test-mk-creates-marker = {
    expr =
      (contract.mk {
        message = "ok";
      } (_: true))
        ? __contract;
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
      } null)
        ? name;
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
          message = "bad";
          blame = "caller";
        } (_: false);
      in
      !(builtins.tryEval (contract.apply c 42 null)).success;
    expected = true;
  };

  # THE RESULT DOOR (den-hoag-5rz5r): `check` is a predicate, so a result that is not a Boolean is
  # refused by name, catchably. WHAT A FAILING RUN LOOKS LIKE: without the door, `if` aborts
  # UNCATCHABLY with Nix's own `expected a Boolean but found a string`, naming neither the site nor
  # the field, and `tryEval` cannot see it.
  flake.tests.contract.test-apply-refuses-a-non-boolean-result-catchably = {
    expr =
      builtins.map (r: (builtins.tryEval (contract.apply (contract.mk { } (_: r)) 1 null)).success)
        [
          "yes"
          null
          1
          { }
        ];
    expected = [
      false
      false
      false
      false
    ];
  };

  flake.tests.contract.test-apply-serves-a-boolean-result-from-a-functor = {
    expr = contract.apply (contract.mk { } { __functor = _: _: true; }) 1 null;
    expected = 1;
  };

  flake.testsError.contract = {
    test-apply-names-a-non-boolean-result = {
      expr = contract.apply (contract.mk { } (_: "yes")) 1 null;
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]contract[.]apply: `check` returned a string, not a Boolean$";
      };
    };
  };
}

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

  # `fields` that is not a list of strings is refused by name, catchably, when the contract is
  # formed (den-hoag-9kj1f). WHAT A FAILING RUN LOOKS LIKE: without the door each one forms (`true`
  # here) and later aborts UNCATCHABLY on Nix's own `expected a list` / `expected a string` when
  # `check` or the violation message reaches it.
  flake.tests.contract.test-hasFields-refuses-a-non-string-list-catchably-at-formation = {
    expr = map (f: (builtins.tryEval (builtins.seq (contract.hasFields f) true)).success) [
      "name"
      [ 1 ]
      [
        "name"
        null
      ]
      { name = true; }
      null
    ];
    expected = [
      false
      false
      false
      false
      false
    ];
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

  # THE TYPE-NAME DOOR (den-hoag-9kj1f): every name `builtins.typeOf` returns forms a contract that
  # serves a value of that kind and blames another.
  flake.tests.contract.test-isType-serves-and-blames-every-declared-name = {
    expr =
      builtins.mapAttrs
        (t: v: {
          serves = (builtins.tryEval (builtins.seq (contract.apply (contract.isType t) v null) true)).success;
          blames =
            (builtins.tryEval (contract.apply (contract.isType t) (if t == "int" then "s" else 1) null))
            .success;
        })
        {
          bool = true;
          float = 1.0;
          int = 1;
          lambda = x: x;
          list = [ ];
          null = null;
          path = ./.;
          set = { };
          string = "s";
        };
    expected = builtins.listToAttrs (
      map
        (t: {
          name = t;
          value = {
            serves = true;
            blames = false;
          };
        })
        [
          "bool"
          "float"
          "int"
          "lambda"
          "list"
          "null"
          "path"
          "set"
          "string"
        ]
    );
  };

  # A name outside the nine — a misspelling, another vocabulary's name, or not a string at all — is
  # refused catchably when the contract is formed. WHAT A FAILING RUN LOOKS LIKE: without the door each
  # string forms (`true` here) and then blames every value, and each non-string forms and later aborts
  # UNCATCHABLY on `cannot coerce … to a string` when the violation message is built.
  flake.tests.contract.test-isType-refuses-an-unknown-name-catchably-at-formation = {
    expr = map (t: (builtins.tryEval (builtins.seq (contract.isType t) true)).success) [
      "sett"
      "attrset"
      "attrs"
      "str"
      "function"
      "Set"
      ""
      null
      1
      [ "set" ]
      { }
    ];
    expected = [
      false
      false
      false
      false
      false
      false
      false
      false
      false
      false
      false
    ];
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
    test-hasFields-names-a-non-list = {
      expr = contract.hasFields "name";
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]contract[.]hasFields: `fields` is a string, not a list of strings$";
      };
    };
    test-hasFields-names-a-non-string-field = {
      expr = contract.hasFields [
        "name"
        1
      ];
      expectedError = {
        type = "ThrownError";
        msg = "^gen-bind[.]contract[.]hasFields: `fields` holds a int, not a list of strings$";
      };
    };
    test-isType-names-an-unknown-type = {
      expr = contract.isType "attrset";
      expectedError = {
        type = "ThrownError";
        msg = ''^gen-bind[.]contract[.]isType: `type` is "attrset", not one of "bool", "float", "int", "lambda", "list", "null", "path", "set", "string"$'';
      };
    };
    test-isType-names-a-non-string-type = {
      expr = contract.isType null;
      expectedError = {
        type = "ThrownError";
        msg = ''^gen-bind[.]contract[.]isType: `type` is a null, not one of "bool", "float", "int", "lambda", "list", "null", "path", "set", "string"$'';
      };
    };
  };
}

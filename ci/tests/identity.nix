{ lib, genBind, ... }:
let
  inherit (genBind) wrapIdentity;
in
{

  flake.tests.identity.test-named-produces-key-and-file = {
    expr =
      let
        result = wrapIdentity { } "nixos" "postgres" {
          x = 1;
        };
      in
      {
        hasKey = result ? key;
        hasFile = result ? _file;
        hasImports = result ? imports;
      };
    expected = {
      hasKey = true;
      hasFile = true;
      hasImports = true;
    };
  };

  flake.tests.identity.test-named-key-format = {
    expr =
      (wrapIdentity { } "nixos" "postgres" {
        x = 1;
      }).key;
    expected = "nixos@postgres";
  };

  flake.tests.identity.test-anon-uses-setDefaultModuleLocation = {
    expr =
      let
        result =
          wrapIdentity
            {
              isAnon = true;
            }
            "nixos"
            "anon"
            {
              x = 1;
            };
      in
      builtins.isAttrs result;
    expected = true;
  };
}

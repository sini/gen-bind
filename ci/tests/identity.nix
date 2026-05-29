{ lib, genBind, ... }:
let
  inherit (genBind) wrapIdentity;
in
{

  flake.tests.identity.test-named-produces-key-and-file = {
    expr =
      let
        result = wrapIdentity {
          class = "nixos";
          module = {
            x = 1;
          };
          identity = "postgres";
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
      (wrapIdentity {
        class = "nixos";
        module = {
          x = 1;
        };
        identity = "postgres";
      }).key;
    expected = "nixos@postgres";
  };

  flake.tests.identity.test-anon-uses-setDefaultModuleLocation = {
    expr =
      let
        result = wrapIdentity {
          class = "nixos";
          module = {
            x = 1;
          };
          identity = "anon";
          isAnon = true;
        };
      in
      builtins.isAttrs result;
    expected = true;
  };
}

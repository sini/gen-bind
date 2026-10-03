{ lib, genBind, ... }:
let
  inherit (genBind) compose composeWith wrap;
in
{
  flake.tests.compose.test-later-shadows-earlier = {
    expr = compose [
      {
        host = "a";
        user = "x";
      }
      { host = "b"; }
    ];
    expected = {
      host = "b";
      user = "x";
    };
  };

  flake.tests.compose.test-empty-layers = {
    expr = compose [
      { }
      { x = 1; }
      { }
    ];
    expected = {
      x = 1;
    };
  };

  flake.tests.compose.test-composeWith-merges-all-fields = {
    expr =
      let
        result = composeWith [
          {
            bindings = {
              host = "a";
            };
            provenance = {
              host = {
                source = "p1";
              };
            };
          }
          {
            bindings = {
              user = "b";
            };
            provenance = {
              user = {
                source = "p2";
              };
            };
          }
        ];
      in
      {
        bindings = result.bindings;
        provenance = result.provenance;
      };
    expected = {
      bindings = {
        host = "a";
        user = "b";
      };
      provenance = {
        host = {
          source = "p1";
        };
        user = {
          source = "p2";
        };
      };
    };
  };

  flake.tests.compose.test-composeWith-later-wins = {
    expr =
      (composeWith [
        {
          bindings = {
            x = 1;
          };
          provenance = {
            x = {
              source = "first";
            };
          };
        }
        {
          bindings = {
            x = 2;
          };
          provenance = {
            x = {
              source = "second";
            };
          };
        }
      ]).provenance.x.source;
    expected = "second";
  };

  # A layer field is a record, so a non-attrset one is refused by name and catchably when
  # `composeWith layers` is formed (den-hoag-bvpuo). WHAT A FAILING RUN LOOKS LIKE: `wrap`'s door
  # forces the merged `mergeStrategies` and aborts uncatchably on `expected a set`.
  flake.tests.compose.test-composeWith-refuses-a-non-attrset-field-catchably = {
    expr =
      (builtins.tryEval (builtins.seq (wrap (composeWith [ { mergeStrategies = "s"; } ])) null)).success;
    expected = false;
  };

  flake.testsError.compose.test-composeWith-names-a-non-attrset-field = {
    expr = composeWith [ { mergeStrategies = "system-wins"; } ];
    expectedError = {
      type = "ThrownError";
      msg = "^gen-bind[.]composeWith: `mergeStrategies` must be an attrset, not a string$";
    };
  };
}

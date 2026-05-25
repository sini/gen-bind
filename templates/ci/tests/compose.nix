{ lib, bindLib, ... }:
let
  inherit (bindLib) compose composeWith;
in
{
  compose.test-later-shadows-earlier = {
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

  compose.test-empty-layers = {
    expr = compose [
      { }
      { x = 1; }
      { }
    ];
    expected = {
      x = 1;
    };
  };

  compose.test-composeWith-merges-all-fields = {
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

  compose.test-composeWith-later-wins = {
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
}

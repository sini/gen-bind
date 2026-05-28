{ lib, bindLib, ... }:
let
  inherit (bindLib)
    mkThunk
    mkThunkFrom
    isThunk
    resolveThunks
    ;
in
{

  flake.tests.thunk.test-mkThunk-creates-marker = {
    expr = (mkThunk ({ config, ... }: config.x)) ? __configThunk;
    expected = true;
  };

  flake.tests.thunk.test-isThunk-positive = {
    expr = isThunk (mkThunk ({ config, ... }: config.x));
    expected = true;
  };

  flake.tests.thunk.test-isThunk-negative-null = {
    expr = isThunk null;
    expected = false;
  };

  flake.tests.thunk.test-isThunk-negative-attrset = {
    expr = isThunk { foo = 1; };
    expected = false;
  };

  flake.tests.thunk.test-mkThunkFrom-attaches-scope = {
    expr = (mkThunkFrom "host=igloo" ({ config, ... }: config.x)).__sourceScope;
    expected = "host=igloo";
  };

  flake.tests.thunk.test-resolveThunks-resolves-list = {
    expr = resolveThunks {
      config = {
        networking.hostName = "igloo";
      };
      ctx = {
        host = {
          name = "igloo";
        };
      };
      thunkArgNames = [ "data" ];
      bindings = {
        data = [
          (mkThunk ({ config, ... }: [ config.networking.hostName ]))
          "static"
        ];
      };
    };
    expected = {
      data = [
        "igloo"
        "static"
      ];
    };
  };

  flake.tests.thunk.test-resolveThunks-passes-ctx-args = {
    expr = resolveThunks {
      config = { };
      ctx = {
        host = {
          name = "igloo";
        };
      };
      thunkArgNames = [ "data" ];
      bindings = {
        data = [
          (mkThunk ({ host, ... }: [ host.name ]))
        ];
      };
    };
    expected = {
      data = [ "igloo" ];
    };
  };

  flake.tests.thunk.test-resolveThunks-skips-non-thunk-args = {
    expr = resolveThunks {
      config = { };
      ctx = { };
      thunkArgNames = [ "data" ];
      bindings = {
        data = [
          "a"
          "b"
        ];
        other = "untouched";
      };
    };
    expected = {
      data = [
        "a"
        "b"
      ];
      other = "untouched";
    };
  };
}

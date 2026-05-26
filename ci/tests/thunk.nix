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
  thunk.test-mkThunk-creates-marker = {
    expr = (mkThunk ({ config, ... }: config.x)) ? __configThunk;
    expected = true;
  };

  thunk.test-isThunk-positive = {
    expr = isThunk (mkThunk ({ config, ... }: config.x));
    expected = true;
  };

  thunk.test-isThunk-negative-null = {
    expr = isThunk null;
    expected = false;
  };

  thunk.test-isThunk-negative-attrset = {
    expr = isThunk { foo = 1; };
    expected = false;
  };

  thunk.test-mkThunkFrom-attaches-scope = {
    expr = (mkThunkFrom "host=igloo" ({ config, ... }: config.x)).__sourceScope;
    expected = "host=igloo";
  };

  thunk.test-resolveThunks-resolves-list = {
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

  thunk.test-resolveThunks-passes-ctx-args = {
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

  thunk.test-resolveThunks-skips-non-thunk-args = {
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

{ lib }:
let
  thunkLib = import ./thunk.nix { inherit lib; };
in
{
  inherit (thunkLib) mkThunk mkThunkFrom isThunk resolveThunks;
}

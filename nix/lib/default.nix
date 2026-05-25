{ lib }:
let
  thunkLib = import ./thunk.nix { inherit lib; };
  provenanceLib = import ./provenance.nix { inherit lib; };
  mergeStrategyLib = import ./merge-strategy.nix { inherit lib; };
in
{
  inherit (thunkLib)
    mkThunk
    mkThunkFrom
    isThunk
    resolveThunks
    ;
  provenance = provenanceLib;
  inherit (mergeStrategyLib) mergeStrategy mkMergeValidator;
}

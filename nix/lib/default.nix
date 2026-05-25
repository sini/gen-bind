{ lib }:
let
  thunkLib = import ./thunk.nix { inherit lib; };
  provenanceLib = import ./provenance.nix { inherit lib; };
  mergeStrategyLib = import ./merge-strategy.nix { inherit lib; };
  contractLib = import ./contract.nix { inherit lib; };
  composeLib = import ./compose.nix { inherit lib; };
  identityLib = import ./identity.nix { inherit lib; };
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
  contract = contractLib;
  inherit (composeLib) compose composeWith;
  inherit (identityLib) wrapIdentity;
}

{ prelude }:
let
  thunkLib = import ./thunk.nix { inherit prelude; };
  provenanceLib = import ./provenance.nix { inherit prelude; };
  mergeStrategyLib = import ./merge-strategy.nix { inherit prelude; };
  contractLib = import ./contract.nix { inherit prelude; };
  composeLib = import ./compose.nix { inherit prelude; };
  identityLib = import ./identity.nix { inherit prelude; };
  stripLib = import ./strip.nix { inherit prelude; };
  signatureLib = import ./signature.nix { inherit prelude; };
  wrapLib = import ./wrap.nix { inherit prelude; };
  argEnvLib = import ./arg-env.nix { };
  crossingLib = import ./crossing.nix { inherit prelude; };
in
{
  # The boundary crossing: the crossing node, its derived demand relation, the
  # body-term algebra, first-order contracts, the Adapter, the Linkset, and the
  # six operations. Namespaced because it is a surface, not a helper.
  crossing = crossingLib;

  inherit (argEnvLib) adaptArgs crossEval configGate;
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
  inherit (stripLib) stripBindingArgs;
  inherit (signatureLib) buildSignature;
  wrap = wrapLib.wrapCore;
  wrapAll = wrapLib.wrapAllCore;
}

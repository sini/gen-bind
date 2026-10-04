# THE DOOR TABLE (den-hoag-7gp66 P1, then P2 — `prelude.door`) — every published step of gen-bind that
# takes a RECORD, read by `door-checks.nix` (catchability, contracts, the guard, and the refusal
# bytes). The leading `_` keeps the harness from collecting it as a test module.
#
# After P2 a step is one of two kinds (R7). An OPTIONS step is a closed set, first in the call: a row
# is the door, its `optional` names, and — for G3 — `on`, a non-default option, with `run`, which
# completes the call from the options-applied door and projects a field the option moves. A RECORD
# step is an open data record (R5): a row is the step as applied (every earlier operand supplied),
# its `required` fields, a `good` record, the field `drop` removes, and — for a record behind an
# options step — `guardedBy`, the options row whose names the record refuses (`optionsStep`, G10).
# `step good` must answer: that is each row's live control.
#
# A record row may also carry `typo`, a misspelling of `drop` written IN PLACE of it: every field
# of such a record is required, so the misspelling leaves `drop` missing and an open door refuses it.
#
# A CLOSED record step (den-hoag-ekum1) refuses a field outside its closed set, so a misspelling is an
# unknown field and closure refuses it: a row is the step as applied, a `good` record, `extra`, a field
# outside the closed set, and `accepted`, that set (required, then optional). `composeWith`'s layer is
# one, a door behind a positional list, so it is reached through `composeWith [ layer ]`. A closed
# step with required fields carries `required` too, and each is dropped in turn: `mkHostedTerminal`'s
# adapter carriage (den-hoag-54al9), a total key set of five required members and three optional ones.
#
# The positional doors (`adaptArgs`, `stripBindingArgs`) carry no row: their arity is structural and
# they have no field check.
{
  genBind,
  genScope,
  lib,
}:
let
  inherit (genBind.crossing) binding term;

  hostedTerminal = genBind.crossing.mkHostedTerminal {
    evaluator = _: { };
    locateConfig = _: { };
    class = "host";
  };
  adapterRequired = [
    "extent"
    "extraModules"
    "peersOf"
    "engine"
    "readerId"
  ];

  # A module reading one arg, defaulted, so the `{ }` call answers too.
  reads =
    {
      v ? 0,
      ...
    }:
    {
      x = v;
    };
  signatureRecord = {
    module =
      { w, ... }:
      {
        inherit w;
      };
    bindings = { };
    defaultMergeStrategy = "bind-wins";
    mergeStrategies = { };
  };
  thunkRecord = {
    config.v = 0;
    ctx = { };
    thunkArgNames = [ "k" ];
    bindings.k = [ (genBind.mkThunkFrom "p" ({ config, ... }: config.v)) ];
  };
  # `wrap`/`wrapAll`'s options: every field of the old one-record call but the module(s).
  wrapOptions = [
    "bindings"
    "contracts"
    "defaultMergeStrategy"
    "mergeStrategies"
    "producerConfigs"
    "provenance"
    "thunkBindings"
  ];
  # For the module-evaluating doors: the arg is read without being a formal, because the module
  # system hands a declared formal from `_module.args` even over its default, so the `{ }` arm would
  # abort on a missing attribute rather than answer.
  readsArg =
    { config, ... }@args:
    {
      x = args.v or config._module.args.v or 0;
    };
  environmentRecord = {
    unit = "igloo";
    crossings = [ ];
    projection = { };
  };
in
{
  options = {
    wrap = {
      door = genBind.wrap;
      optional = wrapOptions;
      on.bindings.v = 1;
      run = f: (f reads).wrapped;
    };
    wrapAll = {
      door = genBind.wrapAll;
      optional = wrapOptions;
      on.bindings.v = 1;
      run = f: (builtins.head (f [ reads ]).signatures).bound ? v;
    };
    wrapIdentity = {
      door = genBind.wrapIdentity;
      optional = [ "isAnon" ];
      on.isAnon = true;
      run = f: f "nixos" "i" { } ? key;
    };
    crossEval = {
      door = genBind.crossEval;
      optional = [
        "specialArgs"
        "moduleArgs"
        "absorb"
      ];
      on.specialArgs.v = 1;
      run = f: (f lib readsArg).config.x;
    };
    configGate = {
      door = genBind.configGate;
      optional = [
        "adapt"
        "absorb"
      ];
      on.adapt = _: { v = 1; };
      run = f: ((f (_: true) readsArg) { inherit lib; }).config.content.x;
    };
    buildSignature = {
      door = genBind.buildSignature;
      optional = [
        "provenance"
        "vocabulary"
      ];
      on.vocabulary = [ "w" ];
      run = f: (f signatureRecord).unsatisfied;
    };
    resolveThunks = {
      door = genBind.resolveThunks;
      optional = [ "producerConfigs" ];
      on.producerConfigs.p.v = 1;
      run = f: (f thunkRecord).k;
    };
    "contract.mk" = {
      door = genBind.contract.mk;
      optional = [
        "message"
        "blame"
      ];
      on.message = "m";
      run = f: (f (_: true)).message;
    };
  };

  # The options doors whose next step is not a record.
  notChained = [
    "wrap"
    "wrapAll"
    "wrapIdentity"
    "crossEval"
    "configGate"
    "contract.mk"
  ];

  records = {
    buildSignature = {
      step = genBind.buildSignature { };
      required = [
        "module"
        "bindings"
        "defaultMergeStrategy"
        "mergeStrategies"
      ];
      good = signatureRecord;
      drop = "mergeStrategies";
      guardedBy = "buildSignature";
    };
    resolveThunks = {
      step = genBind.resolveThunks { };
      required = [
        "config"
        "ctx"
        "thunkArgNames"
        "bindings"
      ];
      good = thunkRecord;
      drop = "bindings";
      guardedBy = "resolveThunks";
    };
    mkMergeValidator = {
      step = genBind.mkMergeValidator;
      required = [
        "resolvePolicy"
        "boundArgNames"
        "provenance"
      ];
      good = {
        resolvePolicy = _: "bind-wins";
        boundArgNames = [ ];
        provenance = { };
      };
      drop = "provenance";
    };
    "crossing.placement" = {
      step = genBind.crossing.placement;
      required = [
        "staticityAdmissible"
        "deltaExact"
        "adapter"
        "name"
      ];
      good = {
        staticityAdmissible = true;
        deltaExact = "EXACT";
        adapter.bindFormals = _: _: { };
        name = "db";
      };
      drop = "name";
    };
    "crossing.environment" = {
      step = genBind.crossing.environment;
      required = [
        "unit"
        "crossings"
        "projection"
      ];
      good = environmentRecord;
      drop = "projection";
    };
    "crossing.linked" = {
      step = genBind.crossing.linked;
      required = [
        "unit"
        "crossings"
        "projection"
      ];
      good = environmentRecord;
      drop = "crossings";
    };
    "crossing.coherence" = {
      step = genBind.crossing.coherence;
      required = [
        "unit"
        "crossings"
        "projection"
        "linkset"
      ];
      good = environmentRecord // {
        linkset.members = [ ];
      };
      drop = "linkset";
    };
    "crossing.mkHostedTerminal" = {
      step = genBind.crossing.mkHostedTerminal;
      required = [
        "evaluator"
        "locateConfig"
        "class"
      ];
      good = {
        evaluator = _: { };
        locateConfig = _: { };
        class = "host";
      };
      drop = "class";
    };
    "crossing.binding.plain" = {
      step = binding.plain;
      required = [
        "value"
        "mark"
      ];
      good = {
        value = 1;
        mark = "Floor";
      };
      drop = "value";
      typo = "vaule";
    };
    "crossing.binding.termed" = {
      step = binding.termed;
      required = [
        "term"
        "mark"
      ];
      good = {
        term = term.lit 1;
        mark = "Floor";
      };
      drop = "term";
      typo = "trem";
    };
    "crossing.binding.scoped" = {
      step = binding.scoped;
      required = [
        "file"
        "scope"
        "producer"
        "mark"
      ];
      good = {
        file = ./_crossing-scoped-body.nix;
        scope = { };
        producer = "p";
        mark = "Open";
      };
      drop = "producer";
      typo = "prodcuer";
    };
    "crossing.binding.wrapped" = {
      step = binding.wrapped;
      required = [
        "producer"
        "body"
        "mark"
      ];
      good = {
        producer = "p";
        body = _: 1;
        mark = "Open";
      };
      drop = "body";
      typo = "bdoy";
    };
  };

  closed = {
    composeWith = {
      step = layer: genBind.composeWith [ layer ];
      good.bindings.v = 1;
      extra = "bindngs";
      accepted = [
        "bindings"
        "provenance"
        "contracts"
        "mergeStrategies"
      ];
    };
    "crossing.mkHostedTerminal.adapter" = {
      step = hostedTerminal.adapter;
      required = adapterRequired;
      good = {
        extent.a = 1;
        extraModules = [ ];
        peersOf = _: [ "a" ];
        engine = genScope;
        readerId = "a";
      };
      extra = "thunkBngings";
      accepted = adapterRequired ++ [
        "marksOf"
        "passthrough"
        "thunkBindings"
      ];
    };
  };
}

# gen-bind — module binding with external arguments for Nix

[![CI](https://github.com/sini/gen-bind/actions/workflows/ci.yml/badge.svg)](https://github.com/sini/gen-bind/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT) [![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/sini)

Module binding with external arguments for Nix — partial application of bindings into NixOS module functions with closure-based injection, collision detection with blame, lazy contracts, and thunk resolution for config-dependent values.

gen-bind gives you what manual `specialArgs` doesn't: `builtins.functionArgs` introspection to inject only the args a module actually declares, merge strategy control when bindings collide with module-system args, contract assertions that fire on demand rather than at wrap time, and provenance tracking that names the source in every error message.

gen-bind is a **nixpkgs-lib-free Class B** library: its only dependency is [gen-prelude](https://github.com/sini/gen-prelude) (pure, zero-input). It remains module-system-*aware* — not -*dependent* — emitting modules in the nixpkgs `__functionArgs`/`_file`/`key` convention via two helpers vendored locally in `lib/module-convention.nix`, with no `nixpkgs.lib` import. A CI `purity` invariant and an `evalModules` equivalence test keep that boundary honest.

## Table of Contents

- [Terminology](#terminology)
- [Overview](#overview)
- [Gen Ecosystem](#gen-ecosystem)
- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
  - [Bindings and Wrapping](#bindings-and-wrapping)
  - [Module Shapes](#module-shapes)
  - [Merge Strategies](#merge-strategies)
  - [Config Thunks](#config-thunks)
  - [Lazy Contracts](#lazy-contracts)
  - [Provenance](#provenance)
  - [Signatures](#signatures)
  - [Layered Composition](#layered-composition)
  - [Identity Wrapping](#identity-wrapping)
  - [Arg Stripping](#arg-stripping)
  - [Batch Wrapping](#batch-wrapping)
  - [Terminal-Crossing Arg-Environment](#terminal-crossing-arg-environment)
- [API Reference](#api-reference)
- [Laziness Guarantees](#laziness-guarantees)
- [Architecture](#architecture)
- [Testing](#testing)
- [Theoretical Foundations](#theoretical-foundations)

## Terminology

| Term | Definition |
|------|-----------|
| Bindings | Named external values injected into module functions |
| Wrapping | Partial application of bindings into a module's args |
| Merge Strategy | Resolution policy when a binding name collides with a module-system arg |
| Thunk | Config-dependent deferred value resolved inside `evalModules` |
| Contract | Lazy assertion on a binding value (checked on demand, not at wrap time) |
| Provenance | Source-tracking metadata surfaced in blame messages on collision or violation |
| Signature | Static record of what a module requires, what was bound, and what remains |

## Overview

A NixOS module is a function `{ arg1, arg2, ... }: { ...config... }` whose formal
parameters are resolved by `evalModules` from `specialArgs` and `_module.args`. gen-bind
sits *in front of* that resolution: it takes a module plus a set of named **bindings** and
partially applies the bindings the module actually declares — determined by
`builtins.functionArgs` introspection, never by evaluating the values — leaving every other
arg for `evalModules` to supply as normal.

The mental model is a single pipeline over four parallel keyed maps, all indexed by binding
arg name:

- **bindings** — the external values to inject (`{ host = ...; }`),
- **contracts** — lazy per-binding assertions that fire only when the arg is demanded,
- **provenance** — blame metadata that names the source in every error message,
- **mergeStrategies** — collision policy when a binding name shadows a module-system arg.

`wrap` (single module) and `wrapAll` (batch) consume those maps and return a record
`{ module; wrapped; validator; signature; advertisedArgs }`. `compose`/`composeWith` merge
binding sources upstream; `mkThunk` defers a binding that depends on the `config` fixpoint;
`wrapIdentity` and `stripBindingArgs` post-process the wrapped module for NixOS key-dedup
and advertised-arg hygiene. Nothing in the pipeline forces a binding value that the target
module does not demand, so unbuilt hosts carry zero binding cost.

## Gen Ecosystem

| Library | Role |
|---------|------|
| [gen-prelude](https://github.com/sini/gen-prelude) | Pure nixpkgs-lib-free utility base (builtins re-exports + vendored lib utils) |
| [gen-algebra](https://github.com/sini/gen-algebra) | Pure primitives (record, search monad, either, intensional identity) |
| [gen-types](https://github.com/sini/gen-types) | Clean-room MIT structural type checker (leaf/poly checkers; `verify: v → null\|err`) |
| [gen-merge](https://github.com/sini/gen-merge) | Byte-mode module merge engine (`evalModuleTree`, byte-identical to nixpkgs `lib.evalModules` over the priority subset) |
| [gen-schema](https://github.com/sini/gen-schema) | Typed registries (kinds, instances, collections, refs); re-hosted on gen-merge |
| [gen-aspects](https://github.com/sini/gen-aspects) | Aspect type system (traits, classification, dispatch); re-hosted on gen-merge |
| [gen-scope](https://github.com/sini/gen-scope) | HOAG scope-graph evaluator (demand-driven, \_eval memoization, circular attributes) |
| [gen-graph](https://github.com/sini/gen-graph) | Accessor-based graph query combinators (traversal, condensation, phaseOrder) |
| [gen-select](https://github.com/sini/gen-select) | Selector algebra (pattern matching over graph positions) |
| [gen-bind](https://github.com/sini/gen-bind) | **This lib** — Module binding (inject external args into NixOS modules) |
| [gen-dispatch](https://github.com/sini/gen-dispatch) | Relational rule dispatch STEP (stratified phases, conflict resolution) |
| [gen-resolve](https://github.com/sini/gen-resolve) | Demand-driven RAG evaluator over scope graphs (attribute schedule + convergence loop) |
| [gen-rebuild](https://github.com/sini/gen-rebuild) | Pure-Nix incremental rebuilder (change propagation, AFFECTED set) |
| [gen-vars](https://github.com/sini/gen-vars) | Pure-Nix vars/secrets (den-agnostic) |
| [gen-flake](https://github.com/sini/gen-flake) | The nixpkgs boundary — compose purely, inject resolved values, build NixOS systems (value-injection) |

## Quick Start

### As a flake input

```nix
# flake.nix
{
  inputs.gen-bind.url = "github:sini/gen-bind";
  # gen-bind's only dependency is gen-prelude (pulled in transitively, zero-input).
  # nixpkgs below is the consumer's own dependency, not gen-bind's.

  outputs = { gen-bind, ... }:
    let
      genBind = gen-bind.lib;
      # or instantiate the lib directly (needs a gen-prelude input):
      #   genBind = import "${gen-bind}/lib" { prelude = inputs.gen-prelude.lib; };
    in {
      # Wrap a module with external bindings
      wrappedModule = (genBind.wrap {
        module = { host, config, lib, ... }: {
          networking.hostName = host.name;
        };
        bindings = { host = { name = "igloo"; }; };
      }).module;
    };
}
```

### Programmatic use

```nix
let
  # prelude = gen-prelude's lib, e.g. import "${gen-prelude}/lib"
  genBind = import ./path/to/gen-bind/lib { inherit prelude; };
  result = genBind.wrap {
    module = { host, pkgs, config, ... }: {
      environment.systemPackages = [ pkgs.git ];
      networking.hostName = host.name;
    };
    bindings = { host = { name = "igloo"; }; };
    # pkgs comes from evalModules specialArgs — wrap only injects `host`
  };
in result.module  # function: { pkgs, config, ... } -> { ... }
```

### Without flakes

```nix
let
  prelude = import ./path/to/gen-prelude/lib { };
  genBind = import ./path/to/gen-bind/lib { inherit prelude; };
in
# use genBind.wrap, genBind.wrapAll, genBind.contract, etc.
```

## Core Concepts

### Bindings and Wrapping

`wrap` inspects a module's formal parameters via `builtins.functionArgs` and injects only the bindings that match. Non-matching bindings are ignored. The result is a partially-applied module whose remaining args come from `evalModules` as normal.

```nix
result = genBind.wrap {
  module = { host, config, lib, ... }: {
    networking.hostName = host.name;
  };
  bindings = { host = { name = "igloo"; }; extraUnused = "ignored"; };
};

# result.module   — partially applied: { config, lib, ... } -> { ... }
# result.wrapped  — true
# result.signature — { requires = { config = false; lib = false; }; bound = { host = { ... }; }; ... }
```

When no binding names match the module's args, the module passes through unchanged (`result.wrapped = false`).

### Module Shapes

`wrap` handles three module shapes:

- **Function** — standard `{ arg1, arg2, ... }: { ... }`. Bindings are injected via partial application.
- **Imports attrset** — `{ imports = [ mod1 mod2 ]; }`. Each import is wrapped recursively.
- **Plain attrset** — `{ config = { ... }; }`. Passes through unchanged.

### Merge Strategies

When a binding name collides with a module-system arg (e.g., both gen-bind and `evalModules` provide `lib`), the merge strategy determines resolution:

```nix
result = genBind.wrap {
  module = { lib, host, ... }: { networking.hostName = host.name; };
  bindings = { host = { name = "igloo"; }; lib = myCustomLib; };
  mergeStrategies = {
    lib = genBind.mergeStrategy.systemWins;  # module-system lib wins
    # or: genBind.mergeStrategy.bindWins (default)
    # or: genBind.mergeStrategy.error (throw at eval time)
  };
};
```

The default strategy is `bindWins` — binding shadows the module-system arg. Set `_mergeStrategy` directly on a binding value as an inline annotation:

```nix
bindings = {
  lib = myLib // { _mergeStrategy = "system-wins"; };
};
```

Collision detection runs when `mkMergeValidator` is called with the module args. Warnings (for `bindWins`/`systemWins`) and errors (for `error`) include provenance if set.

### Config Thunks

Some bindings depend on the `evalModules` fixpoint — they can't be computed until `config` is available. Use `mkThunk` to defer resolution:

```nix
result = genBind.wrap {
  module = { extraModules, config, ... }: {
    imports = extraModules;
  };
  bindings = {
    extraModules = [
      # Static entry
      myBaseModule
      # Thunk — resolved when evalModules calls the wrapper
      (genBind.mkThunk ({ config }: lib.optional config.services.nginx.enable nginxExtraModule))
    ];
  };
};
```

Thunks travel as markers (`{ __configThunk = true; __fn = fn; }`) through the binding pipeline and resolve inside the module wrapper when `evalModules` provides `config`. Only list-valued bindings are auto-detected for thunks. Non-list bindings with thunks require explicit `thunkBindings = [ "argName" ]`.

`mkThunkFrom scopeId fn` creates a thunk annotated with a source scope for tracing.

#### Producer-scoped resolution

By default a thunk resolves against the `config` of the terminal that *consumes* it. When a config-dependent value is produced at one terminal but delivered to another (a value broadcast/exposed/routed across hosts or user-cells), the consumer's `config` is the wrong one to read. Pass an optional `producerConfigs` map — an opaque `scopeKey → config` attrset — so a `mkThunkFrom scope fn` thunk resolves against the *producer's* config instead:

```nix
result = genBind.wrap {
  module = { peers, config, ... }: { networking.domain = builtins.head peers; };
  bindings = {
    peers = [
      # Produced at iceberg, consumed at igloo. __sourceScope = "host=iceberg".
      (genBind.mkThunkFrom "host=iceberg" ({ config, ... }: [ "h-${config.networking.hostName}" ]))
    ];
  };
  # Resolve the thunk against iceberg's terminal config, not igloo's:
  producerConfigs = {
    "host=iceberg" = icebergTerminalConfig;  # a lazy ref to the producer's config
  };
};
```

- **Opaque + general.** gen-bind does one lazy attrset index (`producerConfigs.${thunk.__sourceScope}`); it knows nothing about scopes, classes, or hosts. The consumer builds the map and chooses the key encoding — a scope with multiple class terminals (e.g. a host's `nixos` vs a user-cell's `home-manager`) must qualify the key so each thunk's `__sourceScope` selects the right terminal.
- **Back-compat.** The default `producerConfigs = {}` is byte-identical to the prior behavior: every thunk resolves against the consumer `config`. A plain `mkThunk` thunk (`__sourceScope = null`) always resolves against the consumer config, even when a non-empty map is supplied; a `mkThunkFrom` thunk whose scope is absent from the map falls back to the consumer config.
- **Both dispatch paths.** Thunks resolve whether the module is partially applied (some args still come from `evalModules`) or fully applied (every named arg bound — e.g. a channel-only `{ ch, ... }` where the `...` is not a `functionArgs` entry). A `__sourceScope` thunk resolves against its producer on both paths (the producer config is self-sufficient). A `null`-scope thunk on the fully-applied path has no `evalModules` `config`, so it resolves against a bound `config` arg if present, else sees `{}` — a null-scope config-thunk that needs `config` belongs on the partial-app path (declare `config` as an unbound arg).
- **Lazy (A17).** Supply `producerConfigs` as a lazy `lib.fix`/`genAttrs` over your terminals. gen-bind never forces a producer config at wrap time — it is read only to the depth `__fn` demands, at the consumer, on resolve.
- **Loud on genuine cycle.** An acyclic-at-use cross-terminal read (the producer value does not read back into the consumer) resolves cleanly — Nix's own `lib.fix` ties the knot. A genuine cross-terminal cycle (the producer config transitively demands the same thunk) surfaces as Nix's `infinite recursion encountered` — loud and `tryEval`-uncatchable, never a silent stale read. (Theory: Söderberg & Hedin 2013 CHORAG §5.1 — materialization-as-attribution; let the host's lazy fixpoint be the cross-terminal solver.)

### Lazy Contracts

Contracts are assertions that fire only when the bound value is demanded — preserving Nix's lazy evaluation semantics. Unbuilt modules have zero contract cost.

```nix
result = genBind.wrap {
  module = { host, ... }: { networking.hostName = host.name; };
  bindings = { host = { name = "igloo"; }; };
  contracts = {
    host = genBind.contract.hasFields [ "name" "system" ];
    # or: genBind.contract.isType "set"
    # or: genBind.contract.nonEmpty
    # or: genBind.contract.mk { check = v: v.name != ""; message = "host must have non-empty name"; }
  };
  provenance = {
    host = { source = "entity-context"; scope = "host=igloo"; };
  };
};
```

Contract violations include the message and provenance:

```
gen-bind: contract violation: value must have fields: name, system (provided by 'entity-context' at scope 'host=igloo')
```

`contract.apply contract value prov` applies a contract directly without going through `wrap`.

### Provenance

Provenance metadata on the `wrap` call surfaces in all blame messages — collisions, contract violations, and error-strategy throws:

```nix
genBind.wrap {
  module = myModule;
  bindings = { host = hostVal; };
  provenance = {
    host = { source = "scope-policy"; scope = "host=igloo,user=tux"; };
  };
};
```

`provenance.format prov` formats a provenance record to a string (`"provided by 'scope-policy' at scope 'host=igloo,user=tux'"`) or returns `""` for `null`.

### Signatures

Every `wrap` result includes a signature describing the module's binding interface:

```nix
result.signature
# -> {
#     requires = { config = false; lib = false; };  # still needed from evalModules
#     bound = { host = { optional = false; provenance = { source = "..."; }; }; };
#     unsatisfied = [];  # vocabulary keys present but not injected
#     mergeStrategies = { host = "bind-wins"; };
#   }
```

`buildSignature` computes the signature from a module + binding config without performing wrapping.

### Layered Composition

Multiple binding sources (entity context, enrichment, pipes) compose with later layers shadowing earlier ones:

```nix
# compose: plain attrset merge
allBindings = genBind.compose [
  entityBindings
  enrichmentBindings
  pipeBindings
];

# composeWith: structured merge across all binding fields
cfg = genBind.composeWith [
  { bindings = entityBindings; provenance = entityProv; }
  { bindings = enrichBindings; contracts = enrichContracts; }
  { bindings = pipeBindings; mergeStrategies = pipeStrats; }
];
# cfg.bindings, cfg.provenance, cfg.contracts, cfg.mergeStrategies — all merged

result = genBind.wrap (cfg // { module = myModule; });
```

### Identity Wrapping

NixOS deduplicates modules by `key`. `wrapIdentity` stamps a stable key onto a wrapped module so that re-emitting the same module at the same identity doesn't duplicate it in `evalModules`:

```nix
keyed = genBind.wrapIdentity {
  class = "nixos";
  module = result.module;
  identity = "host=igloo";
  # isAnon = false;  # default: sets key + _file + imports wrapper
};
# keyed -> { key = "nixos@host=igloo"; _file = "nixos@host=igloo"; imports = [ result.module ]; }
```

Set `isAnon = true` to stamp only `_file` (via the vendored `setDefaultModuleLocation` convention helper) instead — useful for anonymous modules that shouldn't appear in `key`-based dedup.

### Arg Stripping

After wrapping, binding arg names must be removed from the module's advertised args. Otherwise `evalModules` probes `_module.args.<name>` for every advertised arg and crashes when the key doesn't exist.

```nix
stripped = genBind.stripBindingArgs {
  module = result.module;
  bindingNames = [ "host" ];
};
```

Works on both function modules and attrset modules with `__functionArgs`. Args not present in the module's advertised interface are silently skipped.

### Batch Wrapping

`wrapAll` wraps a list of modules with shared bindings, pre-computing contracts once across all modules:

```nix
batch = genBind.wrapAll {
  modules = [ modA modB modC ];
  bindings = sharedBindings;
  contracts = sharedContracts;
  provenance = sharedProv;
};

# batch.modules    — list of wrapped modules
# batch.validators — list of non-null validators (one per wrapped function module)
# batch.signatures — list of signatures (one per module)
# batch.all        — wrapped modules ++ non-null validators (flat list)
```

### Terminal-Crossing Arg-Environment

`wrap`/`mkThunk` rewrite a module's FORMAL parameters *before* `evalModules`. But a reach/delivery edge that crosses a module-system boundary must rewrite the **arg environment** the placed slice resolves against **at** the `evalModules` boundary (`_module.args` / `specialArgs`), and may **gate** the slice's resolved config on an eval-time predicate. Content rewriters (gen-edge's `adapt`: content → Π → content, run in the pre-eval fold) structurally cannot reach that boundary — they never see `_module.args`/`specialArgs`. Three primitives do:

```nix
# adaptArgs — inject `_module.args = adapt args` alongside a placed slice (the in-module
# arg-env channel). `adapt` reads the crossing args (config/pkgs/lib/specialArgs).
adaptedModule = genBind.adaptArgs {
  adapt = args: { allModuleArgs = args.config.allModuleArgs; };
  module = placedSlice;
};

# crossEval — resolve an OPAQUE slice through a nested evalModules in the TERMINAL's own
# evaluator (`lib` threaded in), threading a rewritten `specialArgs` env + a freeform
# absorber. Returns the eval result; read `.config`.
resolved = (genBind.crossEval {
  inherit (args) lib;
  module = sliceMod;
  specialArgs = adaptedSpecialArgs;
}).config;

# configGate — gate a slice's nested-eval'd CONFIG on an eval-time predicate via `mkIf`.
gated = genBind.configGate {
  gate = args: args.options ? wsl;   # eval-time read of the terminal option-set
  module = placedSlice;
  adapt = args: { extra = args.pkgs.hello; };  # optional _module.args threading
};
```

**The two arg-env channels.** `_module.args` is the only channel a module can write from *inside* the eval (`adaptArgs`); `specialArgs` is caller-only, so rewriting it means *owning* the `evalModules` call — which is what `crossEval` is for.

**★ Load-bearing module-system bound.** `configGate` gates **config** (`mkIf`), never `imports`. Gating `imports` on a predicate that reads `options`/`config` is the fixpoint cycle `imports ← guard(options) ← options ← imports`. `mkIf` leaves `imports` unconditional, so the outer `options` set stays guard-independent. **Consequence:** a config-gate can conditionally *supply* config but **cannot** conditionally *declare* an option — a gated slice's option declarations live in the nested eval and never reach the outer option-set. The common case (a slice contributes config; the guard checks an option declared *elsewhere*) is sound; conditional option declaration is unsupported **by construction** — a module-system bound, not a gen-bind limit.

**Purity.** These primitives operate the module system *only via a `lib` threaded in at the crossing* (`crossEval`'s `lib` param; the module functions' `args.lib`) — gen-bind still imports no `nixpkgs.lib`. The `purity` suite scopes its module-system-token ban to exempt this one crossing file while keeping the `nixpkgs`-dependency ban global.

**Charter (ratified).** gen-bind's charter is now **binding injection + terminal-crossing arg-environment**. `lib/arg-env.nix` is the **sole, deliberately-ratified module-*evaluating* file** — it drives a nested `evalModules` at the reach/delivery boundary; every other `lib/` file remains module-*producing* under the full purity ban. Two invariants keep this bounded: **(P1) no nixpkgs dependency** — global and unconditional, gen-bind imports no `nixpkgs.lib` (the `lib` is always runtime-threaded, never a file parameter); **(P2) never operates the module system** — relaxed for `arg-env.nix` *by design*, and for no other file. The `purity` suite whitelists exactly the two tokens `arg-env.nix` uses (`lib.`, `evalModules`) and keeps `{ lib }`/`{ lib,`/`mkOption`/`nixpkgs` banned even there, so the exemption is a documented, single-file decision — **not a precedent for module-system creep**.

## API Reference

### `wrap`

```nix
wrap {
  module,                          # function | { imports = [...]; } | attrset
  bindings ? {},                   # { name = value; } — external values to inject
  contracts ? {},                  # { name = contract; } — lazy assertions per binding
  provenance ? {},                 # { name = { source; scope?; }; } — blame metadata
  mergeStrategies ? {},            # { name = strategy; } — per-arg collision resolution
  defaultMergeStrategy ? bindWins, # fallback strategy for unspecified args
  thunkBindings ? [],              # explicit list of list-valued args containing thunks
}
```

Returns `{ module; wrapped; validator; signature; advertisedArgs }`.

- `module` — wrapped or passthrough module
- `wrapped` — `true` if any binding was injected
- `validator` — `mkMergeValidator` result for collision checking, `null` if no bindings matched
- `signature` — `buildSignature` result
- `advertisedArgs` — remaining formal args after binding injection

### `wrapAll`

```nix
wrapAll {
  modules,          # list of modules
  bindings ? {},
  contracts ? {},
  provenance ? {},
  mergeStrategies ? {},
  defaultMergeStrategy ? bindWins,
  thunkBindings ? [],
}
```

Contracts are pre-computed once and shared across all modules. Returns `{ modules; validators; signatures; all }`.

- `modules` — list of wrapped modules
- `validators` — list of non-null validators
- `signatures` — list of signatures (one per module)
- `all` — `modules ++ validators` (flat list of wrapped modules and non-null validators), ready to pass directly to `evalModules`; the validators emit lazy `warnings` and do no work at module-collection WHNF

### `mkThunk`

```nix
mkThunk fn
```

Creates a config-dependent thunk. `fn` receives `{ config; <ctx-args>... }` — `ctx-args` are any of `fn`'s named parameters that exist in the binding context. The return value is spliced into the list binding (single value or list both work).

### `mkThunkFrom`

```nix
mkThunkFrom scopeId fn
```

Like `mkThunk` but annotates the thunk with a source scope string for tracing.

### `isThunk`

```nix
isThunk value  # -> bool
```

Returns `true` if `value` is a thunk created by `mkThunk` or `mkThunkFrom`.

### `resolveThunks`

```nix
resolveThunks { config; ctx; thunkArgNames; bindings; producerConfigs ? {}; }
```

Resolves thunks within list-valued bindings. For each arg name in `thunkArgNames` whose binding is a list, expands thunk entries by calling `__fn` with `config` and matching `ctx` args. Non-thunk entries and non-list args pass through unchanged.

`producerConfigs` (optional, default `{}`) is a `scopeKey → config` map for producer-scoped resolution: a thunk whose `__sourceScope` (from `mkThunkFrom`) is a key in the map resolves against `producerConfigs.<scope>` (the producer's config) instead of the consumer `config`. Default `{}` ⇒ every thunk resolves against the consumer `config` (byte-identical to the prior behavior); a `null`-scope thunk or an absent scope also falls back to the consumer `config`. See [Producer-scoped resolution](#producer-scoped-resolution).

### `contract.mk`

```nix
contract.mk { check; message ? "contract violation"; blame ? null; }
```

Creates a contract. `check` is `value -> bool`. `blame` is an optional string added to the error message.

### `contract.hasFields`

```nix
contract.hasFields fields  # fields: [ "name" "system" ]
```

Contract asserting the value has all listed fields.

### `contract.isType`

```nix
contract.isType type  # type: "set" | "list" | "string" | "int" | "bool" | ...
```

Contract asserting `builtins.typeOf value == type`.

### `contract.nonEmpty`

Contract asserting the value is non-empty (non-empty list, non-empty attrset, or non-null).

### `contract.apply`

```nix
contract.apply contract value prov
```

Applies a contract directly. Returns `value` if the check passes, throws with message + provenance string on failure.

### `mergeStrategy`

```nix
mergeStrategy.bindWins    # "bind-wins"   — binding shadows module-system arg (default)
mergeStrategy.systemWins  # "system-wins" — module-system arg wins, binding dropped
mergeStrategy.error       # "error"       — throw at eval time with blame

mergeStrategy.fromBindings bindings
# -> { name = strategy | null; } — extracts _mergeStrategy annotations from binding values
```

### `mkMergeValidator`

```nix
mkMergeValidator { resolvePolicy; boundArgNames; provenance; }
```

Returns a validator function `moduleArgs -> { warnings }`. Call with the module args attrset (including `config._module.args`) to check for collisions. The returned `warnings` are **lazy** (config-implicit): the `config._module.args` probe runs only when `.warnings` is demanded — post-fixpoint, the NixOS-idiomatic point — so the validator does no work at module-collection WHNF and is safe to feed straight into `evalModules` (this is what `wrapAll`'s `.all` relies on). Bind-wins and system-wins collisions produce warning strings in `.warnings`; error-strategy collisions throw, lazily, when `.warnings` is forced.

### `provenance.format`

```nix
provenance.format prov  # prov: { source; scope?; } | null
```

Returns a formatted string (`"provided by 'source' at scope 'scope'"`) or `""` for `null`.

### `compose`

```nix
compose layers  # layers: [ attrset ... ]
```

Plain left-fold `//` across binding attrsets. Later layers shadow earlier ones.

### `composeWith`

```nix
composeWith layers
# layers: [ { bindings?; provenance?; contracts?; mergeStrategies?; } ... ]
```

Structured composition across all four binding fields. Returns `{ bindings; provenance; contracts; mergeStrategies }`.

### `wrapIdentity`

```nix
wrapIdentity { class; module; identity; isAnon ? false; }
```

Stamps a stable NixOS module key onto a module. Non-anon: returns `{ key = "${class}@${identity}"; _file = ...; imports = [ module ]; }`. Anon: applies the vendored `setDefaultModuleLocation` convention helper instead.

### `stripBindingArgs`

```nix
stripBindingArgs { module; bindingNames; }
```

Removes `bindingNames` from the module's advertised formal args. Works on function modules and attrset modules with `__functionArgs`. Returns the module unchanged if no args match or the module shape doesn't support stripping.

### `buildSignature`

```nix
buildSignature { module; bindings; defaultMergeStrategy; mergeStrategies; provenance ? {}; }
```

Computes a signature record: `{ requires; bound; unsatisfied; mergeStrategies }`.

- `requires` — formal args not satisfied by bindings (pass to `evalModules`)
- `bound` — `{ argName = { optional; provenance; }; }` for each injected arg
- `unsatisfied` — arg names in vocabulary but not injected and not optional (currently always `[]` with the standard API)
- `mergeStrategies` — per-bound-arg strategy

### `adaptArgs`

```nix
adaptArgs { adapt, module }  # -> terminalArgs -> module
```

Returns a terminal module-function that, at the `evalModules` crossing, injects `_module.args = adapt args` (visible to every sibling module) and imports `module`. `adapt : crossingArgs -> attrset` derives the extended arg environment from the terminal args (`config`/`options`/`pkgs`/`lib`/`specialArgs`). `_module.args` is the only arg-env channel a module can write from inside the eval. Laziness: `adapt` and `module` are forced only when the returned function is applied by `evalModules`.

### `crossEval`

```nix
crossEval { lib, module, specialArgs ? {}, moduleArgs ? null, absorb ? true }  # -> evalModules result
```

Resolves an **opaque** `module` through a fresh nested `evalModules` in the terminal's own evaluator (`lib` threaded in — gen-bind imports no `nixpkgs.lib`), returning the eval result (read `.config`). This is what the `specialArgs` arg-env channel requires: `specialArgs` is caller-only, so rewriting it means owning the `evalModules` call.

- `specialArgs` — the caller-only arg env, available during imports resolution.
- `moduleArgs` — a config-level `_module.args` env (`null` ⇒ omit; `{}` threads an empty env).
- `absorb` — install a freeform absorber (`types.lazyAttrsOf types.raw`) so the opaque slice's config keys land regardless of the terminal type universe (nixpkgs / gen-merge). Default `true`.

Laziness: `evalModules` builds config lazily; the result is a WHNF attrset and no slice config value is forced until `.config.<key>` is demanded.

### `configGate`

```nix
configGate { gate, module, adapt ? (_: {}), absorb ? true }  # -> terminalArgs -> module
```

Returns a terminal module-function that resolves `module` in a nested `crossEval` (threading `adapt args` as its `_module.args`) and contributes the result via `mkIf (gate args) nested.config`. `gate : crossingArgs -> bool` is the eval-time predicate.

**★ The gate gates `config` (`mkIf`), never `imports`** — gating imports on a predicate that reads `options`/`config` is the fixpoint cycle `imports ← guard(options) ← options ← imports`. So a config-gate can conditionally supply config but **cannot** conditionally declare an option (a gated slice's option declarations stay in the nested eval). The common case — the guard checks an option declared *elsewhere* and gates *other* content — is sound; conditional option declaration is unsupported by construction (a module-system bound). Laziness: `gate`, `module`, `adapt` are forced only when the returned function is applied.

## Laziness Guarantees

- Binding values are never forced at `wrap` time — `builtins.functionArgs` introspects without evaluating.
- Per-arg injection uses `//` semantics — only args the module actually demands are forced.
- Contracts fire on demand only — the contract thunk wraps the binding value in an `assert`; if the module never demands the arg, the contract never runs.
- Unbuilt hosts have zero cost — thunks in list bindings resolve only when the wrapper function is called by `evalModules`.
- Terminal-crossing transforms force nothing at construction — `adaptArgs`/`configGate` return a module-function; `adapt`/`gate`/`module` are forced only when `evalModules` applies it.

## Architecture

```
External bindings (entity context, enrichment, pipes)
  | composed via
compose / composeWith
  | applied via
wrap / wrapAll
  |-- builtins.functionArgs — inspect module signature
  |-- applyContracts — lazy assertion wrapping (cf. Chitil 2012 §4.2)
  |-- resolvePolicy — per-arg merge strategy dispatch (cf. Leijen 2005 §2)
  |-- detectThunkArgs — identify config-dependent list bindings
  '-- wrapFunctionModule / wrapImportsModule / passthrough
        | result
      { module; wrapped; validator; signature; advertisedArgs }
        | optional post-processing
      wrapIdentity — NixOS key stamping (cf. Cardelli 1997 §5)
      stripBindingArgs — formal arg cleanup
      mkMergeValidator — collision detection with blame (cf. Findler 2002 §2)

Terminal-crossing arg-environment (reach/delivery edges, at the evalModules boundary)
      adaptArgs — inject `_module.args = adapt args` alongside a placed slice
      crossEval — nested evalModules in the terminal's `lib` (specialArgs / freeform absorber)
      configGate — mkIf-gate a slice's nested-eval'd config (cf. Cardelli 1997 §5 linkset)
```

### File Layout

```
lib/
  default.nix           — public API surface (takes { prelude })
  wrap.nix              — core wrapping logic (wrapCore, wrapAllCore)
  merge-strategy.nix    — collision detection and merge validator
  contract.nix          — lazy binding contracts (mk, hasFields, isType, nonEmpty, apply)
  thunk.nix             — config thunk primitives (mkThunk, mkThunkFrom, isThunk, resolveThunks)
  provenance.nix        — blame formatting
  compose.nix           — layered composition (compose, composeWith)
  identity.nix          — NixOS module identity wrapping
  strip.nix             — binding arg stripping for NixOS compatibility
  signature.nix         — module signature inference
  arg-env.nix           — terminal-crossing arg-environment transforms (adaptArgs, crossEval, configGate)
  module-convention.nix — vendored nixpkgs convention helpers (setFunctionArgs, setDefaultModuleLocation)
```

## Testing

**87 tests across 13 suites** — `arg-env`, `compose`, `contract`, `evalmodules-equivalence`,
`identity`, `integration`, `merge-strategy`, `provenance`, `purity`, `signature`, `strip`,
`thunk`, `wrap`. Tests use nix-unit in `ci/` (which keeps a `nixpkgs` dependency for the
test runner and the real `lib.evalModules` driven by the production-safety equivalence
gate and the `arg-env` crossing suite):

```bash
cd ci
nix run nixpkgs#nix-unit -- --flake .#tests            # all 87, across 13 suites
nix run nixpkgs#nix-unit -- --flake .#tests.wrap       # one suite
nix flake check                                        # full check incl. treefmt
```

The `purity` suite enforces the nixpkgs-lib-free Class B boundary — the library source
imports no `nixpkgs.lib` — and the `evalmodules-equivalence` suite drives gen-bind output
through a real `lib.evalModules` to prove the vendored convention helpers stay
byte-behavior-identical.

## Theoretical Foundations

gen-bind's design draws on five papers. Each is either **implemented** (the paper's formalism directly shapes the code) or **informed by** (the paper's concepts influenced the approach without direct implementation).

### Implements

| Feature | Paper | Relationship |
|---------|-------|-------------|
| Blame tracking | Findler & Felleisen -- [*Contracts for Higher-Order Functions*](https://www2.ccs.neu.edu/racket/pubs/icfp2002-ff.pdf) (ICFP 2002) | Provenance metadata plays the role of Findler's blame labels: when a contract fires or a collision is detected, the error message identifies the guilty party (binding source, scope rule) via the same covariant/contravariant blame assignment structure (cf. Findler 2002 S2.3). |
| Lazy contracts | Chitil -- [*Practical Typed Lazy Contracts*](https://kar.kent.ac.uk/30790/1/contacts.pdf) (ICFP 2012) | Contracts are partial identities (`assert c` is less than or equal to `id` -- Chitil 2012 S4.2) that fire on demand. gen-bind contracts wrap binding values in exactly this pattern: the assertion thunk is never forced unless the consuming module demands the arg (cf. Chitil 2012 S2). |
| Module signatures | Cardelli -- [*Program Fragments, Linking, and Modularization*](http://lucacardelli.name/Papers/Linking.A4.pdf) (POPL 1997) | gen-bind's `signature.requires` and `signature.bound` are a lightweight analog of Cardelli's linkset interfaces: each compilation unit (wrapped module) declares what it provides (bound args) and what it still needs (requires from evalModules). Identity wrapping implements Cardelli's fragment naming for dedup (cf. Cardelli 1997 S5). |

### Informed by

| Feature | Paper | Relationship |
|---------|-------|-------------|
| Closure-based binding | Reynolds -- [*Definitional Interpreters for Higher-Order Programming Languages*](https://dl.acm.org/doi/10.1145/800194.805852) (1972) | Reynolds' closure environments inform the approach but gen-bind's wrapping is partial application, not defunctionalization per se. `builtins.functionArgs` is the Nix analogue of formal parameter reflection in a definitional interpreter (cf. Reynolds 1972 S4). |
| Merge resolution | Leijen -- [*Extensible Records with Scoped Labels*](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/scopedlabels.pdf) (TFP 2005) | Leijen's free extension (retaining duplicate labels with scoped resolution) informs the merge strategy vocabulary: `bindWins` shadows like Leijen's first-match selection; `error` mirrors strict extension where duplicates are rejected (cf. Leijen 2005 S2). gen-bind uses flat `//` rather than row-typed scoping. |

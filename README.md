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
  - [The Boundary Crossing](#the-boundary-crossing)
  - [The Adapter set](#the-adapter-set)
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
- **contracts** — lazy per-binding assertions that fire when the arg is demanded (one
  narrowing, for a colliding binding — see [Lazy Contracts](#lazy-contracts)),
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
| [gen-memo](https://github.com/sini/gen-memo) | The incremental plane — decides reuse, never evaluates (change propagation, AFFECTED set) |
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
- **Loud on genuine cycle.** An acyclic-at-use cross-terminal read (the producer value does not read back into the consumer) resolves cleanly — Nix's own `lib.fix` ties the knot. A genuine cross-terminal cycle (the producer config transitively demands the same thunk) surfaces as Nix's `infinite recursion encountered` — loud and `tryEval`-uncatchable, never a silent stale read. (Theory: Söderberg & Hedin 2013 CHORAG §5.1 — materialization-as-attribution; let the evaluator's lazy fixpoint be the cross-terminal solver.)

### Lazy Contracts

Contracts are assertions that fire when the bound value is demanded — preserving Nix's lazy evaluation semantics. An unbuilt module pays no contract cost for a binding it never reads.

**One narrowing.** A binding that *collides* with a module-system arg is forced when `config.warnings` is demanded, so a contract on it can fire for an arg the module never demanded. `mkMergeValidator` has to read the value to report which side of the collision won: for an annotated binding the strategy lives *inside* the value (`_mergeStrategy`). Absent a collision, or absent a demand for `config.warnings`, nothing is forced.

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

`wrap`/`mkThunk` rewrite a module's FORMAL parameters *before* `evalModules`. But a reach/delivery edge that crosses a module-system boundary must rewrite the **arg environment** the placed slice resolves against **at** the `evalModules` boundary (`_module.args` / `specialArgs`), and may **gate** the slice's resolved config on an eval-time predicate. Content rewriters (content → content, run in the pre-eval fold — gen-view's `transform.map`, and gen-edge's `adapt` before ADR-0010 §3 retired that library) structurally cannot reach that boundary — they never see `_module.args`/`specialArgs`. That is a fact about the shape of a content-to-content rewriter, so it survives the rehoming. Three primitives do reach it:

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

### The Boundary Crossing

`genBind.crossing` is the **boundary crossing** surface: the mechanism by which a substrate-resolved value enters an evaluation gen does not own. The boundary is the **eval**, not the repo — a sibling library at a different pin is a foreign eval under the same rule — and what the surface separates is *re-handing* a value from *constructing* one.

**A crossing is a NODE, not an edge.** It is the reified relation between an import declaration, a **binding**, and a consuming target. A relation that must carry content cannot be an edge, and a crossing carries content: its congruence verdict, its residue bit, its refusal witness. The middle relatum is the **binding**, never the supply — the demand set is a property of a *body*, a body is a field of a `Binding`, so one supply is an emitter of many crossings rather than a relatum of one. Making the supply the relatum would put the over-approximation back at the node, demoting every plain binding whose sibling happens to carry a producer.

**The demand relation is DERIVED, not declared.** `ReadFrom` is the one former that names a unit, and the demand set is computed by structural recursion over a closed, first-order body-term algebra:

```nix
b = genBind.crossing;

supply = {
  bindings = {
    base    = b.binding.plain  { value = { host = "igloo"; }; mark = b.mark.open; };
    derived = b.binding.termed { term = b.term.readCtx "base" [ "host" ]; mark = b.mark.open; };
    peer    = b.binding.termed { term = b.term.readFrom "iceberg" [ "networking" "hostName" ]; mark = b.mark.open; };
    opaque  = b.binding.wrapped { producer = "iceberg"; body = scope: scope.x; mark = b.mark.open; };
  };
  proposals = { };
  origins = { };
};

reg = b.registerSupply supply;   # stratifies, refuses a sibling cycle, mints the projection
reg.value.heights                # { base = 0; derived = 1; opaque = 0; peer = 0; }
reg.value.projection.peer        # { targets = [ "iceberg" ]; exact = "EXACT"; }
reg.value.projection.opaque      # { targets = [ "iceberg" ]; exact = "APPROX"; }
```

**`deltaExact` is why the recursion returns a pair and not a bare set.** A `Scoped` or `Wrapped` binding's own demand set under-approximates, and a `Termed` binding reading one **inherits that residue**. An approximating chain and an exact chain of the same shape return *identical, indistinguishable* sets, so nothing computed over the set alone can decide whether a binding is in the derived class. The exactness bit is a conjunction accumulated by the same traversal — no second walk — and it sees through `If`, so a residue-carrying arm marks the whole term `APPROX`. That is the conservative direction.

**The four binding constructors ARE the three populations**, so a binding's population is decidable from its tag and no reader classifies anything:

| Constructor | Population | Demand set |
|---|---|---|
| `plain { value; mark; }` | — | carries none; still traversed by the queries, so it carries the floor mark |
| `termed { term; mark; }` | P-A, the substrate-assembled body | **computed** from the term, total and decidable |
| `scoped { file; scope; producer; mark; }` | P-B, the file-loaded body | `{producer}`, complete on the caller-lexical channel only — the `import` channel is measured open |
| `wrapped { producer; body; mark; }` | P-C, the foreign lambda | `{producer}`, an **under-approximation**: application bounds the argument channel and nothing lexical |

`Termed` is **not** a restriction on the authoring language. An author builds the term with ordinary Nix — `map`, `listToAttrs`, computed attribute names — and all of that runs at term-construction time, leaving a term whose keys and read paths are literal by the time the analysis runs.

**The stratification is derived too.** A binding's height in the sibling-reference graph is read off the `ReadCtx` head names in the terms — a canonical *height function*, not a choice of topological order, so it is unique and invariant under the presentation order of the bindings. A `ReadCtx` resolves only against a **strictly lower** stratum, so a same-pass sibling reference cannot be named and a cycle in that channel is refused at registration and inexpressible thereafter. A **cycle across eval boundaries is a different object** and stays expressible and unattributed: the foreign evaluator's `infinite recursion`, uncatchable and carrying no name of ours.

**Placement is derived in two steps at two operations**, because its two inputs become available at different ones. `link` evaluates the congruence predicate — *does this binding demand this very target?* — over the materialized projection, forcing nothing, and records it on the node beside the residue bit. `close` resolves `(Channel, Time)` against the Adapter's offered positions. It **must not** silently downgrade a substrate-placed name to target-invoked: that is a congruence violation, not a degradation.

**Substrate placement requires an EXACT demand set, not merely a passing congruence check.** The predicate is a *negative* membership test — *is this target absent from the demand set?* — and an APPROX set under-approximates, so the true set may be larger and may contain the very target. A pass over an APPROX set therefore proves nothing, and admitting it would substitute a value before the fixpoint that determines it has run. `placement` takes both facts and refuses `substrate-placement-inexact-demand` when the second is missing. The two stay distinct on the crossing node, because collapsing *proved safe* into *could not prove* loses the witness. The visible consequence: a `scoped` or `wrapped` binding whose producer is a **peer** does not cross, since its demand set can never be exact; it crosses when its demand is the consuming target, which routes it to the target-invoked channel where the residue costs nothing.

**Access marks bound the queries, never the analysis.** A `Floor` mark terminates `crossings` and `E` at the node — those are queries, which is to say access — while the demand analysis walks straight through it. An analysis is the input a gate is trusted for, and a gate whose domain is narrower than the property it is trusted for is exactly the narrowing that makes a clean result meaningless: a Floor-marked binding demanding the consuming target would report an empty demand set, and the congruence predicate would then admit a placement the value cannot support. The price of the split is stated rather than absorbed, with the direction word stated correctly: a Floor-marked binding's cross-unit references do not enter `E(u)`, so `linked(u)` can be wrongly **true** and the coherence refusal goes blind. **On the decisions `E` feeds, that narrowing is permissive, not fail-closed** — calling it fail-closed describes the declaration rather than its effect, and the two point opposite ways. It is bounded twice. First, **the mark is not transitive**: it stops the query at the node carrying it and nowhere else, so an unmarked reader of a Floor-marked sibling puts the demanded target straight back into `E(u)`, which is the conservative direction to leak in. Second, **`close` still refuses the unit**: the placement decision reads the analysis, which is mark-blind, so the binding is still substrate-placed and still refuses `value-not-obtainable`. A unit that is linked-wrongly-true therefore cannot silently cross carrying an unresolvable reference; it fails one operation later, with a witness.

**Contracts are DATA, checked substrate-side, eagerly and completely.** The vocabulary is a closed first-order algebra carried as tagged terms and interpreted beneath it, so a contract is comparable, hashable and enumerable where a closure is none of those. The check runs *before* the value crosses and it **forces** — the only construction under which the payload contains no reachable function is one where the check has already run and the payload is the checked value. The price is stated rather than absorbed: a contract system is meaning-preserving **or** complete, not both, and this takes completeness, so a violation in a part the target would never have demanded is still reported and a fleet that succeeds today by never forcing a bad part fails under it. It is **opt-in per name** — `Any` is unconstrained said visibly and costs no forcing — so the price is paid where a contract was asked for and nowhere else. Higher-order contracts are **inadmissible**: their two contracts fire on *application*, inside the consuming target, which needs exactly the substrate closure at the installation site that the construction exists to remove.

**The operations exist only once you inject the mint.** The published surface carries the constructors and `mkOperations`; it ships **no minting formula, not even as a convenience default**, because ADR-0016 gives the substrate one minting authority and a shipped fallback would be a second one — reachable by any consumer who simply omitted the injection, with the omission invisible at the call site. `hashIdentity` is a total field: omitting it refuses by name rather than silently defaulting.

```nix
ops    = (b.mkOperations { hashIdentity = yourSubstrateMint; }).value;
frag   = ops.declare { imports = { … }; exports = { }; } body;
linked = ops.link "igloo" reg.value.projection supply frag.value;
unit   = ops.close "igloo" reg.value.projection { members = [ "igloo" "iceberg" ]; } adapter linked.value;
```

**Every failure is a tagged VALUE, never a throw** — `tryEval` cannot catch every failure form, so a thrown refusal is not reliably recoverable. Each refusal carries a `code`, the `blamed` party and a `witness`; `b.isOk` / `b.isRefusal` discriminate, and `b.codes` enumerates the vocabulary.

**Two carriers the surface deliberately does not invent.** The Adapter's opaque types — `Body`, `TargetUnit`, `TargetArgs`, `ProducerScope` — are target-owned and are produced or consumed only by an Adapter; `close` returns the TargetUnit exactly as the adapter built it and never reads its structure. Consequently the substrate cannot combine two `Body` values, so a merged multi-body fragment refuses at `close` rather than having one of its bodies silently dropped; and where a value would need a foreign scope the substrate does not hold — a `ProducerScope` for a `Wrapped` body, a target config root for a `ReadFrom` — `close` refuses by name with the missing carrier in the witness, rather than skipping the check and letting silence read as success.

### The Adapter set

`crossing-adapter.nix` defines the Adapter *type* and resolves placement; `crossing-adapter-set.nix` defines the *instances* — the concrete adapters the substrate ships. Each says what a `Body` is for its own target, which is the whole content of the type's opacity.

```nix
b.crossing.injectAdapter                                    # -> Adapter
b.crossing.mkSystemTerminal { evaluator, locateConfig }      # -> { adapter = carriage -> Adapter; locateConfig; }
b.crossing.mkFlakeTerminal { evalFlakeModule, inputs, self, systems ? [] }
                                                            # -> { adapter = Adapter; locateConfig = null; }
```

**`injectAdapter` realizes `Formals` as an ARG-ENVIRONMENT WRITER, and the choice is behavioural rather than stylistic.** Its `Body` is a module destined to be spliced into an evaluation the substrate does not own, and its `bindFormals` produces `{ imports = [ body ]; _module.args = values; }`. An arg environment reaches every module in the target's evaluation, *including modules the substrate never saw*; a formal partial-application reaches only the wrapped set, and that narrowing is invisible to any consumer whose readers happen to sit inside it. Both constructions are admissible at the same coordinate — `Channel` and `Time` are placement coordinates of the substrate's vocabulary, not names of module-system channels — so the surface states which one it takes and arms the difference with a cell.

★ **The payload this adapter places is NOT plain data, and that is a DECLARED opt-out with its price recorded.** A resolved gen fixpoint carries option-type objects, whose `check`/`merge` fields are functions, so the payload-side *provably-plain-data* predicate fails on it. The value is inert only because `_module.args` is not type-walked by the consuming module system — a consequence-based argument, which is the documented-hole form the by-construction target exists to replace. The declaration is carried at the construction site, and a consumer that routes any part of the payload into an options tree as a `type` leaves the condition under which it is safe.

**`mkSystemTerminal` realizes `Formals` as `wrapAll`'s partial application**, its `Body` being the class module list. Two things ride the closure rather than crossing as bindings, and they are named because δ cannot see them and `E(u)` cannot count them: `extraModules`, `evaluator` and `osConfig` are *scope* residues with no reach of their own; **`nodes` is a correctness residue and it is silent** — a missed edge to a peer leaves the value correct and makes `E(u)` under-report, which can render `linked(u)` wrongly true. Separately, `bindFormals` returns `wrapAll`'s `.all`, carrying the merge-collision validators into the target's module set — the collision class's **named surface**: a crossed binding shadowing a module-system value lands in the target's `warnings` channel under the retired surface's own message family (*"gen-bind: binding '\<name>' collision — bind-wins, module-system value shadowed"*). This is warn-and-proceed, not a refusal — a substrate `Refusal` stays a tagged value; the one throw a validator can raise is the per-value `_mergeStrategy = "error"` spelling, the consumer's own opt-in, raised inside the consumer's own evaluation exactly as the retired surface raised it. The price, stated: a validator defines `warnings`, so a target evaluation receiving a crossed binding must declare that option — true of every NixOS-shaped target, and the same imposition the retired surface made.

**`mkFlakeTerminal` is a NULL-POSITION adapter** — `bindFormals`, `bindArgEnv` and `wrapFn` are all `null`, which `mkAdapter` accepts, since only `wrapUnit` and `interpret` are mandatory. A collect-only flake fleet still builds; a crossing over it is **refused by name**, with the offered positions in the witness and the adapter selector blamed. This converts a silence into a witness: previously such a fleet could not receive a crossing because the function signature had nowhere to put one. **Growing an offered position onto it is a design change requiring its own ruling**, never an implementation detail — it would turn a by-construction guarantee into an as-authored one with every fixture still green.

**The evaluated-config locator is a per-terminal field, never a fixed `.config` path.** For a `nixosSystem`-shaped evaluator the config sits at `.config` *of* the artifact; for an `evalModules`-shaped data terminal the artifact *is* the config, and a fixed path silently misreads the second by reaching for `.config` of something that already is one. `locateConfig = null` says "this terminal produces no evaluated config" visibly, the same way a `null` Adapter position says one is not offered.

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
buildSignature { module; bindings; defaultMergeStrategy; mergeStrategies; provenance ? {}; vocabulary ? null; }
```

Computes a signature record: `{ requires; bound; unsatisfied; mergeStrategies }`.

- `requires` — formal args not satisfied by bindings (pass to `evalModules`)
- `bound` — `{ argName = { optional; provenance; }; }` for each injected arg
- `unsatisfied` — arg names in `vocabulary` but not injected and not optional. `vocabulary` is what a caller declares it may supply — broader than the `bindings` of a single wrap site in a layered composition. Default `null` collapses `vocabulary` to `bindings`' own keys, so with the standard API this stays `[]` (honestly — nothing outside `bindings` was ever declared as forthcoming)
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

- Binding values are never forced at `wrap` time — `builtins.functionArgs` introspects without
  evaluating, and membership in the injected attrset is value-free. Scope: on the
  partial-application branch nothing is forced until `evalModules` calls the wrapper, but on
  the fully-applied branch `.module` **is** the called module, so demanding it forces whatever
  the module body demands.
- Per-arg injection is per-key — each bound arg is injected as its own thunk, so only args the
  module actually demands are forced. Reading one binding never forces a sibling.
- Contracts fire on demand — the contract thunk wraps the binding value in an `assert`; if the
  module never demands the arg, the contract never runs. **Narrowing:** a binding that collides
  with a module-system arg is forced when `config.warnings` is demanded — see
  [Lazy Contracts](#lazy-contracts).
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

The boundary crossing (a substrate value entering an eval gen does not own)
registerSupply — stratify the sibling graph, refuse a cycle, mint the projection
  |-- strata — the canonical HEIGHT function over the ReadCtx head names
  '-- the structural recursion — (targets, exact) per binding, memoised in stratum order
declare -> merge / gate -> link -> close
  |-- declare — signature totality, closed vocabularies, satisfiedBy edges, token
  |-- merge   — export disjointness, import compatibility by structural equality
  |-- gate    — Jones's finite-enum precondition ENFORCED; branches materialized (cf. Jones 1993 §12.2)
  |-- link    — mints one crossing per name-and-binding pair; records the congruence
  |             verdict and deltaExact on the node
  '-- close   — placement against the Adapter, coherence over the Linkset, the
                substrate-side contract check, then the adapter's TargetUnit
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
  crossing.nix          — the crossing node, its identity, and declare/merge/gate/link/close/residue
  crossing-refusal.nix  — the Either carrier: refusal as a tagged value, the code and blame vocabularies
  crossing-term.nix     — the BodyTerm algebra, the InertValue minting walk, the primitive table, resolution
  crossing-binding.nix  — the four Binding constructors and the boundary mark
  crossing-delta.nix    — the derived stratification, the demand recursion, the projection, deltaExact
  crossing-contract.nix — first-order ContractTerm and its eager, complete interpreter
  crossing-adapter.nix  — the Adapter record and the placement table
  crossing-adapter-set.nix — the concrete adapters: the arg-environment writer, the system
                             terminal, the null-position flake terminal
  crossing-linkset.nix  — the fleet linkset, the cross-unit environment, coherence
```

The crossing files are **flat in `lib/`** deliberately: the `purity` suite scans `builtins.readDir lib`
and filters on the `.nix` suffix, so a subdirectory would be silently exempt from the nixpkgs-lib-free
invariant. A gate that skips a file is worse than no gate, because it reads as a pass.

## Testing

**352 tests across 22 suites** — `arg-env`, `compose`, `contract`, `crossing-adapter`,
`crossing-adapter-set`, `crossing-contract`, `crossing-delta`, `crossing-linkset`,
`crossing-operations`, `crossing-populations`, `crossing-term`, `entry`,
`evalmodules-equivalence`, `identity`, `integration`, `merge-strategy`, `provenance`, `purity`,
`signature`, `strip`, `thunk`, `wrap`. Tests use nix-unit
in `ci/` (which keeps a `nixpkgs` dependency for the test runner and the real `lib.evalModules`
driven by the production-safety equivalence gate and the `arg-env` crossing suite):

```bash
cd ci
nix run nixpkgs#nix-unit -- --flake .#tests            # all 352, across 22 suites
nix run nixpkgs#nix-unit -- --flake .#tests.wrap       # one suite
nix flake check                                        # full check incl. treefmt
```

Every refusal row of the crossing surface is armed by a planted violation **and** its conforming
control in the same suite, cells named `test-control-*`: a row whose conforming input is untested has
not been armed, and a walk that refuses everything is indistinguishable from one that works. Where an
oracle cannot be expressed as a cell the reason is measured rather than asserted — the P-B
file-import arm needs an undefined-variable error, which `tryEval` does **not** convert, so the suite
carries the live control for that claim (`tryEval` catching a `throw` in the same run) instead of a
silently absent arm.

The `purity` suite enforces the nixpkgs-lib-free Class B boundary — the library source
imports no `nixpkgs.lib` — and the `evalmodules-equivalence` suite drives gen-bind output
through a real `lib.evalModules` to prove the vendored convention helpers stay
byte-behavior-identical.

## Theoretical Foundations

gen-bind's design draws on seven papers. Each is either **implemented** (the paper's formalism directly shapes the code) or **informed by** (the paper's concepts influenced the approach without direct implementation).

### Implements

| Feature | Paper | Relationship |
|---------|-------|-------------|
| Blame tracking | Findler & Felleisen -- [*Contracts for Higher-Order Functions*](https://www2.ccs.neu.edu/racket/pubs/icfp2002-ff.pdf) (ICFP 2002) | Provenance metadata plays the role of Findler's blame labels: when a contract fires or a collision is detected, the error message identifies the guilty party (binding source, scope rule) via the same covariant/contravariant blame assignment structure (cf. Findler 2002 S2.3). |
| Lazy contracts | Chitil -- [*Practical Typed Lazy Contracts*](https://kar.kent.ac.uk/30790/1/contacts.pdf) (ICFP 2012) | Contracts are partial identities (`assert c` is less than or equal to `id` -- Chitil 2012 S4.2) that fire on demand. gen-bind contracts wrap binding values in exactly this pattern: the assertion thunk is never forced unless the consuming module demands the arg (cf. Chitil 2012 S2). |
| Module signatures | Cardelli -- [*Program Fragments, Linking, and Modularization*](http://lucacardelli.name/Papers/Linking.A4.pdf) (POPL 1997) | gen-bind's `signature.requires` and `signature.bound` are a lightweight analog of Cardelli's linkset interfaces: each compilation unit (wrapped module) declares what it provides (bound args) and what it still needs (requires from evalModules). Identity wrapping implements Cardelli's fragment naming for dedup (cf. Cardelli 1997 S5). |
| Crossing fleet linkset | Cardelli -- *Program Fragments, Linking, and Modularization* (POPL 1997) | `crossing.mkLinkset`/`coherence` impose Cardelli's two disjointness clauses directly: `imp(L)` intersect `exp(L)` is empty (Definition 5-2) at `declare`, and `exp(L)` intersect `exp(L')` is empty (Definition 5-7's precondition) at `merge`. What transfers to `E(u)` is the **containment condition**, not the `dom` operator -- Cardelli's environment is one of `x:A` bindings and `E(u)` is a set of target identities, so the operator would be a borrowed notation on an object where it has no meaning. Theorem 7-6 is deliberately **not** cited as a licence: its hypotheses are F1 typing derivations this setting cannot supply. |
| Defunctionalized contracts and bodies | Reynolds -- [*Definitional Interpreters for Higher-Order Programming Languages*](https://dl.acm.org/doi/10.1145/800194.805852) (1972) | `ContractTerm` and `BodyTerm` are Reynolds' transformation applied twice: a set of functions becomes a set of records interpreted by an `apply`-style function beneath the algebra. That is what makes a contract comparable, hashable and enumerable, and what makes a body's demand set analysable at all. Reynolds labels his own justification informal and states **no completeness theorem**, so the claim that a closed former vocabulary covers the authored corpus is gen-bind's argument and not his. |
| Eager complete contracts | Chitil -- *Practical Typed Lazy Contracts* (ICFP 2012) S8 | The crossing surface deliberately takes the **opposite** arm of the result Chitil reports from Degen, Thiemann and Wehr: a contract system is meaning-preserving **or** complete, not both. Crossing contracts are checked substrate-side and eagerly, so a violation is reported even in a part the target would never have demanded. Chitil's Lemma 4.1 (`assert c` is less than or equal to `id`) is **not** offered as mitigation -- it is stated over an order whose least element represents both non-termination and a violated contract, so it admits that loss rather than excluding it. The paper's function combinator `(>->)` is refused by name, because its contracts fire on application inside the consumer. |
| Gate finite-enum precondition | Jones, Gomard & Sestoft -- *Partial Evaluation and Automatic Program Generation* (1993) S12.2 | "The Trick" applies when a dynamic variable is known to assume one of a finite set of statically computable values. gen-bind treats that as a **precondition to enforce**, not a conclusion to inherit: a gate whose `enum` is not finite and determined before any target fixpoint is refused at `declare`. With it enforced every branch is materialized, so the declared edge set is the union over branches unconditionally and no conditional edge is written. |

### Informed by

| Feature | Paper | Relationship |
|---------|-------|-------------|
| Closure-based binding | Reynolds -- [*Definitional Interpreters for Higher-Order Programming Languages*](https://dl.acm.org/doi/10.1145/800194.805852) (1972) | Reynolds' closure environments inform the approach but gen-bind's wrapping is partial application, not defunctionalization per se. `builtins.functionArgs` is the Nix analogue of formal parameter reflection in a definitional interpreter (cf. Reynolds 1972 S4). |
| Merge resolution | Leijen -- [*Extensible Records with Scoped Labels*](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/scopedlabels.pdf) (TFP 2005) | Leijen's free extension (retaining duplicate labels with scoped resolution) informs the merge strategy vocabulary: `bindWins` shadows like Leijen's first-match selection; `error` mirrors strict extension where duplicates are rejected (cf. Leijen 2005 S2). gen-bind uses flat `//` rather than row-typed scoping. |
| Remote attribute reference | Soderberg & Hedin -- *Circular Higher-Order Reference Attribute Grammars* (2013) S5.1, S7 | Supplies the **remote reference** reading that `lib/thunk.nix` already uses -- a deferred value is an attribute whose value refers to a node in another unit's context. Its circular-NTA well-definedness apparatus has **no live case** in the crossing: a substrate-internal deferred cycle is inexpressible rather than detected, so there is no cycle to accept and no fixpoint-from-bottom iteration to bound. The undecidability of static circularity detection under remote attribute access is **Boyland's** result (*Remote attribute grammars*, J. ACM 52(4), 2005), which Soderberg & Hedin S7 cites rather than produces; the attribution belongs to Boyland. |

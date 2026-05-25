# gen-bind

Module binding with external arguments for Nix — partial application of bindings into NixOS module functions with signature-directed injection, collision detection with blame, lazy contracts, and thunk resolution for config-dependent values.

gen-bind gives you what manual `specialArgs` doesn't: `builtins.functionArgs` introspection to inject only the args a module actually declares, merge strategy control when bindings collide with module-system args, contract assertions that fire on demand rather than at wrap time, and provenance tracking that names the source in every error message.

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

## Gen Ecosystem

| Library | Role |
|---------|------|
| [gen](https://github.com/sini/gen) | Pure primitives (search, record, identity) |
| [gen-schema](https://github.com/sini/gen-schema) | Typed registries (kinds, instances, collections, refs) |
| [gen-aspects](https://github.com/sini/gen-aspects) | Aspect types (traits, classification, dispatch) |
| [gen-graph](https://github.com/sini/gen-graph) | Graph queries (combinators, traversals, fixpoint) |
| [gen-scope](https://github.com/sini/gen-scope) | Scope graphs (construction, evaluation, resolution) |
| **[gen-bind](https://github.com/sini/gen-bind)** | **Module binding (wrapping, contracts, collision detection)** |

## Quick Start

### As a flake input

```nix
# flake.nix
{
  inputs.gen-bind.url = "github:sini/gen-bind";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { gen-bind, nixpkgs, ... }:
    let
      bindLib = gen-bind.lib;
      # or: bindLib = import ./path/to/gen-bind/nix/lib { lib = nixpkgs.lib; };
    in {
      # Wrap a module with external bindings
      wrappedModule = (bindLib.wrap {
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
  bindLib = import ./path/to/gen-bind/nix/lib { inherit lib; };
  result = bindLib.wrap {
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
  bindLib = import ./path/to/gen-bind/nix/lib { inherit lib; };
in
# use bindLib.wrap, bindLib.wrapAll, bindLib.contract, etc.
```

## Core Concepts

### Bindings and Wrapping

`wrap` inspects a module's formal parameters via `builtins.functionArgs` and injects only the bindings that match. Non-matching bindings are ignored. The result is a partially-applied module whose remaining args come from `evalModules` as normal.

```nix
result = bindLib.wrap {
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
result = bindLib.wrap {
  module = { lib, host, ... }: { networking.hostName = host.name; };
  bindings = { host = { name = "igloo"; }; lib = myCustomLib; };
  mergeStrategies = {
    lib = bindLib.mergeStrategy.systemWins;  # module-system lib wins
    # or: bindLib.mergeStrategy.bindWins (default)
    # or: bindLib.mergeStrategy.error (throw at eval time)
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
result = bindLib.wrap {
  module = { extraModules, config, ... }: {
    imports = extraModules;
  };
  bindings = {
    extraModules = [
      # Static entry
      myBaseModule
      # Thunk — resolved when evalModules calls the wrapper
      (bindLib.mkThunk ({ config }: lib.optional config.services.nginx.enable nginxExtraModule))
    ];
  };
};
```

Thunks travel as markers (`{ __configThunk = true; __fn = fn; }`) through the binding pipeline and resolve inside the module wrapper when `evalModules` provides `config`. Only list-valued bindings are auto-detected for thunks. Non-list bindings with thunks require explicit `thunkBindings = [ "argName" ]`.

`mkThunkFrom scopeId fn` creates a thunk annotated with a source scope for tracing.

### Lazy Contracts

Contracts are assertions that fire only when the bound value is demanded — preserving Nix's lazy evaluation semantics. Unbuilt modules have zero contract cost.

```nix
result = bindLib.wrap {
  module = { host, ... }: { networking.hostName = host.name; };
  bindings = { host = { name = "igloo"; }; };
  contracts = {
    host = bindLib.contract.hasFields [ "name" "system" ];
    # or: bindLib.contract.isType "set"
    # or: bindLib.contract.nonEmpty
    # or: bindLib.contract.mk { check = v: v.name != ""; message = "host must have non-empty name"; }
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
bindLib.wrap {
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
# → {
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
allBindings = bindLib.compose [
  entityBindings
  enrichmentBindings
  pipeBindings
];

# composeWith: structured merge across all binding fields
cfg = bindLib.composeWith [
  { bindings = entityBindings; provenance = entityProv; }
  { bindings = enrichBindings; contracts = enrichContracts; }
  { bindings = pipeBindings; mergeStrategies = pipeStrats; }
];
# cfg.bindings, cfg.provenance, cfg.contracts, cfg.mergeStrategies — all merged

result = bindLib.wrap (cfg // { module = myModule; });
```

### Identity Wrapping

NixOS deduplicates modules by `key`. `wrapIdentity` stamps a stable key onto a wrapped module so that re-emitting the same module at the same identity doesn't duplicate it in `evalModules`:

```nix
keyed = bindLib.wrapIdentity {
  class = "nixos";
  module = result.module;
  identity = "host=igloo";
  # isAnon = false;  # default: sets key + _file + imports wrapper
};
# keyed → { key = "nixos@host=igloo"; _file = "nixos@host=igloo"; imports = [ result.module ]; }
```

Set `isAnon = true` to use `lib.setDefaultModuleLocation` instead — useful for anonymous modules that shouldn't appear in `key`-based dedup.

### Arg Stripping

After wrapping, binding arg names must be removed from the module's advertised args. Otherwise `evalModules` probes `_module.args.<name>` for every advertised arg and crashes when the key doesn't exist.

```nix
stripped = bindLib.stripBindingArgs {
  module = result.module;
  bindingNames = [ "host" ];
};
```

Works on both function modules and attrset modules with `__functionArgs`. Args not present in the module's advertised interface are silently skipped.

### Batch Wrapping

`wrapAll` wraps a list of modules with shared bindings, pre-computing contracts once across all modules:

```nix
batch = bindLib.wrapAll {
  modules = [ modA modB modC ];
  bindings = sharedBindings;
  contracts = sharedContracts;
  provenance = sharedProv;
};

# batch.modules    — list of wrapped modules
# batch.validators — list of non-null validators (one per wrapped function module)
# batch.signatures — list of signatures (one per module)
# batch.all        — full result records (module + wrapped + validator + signature)
```

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

### `mkThunk`

```nix
mkThunk fn
```

Creates a config-dependent thunk. `fn` receives `{ config; <ctx-args>... }` — `ctx-args` are any of `fn`'s named parameters that exist in the module call context. The return value is spliced into the list binding (single value or list both work).

### `mkThunkFrom`

```nix
mkThunkFrom scopeId fn
```

Like `mkThunk` but annotates the thunk with a source scope string for tracing.

### `isThunk`

```nix
isThunk value  # → bool
```

Returns `true` if `value` is a thunk created by `mkThunk` or `mkThunkFrom`.

### `resolveThunks`

```nix
resolveThunks { config; ctx; thunkArgNames; bindings; }
```

Resolves thunks within list-valued bindings. For each arg name in `thunkArgNames` whose binding is a list, expands thunk entries by calling `__fn` with `config` and matching `ctx` args. Non-thunk entries and non-list args pass through unchanged.

### `contract.mk`

```nix
contract.mk { check; message ? "contract violation"; blame ? null; }
```

Creates a contract. `check` is `value → bool`. `blame` is an optional string added to the error message.

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
# → { name = strategy | null; } — extracts _mergeStrategy annotations from binding values
```

### `mkMergeValidator`

```nix
mkMergeValidator { resolvePolicy; boundArgNames; provenance; }
```

Returns a validator function `moduleArgs → { warnings }`. Call with the module args attrset (including `config._module.args`) to check for collisions. Error-strategy collisions throw immediately (`builtins.seq` forces the check list to WHNF). Bind-wins and system-wins collisions produce warning strings in `.warnings`.

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

Stamps a stable NixOS module key onto a module. Non-anon: returns `{ key = "${class}@${identity}"; _file = ...; imports = [ module ]; }`. Anon: calls `lib.setDefaultModuleLocation` instead.

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

## Laziness Guarantees

- Binding values are never forced at `wrap` time — `builtins.functionArgs` introspects without evaluating.
- Per-arg injection uses `//` semantics — only args the module actually demands are forced.
- Contracts fire on demand only — the contract thunk wraps the binding value in an `assert`; if the module never demands the arg, the contract never runs.
- Unbuilt hosts have zero cost — thunks in list bindings resolve only when the wrapper function is called by `evalModules`.

## Academic Foundations

| Feature | Paper |
|---------|-------|
| Signature-directed binding | [Reynolds — *Definitional Interpreters for Higher-Order Programming Languages* (1972)](https://dl.acm.org/doi/10.1145/800194.805852) — deferred evaluation via closure inspection; `builtins.functionArgs` is the Nix analogue of formal parameter reflection |
| Blame tracking | [Findler & Felleisen — *Contracts for Higher-Order Functions* (ICFP 2002)](https://www2.ccs.neu.edu/racket/pubs/icfp2002-ff.pdf) — blame assignment identifies the guilty party; provenance metadata plays the same role in gen-bind |
| Lazy contracts | [Chitil — *Practical Typed Lazy Contracts* (ICFP 2012)](https://kar.kent.ac.uk/30790/1/contacts.pdf) — contracts as partial identities (`assert c ⊑ id`) that fire on demand; gen-bind contracts wrap binding values in the same pattern |
| Merge resolution | [Leijen — *Extensible Records with Scoped Labels* (TFP 2005)](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/scopedlabels.pdf) — first-wins selection and strict-extension rejection; `bindWins` and `error` strategies implement these two modes |
| Module signatures | [Cardelli — *Program Fragments, Linking, and Modularization* (POPL 1997)](http://lucacardelli.name/Papers/Linking.A4.pdf) — linksets carry `requires`/`provides` interfaces; gen-bind's `signature.requires` and `signature.bound` are a lightweight analog |
| Constructor injection | [Bracha & Ungar — *Mirrors: Design Principles for Meta-level Facilities of Object-Oriented Programming Languages* (OOPSLA 2004)](https://bracha.org/mirrors.pdf) — pluggable composition via partial application; `wrap` is a mixin combinator that partially applies external bindings while preserving the module's remaining interface |

## Architecture

```
External bindings (entity context, enrichment, pipes)
  ↓ composed via
compose / composeWith
  ↓ applied via
wrap / wrapAll
  ├── builtins.functionArgs — inspect module signature
  ├── applyContracts — lazy assertion wrapping (Chitil 2012)
  ├── resolvePolicy — per-arg merge strategy dispatch (Leijen 2005)
  ├── detectThunkArgs — identify config-dependent list bindings
  └── wrapFunctionModule / wrapImportsModule / passthrough
        ↓ result
      { module; wrapped; validator; signature; advertisedArgs }
        ↓ optional post-processing
      wrapIdentity — NixOS key stamping (Cardelli 1997)
      stripBindingArgs — formal arg cleanup (Reynolds 1972)
      mkMergeValidator — collision detection with blame (Findler 2002)
```

### File Layout

```
nix/lib/
  default.nix        — public API surface
  wrap.nix           — core wrapping logic (wrapCore, wrapAllCore)
  merge-strategy.nix — collision detection and merge validator
  contract.nix       — lazy binding contracts (mk, hasFields, isType, nonEmpty, apply)
  thunk.nix          — config thunk primitives (mkThunk, mkThunkFrom, isThunk, resolveThunks)
  provenance.nix     — blame formatting
  compose.nix        — layered composition (compose, composeWith)
  identity.nix       — NixOS module identity wrapping
  strip.nix          — binding arg stripping for NixOS compatibility
  signature.nix      — module signature inference
```

## Testing

Tests use nix-unit in `templates/ci/`:

```bash
cd templates/ci
nix develop --override-input gen-bind ../.. -c nix-unit \
  --override-input gen-bind ../.. --flake .#.tests
```

## License

MIT

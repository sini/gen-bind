# gen-bind — agent capability sheet

## Scope

Partial application of external bindings into Nix module functions: inspects a module's formal parameters (`builtins.functionArgs`), injects matching bindings, and re-advertises the residual interface in the nixpkgs `__functionArgs`/`_file` convention — plus three primitives that rewrite the arg environment *at* an `evalModules` crossing.

## Not this library's job

Quoted text is the owner's own `flake.nix` `description` field, verbatim.

| Responsibility | Owner |
|---|---|
| Running `evalModules`, merging config values, option types | Not gen-bind — the terminal threads its evaluator in as `lib` (`crossEval` takes `lib` as a parameter; `adaptArgs`/`configGate` read `args.lib`). The pure-gen stack's own engine is `gen-merge` — "gen-merge — pure-Nix byte-mode module MERGE engine (evalModuleTree) for the pure-gen module system"; `ci/tests/evalmodules-equivalence.nix` drives gen-bind output through nixpkgs' `lib.evalModules` |
| General utilities (`genAttrs`, `optionalString`) | `gen-prelude` — "gen-prelude: vendored, nixpkgs-lib-free pure utilities for the gen ecosystem". gen-bind's *only* dependency (`flake.nix` `inputs`) |
| Type checking / structural verification | `gen-types` — "gen-types: pure, nixpkgs-lib-free structural type checker for the gen ecosystem". gen-bind contracts are runtime predicates (`check : v -> bool`), not types |
| Rewriting module CONTENT as it moves across a delivery edge | `gen-edge` — "gen-edge — the content-movement contract: the (S,T,P,M) edge algebra, toposorted materialization fold, and the frozen edge-trace parity oracle". `lib/arg-env.nix` header states gen-edge `adapt` rewriters "structurally cannot reach that boundary — they never see `_module.args`/`specialArgs`" |
| Choosing WHICH module a binding set applies to | `gen-dispatch` — "gen-dispatch: relational rule dispatch over ordered groups (the dispatch STEP)" |
| Naming the graph positions a rule matches | `gen-select` — "gen-select: selector algebra for attributed graph positions" |
| Evaluating the scope graph that computes binding values | `gen-scope` — "gen-scope: demand-driven attribute grammar evaluator over algebraic scope graphs" |
| Precedence / stratified layering of settings | `gen-settings` — "gen-settings — stratified settings resolution as a pure layered fold, with refs-as-data, structured provenance, and the graduated injection construct". gen-bind's `compose`/`composeWith` are plain `//` folds with no precedence semantics; `gen/lib/mkGenLibs.nix` records gen-settings' deps as `prelude+algebra+bind` (gen-settings CONSUMES gen-bind) |
| Class partition/gating (note the name collision with gen-bind's `contract` and `configGate`) | `gen-class` — "gen-class — pure-Nix class-share mechanism (partition / contract / apply / gate) for the pure-gen module system" |
| Minting identity — gen-bind's `wrapIdentity` takes the identity STRING from the caller and only formats `"${class}@${identity}"` | `gen-schema` — "gen-schema: typed record registry with extension points for the pure-gen module system" |
| Channels/dataflow that PRODUCE the config-thunk payloads gen-bind resolves | `gen-pipe` — "gen-pipe — scoped channels + dataflow algebra (map/filter/fold/scan/route/join/tee) with B5 determinism, provenance, dedup, and class-aware contributions" |
| Flake-level composition boundary | `gen-flake` — "gen-flake — the pure composition boundary of the pure-gen module ecosystem" |
| Constructing the `bindings` attrset itself — gen-bind receives it opaque | UNKNOWN on this pass |
| Building the `producerConfigs` scopeKey→config map — `lib/thunk.nix` states "the caller (e.g. den-hoag) builds the map" | UNKNOWN (consumer-side, not a gen sibling on this evidence) |

## Exports

Entry: `inputs.gen-bind.lib` (flake). Root `default.nix` is a FUNCTION `{ prelude ? <derived from flake.lock>, ... } -> lib`; `import ./lib` is `{ prelude } -> lib` with `prelude` required. The flake output and the zero-arg `import ./gen-bind { }` yield the same value.

**Wrapping** — `lib/wrap.nix`

| Export | Signature |
|---|---|
| `wrap` | `cfg -> result` (`cfg.module` required) |
| `wrapAll` | `cfg -> batch` (`cfg.modules : [module]`) |

`cfg` keys (both): `module`/`modules` · `bindings ? {}` · `contracts ? {}` · `provenance ? {}` · `mergeStrategies ? {}` · `defaultMergeStrategy ? "bind-wins"` · `thunkBindings ? null` · `producerConfigs ? {}`.

`result` (returned, not exported): `{ module; wrapped; validator; signature; advertisedArgs; }`.
`batch` (returned, not exported): `{ modules; validators; signatures; all; }` where `all = modules ++ validators`.

**Config thunks** — `lib/thunk.nix`

| Export | Signature |
|---|---|
| `mkThunk` | `fn -> { __configThunk = true; __fn; __sourceScope = null; }` |
| `mkThunkFrom` | `scopeId -> fn -> thunk` (stamps `__sourceScope`) |
| `isThunk` | `v -> bool` (`isAttrs v && v ? __configThunk`) |
| `resolveThunks` | `{ config, ctx, thunkArgNames, bindings, producerConfigs ? {} } -> bindings` |

**Contracts** — `lib/contract.nix`

| Export | Signature |
|---|---|
| `contract.mk` | `{ check, message ? "contract violation", blame ? null } -> contract` |
| `contract.hasFields` | `[string] -> contract` |
| `contract.isType` | `string -> contract` (compares `builtins.typeOf`) |
| `contract.nonEmpty` | `contract` (a value, not a function) |
| `contract.apply` | `contract -> value -> prov -> value` (throws on failure) |

**Merge strategy** — `lib/merge-strategy.nix`

| Export | Signature |
|---|---|
| `mergeStrategy.bindWins` / `.systemWins` / `.error` | `"bind-wins"` / `"system-wins"` / `"error"` |
| `mergeStrategy.fromBindings` | `bindings -> { <name> = strategy \| null; }` |
| `mkMergeValidator` | `{ resolvePolicy : name -> strategy, boundArgNames, provenance } -> moduleArgs -> { warnings; }` |

**Provenance** — `lib/provenance.nix`

| Export | Signature |
|---|---|
| `provenance.format` | `{ source, scope ? null } \| null -> string` |

**Composition** — `lib/compose.nix`

| Export | Signature |
|---|---|
| `compose` | `[attrset] -> attrset` (`foldl' //`) |
| `composeWith` | `[{ bindings?, provenance?, contracts?, mergeStrategies? }] -> { bindings; provenance; contracts; mergeStrategies; }` |

**Module metadata** — `lib/identity.nix`, `lib/strip.nix`, `lib/signature.nix`

| Export | Signature |
|---|---|
| `wrapIdentity` | `{ class, module, identity, isAnon ? false } -> module` |
| `stripBindingArgs` | `{ module, bindingNames } -> module` |
| `buildSignature` | `{ module, bindings, defaultMergeStrategy, mergeStrategies, provenance ? {} } -> { requires; bound; unsatisfied; mergeStrategies; }` |

**Terminal-crossing arg-env** — `lib/arg-env.nix`

| Export | Signature |
|---|---|
| `adaptArgs` | `{ adapt, module } -> crossingArgs -> { imports; _module.args; }` |
| `crossEval` | `{ lib, module, specialArgs ? {}, moduleArgs ? null, absorb ? true } -> evalResult` (read `.config`) |
| `configGate` | `{ gate, module, adapt ? (_: {}), absorb ? true } -> crossingArgs -> { config; }` |

**Not exported**: `lib/module-convention.nix` (`setFunctionArgs`, `setDefaultModuleLocation`) is vendored byte-for-byte from nixpkgs and reachable only through `wrap`/`stripBindingArgs`/`wrapIdentity`.

## Entry points by task

| Task | Reach for |
|---|---|
| Inject external args into one module function | `wrap { module; bindings; }`, then read `.module` |
| Same across a module list, sharing contract thunks | `wrapAll { modules; bindings; }`, then read `.all` |
| Defer a binding value until `config` exists | `mkThunk fn`, passed as a **list** element |
| Resolve a value against the config of the terminal that EMITTED it | `mkThunkFrom scopeKey fn` + `producerConfigs.<scopeKey>` |
| Validate a binding value on demand | `contracts.<name> = contract.isType "…"` (see the laziness trap) |
| Decide who wins when a binding name collides with a module-system arg | `mergeStrategies.<name>` = `"bind-wins"` / `"system-wins"` / `"error"` |
| Surface collisions as `config.warnings` | include `wrapAll`'s `.validators` (or `.all`) as top-level modules |
| Attribute a violation to a source | `provenance.<name> = { source; scope; }` |
| Merge binding layers | `compose` (bindings only) / `composeWith` (all four fields) |
| Give a module a dedup key | `wrapIdentity { class; identity; module; }` |
| Inspect what a module still needs from `evalModules` | `.signature.requires` |
| Add args visible to SIBLING modules at a crossing | `adaptArgs` (writes `_module.args`) |
| Set `specialArgs` for a placed slice | `crossEval` (owns the nested `evalModules`) |
| Conditionally contribute a slice's config | `configGate` |

## Measured traps

Each row verified in this run by evaluating against the flake `.lib` (`b`). Shared fixtures: `blind = { a, config }: { untouched = "no read of a"; }` (never reads `a`); `failing = b.contract.isType "string"` against binding `a = 1`; `apply r = r.module.__functor r.module { config = {}; }`; `okD e = (builtins.tryEval (builtins.deepSeq e e)).success`.

| Trap | Evidence |
|---|---|
| `wrap` returns a RECORD, not a module — passing it to `imports` is wrong | `builtins.attrNames (wrap {…})` ⇒ `["advertisedArgs","module","signature","validator","wrapped"]` |
| A partially-applied result is **not** `builtins.isFunction` — it is `{ __functor; __functionArgs; }` | `builtins.isFunction .module` ⇒ `false`; `attrNames` ⇒ `["__functionArgs","__functor"]`. Positive control, same run: that value driven through a real `lib.evalModules` resolves ⇒ `"igloo"`. Suite: `ci/tests/evalmodules-equivalence.nix` |
| `stripBindingArgs` on a raw function likewise returns an attrset | `isFunction` ⇒ `false`, `attrNames` ⇒ `["__functionArgs","__functor"]`. Positive control: nothing to strip ⇒ `isFunction` ⇒ `true`. Tests: `test-strips-from-raw-function`, `test-noop-when-nothing-to-strip` |
| `...` is not a formal, so `{ ch, ... }` with `ch` bound counts as FULLY matched — the module is **called at wrap time** and `.module` is a plain attrset | `builtins.functionArgs ({ a, ... }: null)` ⇒ `{"a":false}`; `wrap { module = { ch, ... }: { got = ch; }; bindings.ch = 7; }` ⇒ `wrapped=true`, `isAttrs=true`, `__functor` absent, `advertisedArgs={}`, `.module.got=7`. Positive control: adding an unbound formal `other` ⇒ `__functor` present, `advertisedArgs=["other"]`. Tests: `test-function-fully-applied`, `test-function-partial-application` |
| ★ `configGate` gates CONFIG via `mkIf`; it never emits `imports` | `attrNames (configGate {…} { inherit lib; })` ⇒ `["config"]`, `.config._type` ⇒ `"if"`, `.config.condition` tracks the gate (`false`/`true`). Contrast `adaptArgs` ⇒ `["_module","imports"]`, unconditional. Sole `mkIf` call site in `lib/`; every `imports = [ … ]` in `lib/` is unconditional. Tests: `test-configGate-true-contributes-config`, `test-configGate-false-suppresses-config`, `test-configGate-cannot-declare-option-in-outer` |
| A **false** gate under a freeform absorber leaves the key DECLARED but valueless — reading it throws, it is not absent | `config ? opaqueKey` ⇒ `true`, `elem "opaqueKey" (attrNames config)` ⇒ `true`, `okD config.opaqueKey` ⇒ `false`; error: `` The option `opaqueKey' was accessed but has no value defined. Try setting the option. `` Positive control: a sibling module defining the same key ⇒ `"from-sibling"`, and gate-true ⇒ `"landed"` |
| ★ Contracts are **not** deferred to arg demand by default: merely APPLYING the wrapper fires them, even for a module that never reads the arg | with `blind` + `failing`: `okD (apply (wrap {…}))` ⇒ `false`. `resolvePolicy` forces the binding to WHNF (`isAttrs (bindings.${name} or null)`, `lib/merge-strategy.nix` path in `lib/wrap.nix`) and `detectThunkArgs` forces it again (`builtins.isList v`). Suppressing BOTH restores laziness: `mergeStrategies.a` alone ⇒ `false`; `thunkBindings = []` alone ⇒ `false`; **both** ⇒ `true`. Instrument live: with both set and the arg actually read ⇒ `false` (still armed); with both set and a PASSING contract ⇒ `true` |
| Setting `thunkBindings` at all disables auto-detection — naming an arg that is not bound silently leaves real thunks unresolved | `thunkBindings = [ "notAnArg" ]` with a genuine list-thunk binding ⇒ the delivered value is still a thunk (`isThunk` ⇒ `true`) |
| Thunk auto-detection fires only on **list**-valued bindings — a bare `mkThunk` binding passes through unresolved | bare thunk ⇒ `isThunk out` `true`, `isInt out` `false`. Positive control: same thunk wrapped in a list ⇒ `[42]`. Test: `test-resolveThunks-resolves-list` |
| `resolveThunks` is a `concatMap`: a thunk returning a list is SPLICED, a scalar is wrapped in a singleton, non-thunk entries pass through | `[ listThunk scalarThunk "plain" ]` ⇒ `[1,2,42,"plain"]`. Args outside `thunkArgNames`, and non-list values, are returned untouched (`untouched`/`scalar` still `isThunk` ⇒ `true`). Test: `test-resolveThunks-skips-non-thunk-args` |
| A producer scope key must be a **string**; a non-string or unregistered key falls back to the consumer config **silently** | `producerConfigs.P` hit ⇒ `["producer"]`; unknown key `P` with only `OTHER` supplied ⇒ `["consumer"]`; `mkThunkFrom { structured = true; }` ⇒ `["consumer"]`. Tests: `test-resolveThunks-producer-scoped-reads-producer-config`, `test-resolveThunks-unknown-scope-falls-back-to-consumer`, `test-resolveThunks-non-string-scope-falls-back` |
| ★ `signature.mergeStrategies` reports the **declared** strategy, not the effective one — a binding's own `_mergeStrategy` annotation is honoured at runtime but omitted from the signature | binding `a = { _mergeStrategy = "system-wins"; v = 1; }`: `signature.mergeStrategies.a` ⇒ `"bind-wins"` while the evalModules-supplied value actually wins ⇒ `"SYSTEM"`. Positive control: no annotation ⇒ signature `"bind-wins"` AND the binding wins. `resolvePolicy` reads the annotation, `buildSignature` reads only the `mergeStrategies` cfg |
| `signature.unsatisfied` is structurally always `[]` — its predicate is `inVocabulary && !isBound`, and both sides test the same attrset | observed `[]` with `bindings = { a = 1; neverAFormal = 2; }`. Instrument live in the same call: `requires` ⇒ `["config","lib"]`, `bound` ⇒ `["a"]` |
| The merge validator is inert unless `moduleArgs.config._module.args` carries a real value — an `error` strategy applied to `{}` warns nothing | `error` strategy, `{ config._module.args = {}; }` ⇒ `warnings = []`; bare `{}` ⇒ `warnings = []`. Test: `test-validator-no-collision-no-warnings` |
| An `error` strategy throws only when `config.warnings` is FORCED, not at validator construction or application | `attrNames (v { config._module.args.a = "collide"; })` ⇒ `["warnings"]` (no throw), `okD .warnings` ⇒ `false`. Positive control, bind-wins: `["gen-bind: binding 'a' collision — bind-wins, module-system value shadowed"]`. Test: `test-validator-error-throws` |
| `"system-wins"` on the fully-applied path still injects the binding — there is no module-system value to lose | `wrap { module = { a }: { out = a; }; bindings.a = "BINDING"; mergeStrategies.a = "system-wins"; }` ⇒ `.module.out` = `"BINDING"`. Positive control on the partial path with `a = "SYSTEM"` supplied ⇒ `"SYSTEM"`; bind-wins on the same shape ⇒ `"BINDING"` |
| The `{ imports = [ … ]; }` form propagates only the FIRST sub-validator; the rest are dropped | two wrappable imports ⇒ `validator` is a single non-null value (`isList` ⇒ `false`, `== null` ⇒ `false`). `wrapAll` over the same two modules ⇒ `validators` length `2`, `all` length `4`. Tests: `test-imports-recursion`, `test-wrapAll-all-length-equals-modules-plus-validators` |
| `composeWith` rejects an unknown layer key with an error `builtins.tryEval` **cannot catch** | `tryEval (composeWith [ { extra = 1; } ])` propagates: `error: function 'anonymous lambda' called with unexpected argument 'extra'`. Positive control: `composeWith [ { bindings.a = 1; } ]` ⇒ `okD` `true`. The four-field destructure in `lib/compose.nix` has no `...` |
| `crossEval` without `lib` fails the same uncatchable way | `tryEval (crossEval { module = {}; })` propagates: `error: function 'crossEval' called without required argument 'lib'` |
| `crossEval` with `absorb = false` cannot land opaque keys | `okD (crossEval { inherit lib; module = { opaqueKey = "landed"; }; absorb = false; }).config` ⇒ `false`. Positive control, default `absorb = true` ⇒ `"landed"`. Test: `test-crossEval-freeform-absorbs-opaque-keys` |
| `compose` is a shallow `//` — a nested attrset is REPLACED, not merged | `compose [ { a.x = 1; } { a.y = 2; } ]` ⇒ `{"a":{"y":2}}` (`x` gone). Test: `test-later-shadows-earlier` |
| `contract.nonEmpty` is a value; the other constructors are functions | `isFunction contract.nonEmpty` ⇒ `false`, `isFunction contract.isType` ⇒ `true`; `attrNames` ⇒ `["__contract","blame","check","message"]` |
| `wrapIdentity` with `isAnon = true` emits **no** `key` | anon ⇒ `["_file","imports"]`; named ⇒ `["_file","imports","key"]`, `key` = `"nixos@host=igloo"`. Tests: `test-anon-uses-setDefaultModuleLocation`, `test-named-produces-key-and-file` |
| A no-match wrap is a passthrough that still advertises the module's full arg set | `bindings = { zzz = 1; }` against `{ config, lib }` ⇒ `wrapped=false`, `validator=null`, `advertisedArgs=["config","lib"]`. A plain attrset module ⇒ `wrapped=false`, module returned unchanged. Tests: `test-function-passthrough-no-match`, `test-attrset-passthrough`, `test-validator-null-on-passthrough` |
| `configGate`'s `adapt` reaches the NESTED eval as `_module.args`, not the outer one | gate true + `adapt = _: { injected = "ADAPTED"; }` ⇒ outer `config.echoed` = `"ADAPTED"`. Test: `test-configGate-adapt-threads-into-nested-eval` |

## Theory

Claimed in `README.md` §Theoretical Foundations, which splits its sources into **Implements** and **Informed by**, and restated in `lib/` code comments.

**Implements**

- **Findler & Felleisen (2002), *Contracts for Higher-Order Functions*** — provenance metadata plays the blame-label role; a firing contract or detected collision names the guilty party (`lib/provenance.nix`, `lib/contract.nix`, `mkMergeValidator`; README cites §2.3).
- **Chitil (2012), *Practical Typed Lazy Contracts*** — contracts as partial identities (`assert c ⊑ id`) applied through `genAttrs`; `wrapAll` shares one contracted-binding set across all modules (`lib/contract.nix` `apply`, `lib/wrap.nix` `applyContracts`). See the laziness trap for where the realized behaviour departs from the on-demand claim.
- **Cardelli (1997), *Program Fragments, Linking, and Modularization*** — `signature.requires`/`signature.bound` as a linkset interface (§2-3, `lib/signature.nix`); `wrapIdentity` as fragment naming for dedup (§3, `lib/identity.nix`); the arg environment as the LINKSET a fragment resolves free names against, with `adaptArgs`/`crossEval` extending it at the crossing (§5, `lib/arg-env.nix`).

**Informed by** (README's own label; no result claimed)

- **Reynolds (1972), *Definitional Interpreters*** — `builtins.functionArgs` as formal-parameter reflection. `lib/strip.nix` explicitly corrects the citation: residual arity is lambda calculus, "not a specific Reynolds 1972 section — §4 is Abstract Syntax".
- **Leijen (2005), *Extensible Records with Scoped Labels*** — the merge-strategy vocabulary; gen-bind uses flat `//` rather than row-typed scoping (`lib/compose.nix`, `lib/merge-strategy.nix`).

**Cited in code but not in the README table**: Söderberg & Hedin (2013), CHORAG §5.1 — materialization-as-attribution over the static AST, the producer-scoped thunk resolution in `lib/thunk.nix`.

**Checked invariants**: the library source imports no `nixpkgs.lib` — enforced by `ci/tests/purity.nix` (`test-library-source-is-nixpkgs-lib-free`) over `lib/**.nix` + root `flake.nix`, excluding `ci/`. The vendored `setFunctionArgs`/`setDefaultModuleLocation` are held byte-behavior-identical to nixpkgs' module probe by `ci/tests/evalmodules-equivalence.nix`.

## Drift check

```sh
nix eval --json .#lib --apply 'l: { top = builtins.attrNames l; nested = builtins.mapAttrs (_: builtins.attrNames) { inherit (l) contract mergeStrategy provenance; }; }'
```

Current output (verbatim):

```json
{"nested":{"contract":["apply","hasFields","isType","mk","nonEmpty"],"mergeStrategy":["bindWins","error","fromBindings","systemWins"],"provenance":["format"]},"top":["adaptArgs","buildSignature","compose","composeWith","configGate","contract","crossEval","isThunk","mergeStrategy","mkMergeValidator","mkThunk","mkThunkFrom","provenance","resolveThunks","stripBindingArgs","wrap","wrapAll","wrapIdentity"]}
```

**Checks.** Test-runner invocation (from the repo root; CI runs the same command with `working-directory: ci`, `.github/workflows/ci.yml:13,18`):

```sh
nix flake check ./ci
```

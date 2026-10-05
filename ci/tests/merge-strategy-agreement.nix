# Each Merge Strategy's SERVED VALUE agrees with the validator's WARNING, through evalModules, for every
# channel the hosted module system supplies an argument by: `config._module.args` (M), `specialArgs`
# (S), and a name evalModules passes itself, `lib` (L). N supplies nothing: the no-collision control.
# The value and the warning both read `merge-strategy.nix`'s `systemArg` (den-hoag-34i06).
#
# Two shapes. `partial` leaves `config` unbound. `full` binds every formal, and the wrapped module is
# still a function of the module system's call args, so `system-wins` serves the hosted value on both
# (owner-ruled 2026-10-05). The `error` strategy's refusal is pinned by its text on the `testsError`
# plane; the `tests` plane pins the refused cell's served value only.
{ lib, genBind, ... }:
let
  inherit (genBind) wrap wrapAll mkThunkFrom;
  sysVal = {
    tag = "SYSTEM";
  };
  tagOf = v: v.tag or (if v ? mkOption then "SYSTEM" else "OTHER");
  nameOf = src: if src == "L" then "lib" else "a";
  policyCfg = {
    bw.mergeStrategies = "bind-wins";
    sw.mergeStrategies = "system-wins";
    er.mergeStrategies = "error";
    swann.annotation = "system-wins";
  };
  cfgOf =
    pol: src:
    let
      n = nameOf src;
      p = policyCfg.${pol};
    in
    {
      bindings.${n} = {
        tag = "BOUND";
      }
      // lib.optionalAttrs (p ? annotation) { _mergeStrategy = p.annotation; };
    }
    // lib.optionalAttrs (p ? mergeStrategies) { mergeStrategies.${n} = p.mergeStrategies; };
  modOf =
    shape: src:
    if shape == "full" then
      (if src == "L" then ({ lib }: { config.out = tagOf lib; }) else ({ a }: { config.out = tagOf a; }))
    else if src == "L" then
      ({ lib, config, ... }: { config.out = tagOf lib; })
    else
      ({ a, config, ... }: { config.out = tagOf a; });
  decls = {
    options.out = lib.mkOption { };
    options.warnings = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
  };
  evalWith =
    specialArgs: modules:
    (lib.evalModules {
      inherit specialArgs;
      modules = modules ++ [ decls ];
    }).config;
  evalCell =
    shape: pol: src:
    evalWith (lib.optionalAttrs (src == "S") { a = sysVal; }) (
      (wrapAll (cfgOf pol src) [
        (modOf shape src)
        (lib.optionalAttrs (src == "M") { config._module.args.a = sysVal; })
      ]).all
    );
  forced = v: builtins.deepSeq v v;

  refused =
    shape: pol: src:
    src != "N" && pol == "er";
  msg = src: tail: [ "gen-bind: binding '${nameOf src}' collision — ${tail}" ];
  expectedOf =
    shape: pol: src:
    if refused shape pol src then
      { out = "BOUND"; }
    else if src == "N" then
      {
        out = "BOUND";
        warnings = [ ];
      }
    else if pol == "bw" then
      {
        out = "BOUND";
        warnings = msg src "bind-wins, module-system value shadowed";
      }
    else
      {
        out = "SYSTEM";
        warnings = msg src "system-wins, binding value dropped";
      };
  exprOf =
    shape: pol: src:
    let
      c = evalCell shape pol src;
    in
    if refused shape pol src then
      { inherit (c) out; }
    else
      {
        inherit (c) out;
        warnings = forced c.warnings;
      };
  refusalOf =
    src:
    "^gen-bind: binding '${nameOf src}' collides with module-system arg — set mergeStrategy to resolve$";

  cellName =
    shape: pol: src:
    "test-${lib.optionalString (shape == "full") "full-"}${pol}-${src}";
  grid =
    lib.concatMap
      (
        shape:
        lib.concatMap (
          pol:
          map
            (src: {
              inherit shape pol src;
            })
            [
              "M"
              "S"
              "L"
              "N"
            ]
        ) (builtins.attrNames policyCfg)
      )
      [
        "partial"
        "full"
      ];

  # The imports-attrset shape: one `{ imports = [ … ]; }` module whose two imports bind `a` under
  # `system-wins`, one partial and one fully applied, with `a` in `config._module.args`. In either order
  # both imports are served the hosted value, and both drops are warned, because every sub-import's
  # validator is kept.
  importsCell =
    imports:
    evalWith { }
      (wrapAll
        {
          bindings.a.tag = "BOUND";
          mergeStrategies.a = "system-wins";
        }
        [
          { inherit imports; }
          {
            options.outPart = lib.mkOption { };
            options.outFull = lib.mkOption { };
            config._module.args.a = sysVal;
          }
        ]
      ).all;
  # A module whose attribute STRUCTURE depends on its bound arg, with no system value supplied.
  structureCell =
    policy:
    evalWith { }
      (wrapAll
        {
          bindings.a.on = true;
          mergeStrategies.a = policy;
        }
        [
          ({ a, config, ... }: if a.on then { options.out2 = lib.mkOption { default = "ON"; }; } else { })
        ]
      ).all;
  part = { a, config, ... }: { config.outPart = a.tag; };
  full = { a }: { config.outFull = a.tag; };
  importsServed = imports: {
    expr =
      let
        c = importsCell imports;
      in
      {
        inherit (c) outPart outFull;
        warnings = forced c.warnings;
      };
    expected = {
      outPart = "SYSTEM";
      outFull = "SYSTEM";
      warnings =
        msg "M" "system-wins, binding value dropped" ++ msg "M" "system-wins, binding value dropped";
    };
  };
in
{
  flake.tests.merge-strategy-agreement =
    builtins.listToAttrs (
      map (c: {
        name = cellName c.shape c.pol c.src;
        value = {
          expr = exprOf c.shape c.pol c.src;
          expected = expectedOf c.shape c.pol c.src;
        };
      }) grid
    )
    // {
      # nixpkgs' precedence: `args.${k}` before `config._module.args.${k}`, so `specialArgs` wins.
      test-sw-precedence-specialArgs-over-module-args = {
        expr =
          let
            c = evalWith { a.tag = "S"; } (
              (wrapAll (cfgOf "sw" "S") [
                (modOf "partial" "S")
                { config._module.args.a.tag = "M"; }
              ]).all
            );
          in
          {
            inherit (c) out;
            warnings = forced c.warnings;
          };
        expected = {
          out = "S";
          warnings = msg "S" "system-wins, binding value dropped";
        };
      };

      test-imports-partial-then-full-serves-the-system-value = importsServed [
        part
        full
      ];
      test-imports-full-then-partial-serves-the-system-value = importsServed [
        full
        part
      ];

      # Two imports binding DIFFERENT names: each import's collision is warned.
      test-imports-every-sub-import-validator-warns = {
        expr =
          forced
            (evalWith { }
              (wrapAll
                {
                  bindings = {
                    a = "BOUND";
                    b = "BOUND";
                  };
                }
                [
                  {
                    imports = [
                      ({ a, config, ... }: { })
                      ({ b, config, ... }: { })
                    ];
                  }
                  {
                    config._module.args = {
                      a = "x";
                      b = "y";
                    };
                  }
                ]
              ).all
            ).warnings;
        expected = [
          "gen-bind: binding 'a' collision — bind-wins, module-system value shadowed"
          "gen-bind: binding 'b' collision — bind-wins, module-system value shadowed"
        ];
      };

      # `system-wins` over a declared thunk binding with no system value falls through to the thunk
      # arm and is resolved, not served raw.
      test-sw-thunk-binding-without-system-value-resolves = {
        expr =
          let
            wrapped = wrap {
              bindings.ch = [
                (mkThunkFrom "host=iceberg" ({ config, ... }: "h-${config.networking.hostName}"))
              ];
              producerConfigs."host=iceberg".networking.hostName = "iceberg";
              thunkBindings = [ "ch" ];
              mergeStrategies.ch = "system-wins";
            } ({ ch, config, ... }: { out = ch; });
          in
          builtins.head (wrapped.module { config = { }; }).out;
        expected = "h-iceberg";
      };

      # The price's control: `bind-wins` never reads `config._module.args` for the served value, so the
      # structure-dependent module of `testsError`'s `test-sw-structure-dependent-module-recurses` is served.
      test-bw-structure-dependent-module-is-served = {
        expr = (structureCell "bind-wins").out2;
        expected = "ON";
      };
    };

  flake.testsError.merge-strategy-agreement =
    builtins.listToAttrs (
      map (c: {
        name = "${cellName c.shape c.pol c.src}-refuses-by-name";
        value = {
          expr = forced (evalCell c.shape c.pol c.src).warnings;
          expectedError = {
            type = "ThrownError";
            msg = refusalOf c.src;
          };
        };
      }) (builtins.filter (c: refused c.shape c.pol c.src) grid)
    )
    // {
      # THE PRICE: a module whose attribute STRUCTURE depends on its `system-wins`-bound arg recurses
      # when no system value is supplied, because deciding presence reads the names of
      # `config._module.args`. Uncatchable, so it lives here. nixpkgs pays the same for an arg it reads
      # from `_module.args`; `bind-wins` over the same module does not read them.
      test-sw-structure-dependent-module-recurses = {
        expr = (structureCell "system-wins").out2;
        # By message: the error's class name differs between runners (nix-unit 2.35.1 reports
        # `EvalError`, the `ci --tests-error` runner `InfiniteRecursionError`).
        expectedError.msg = "infinite recursion encountered";
      };
    };
}

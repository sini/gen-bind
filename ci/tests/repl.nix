# The repl entry (`ci/repl.nix`, the harness `repl` command's file) loads, and loads exactly the
# library surface plus `lib`, `prelude` and `genBind`. Nothing else in the suite reaches that file,
# which is how it came to import `../lib` without the `graph` it requires (den-hoag-s34cm).
{
  lib,
  genBind,
  prelude,
  graph,
  ...
}:
{
  flake.tests.repl.test-entry-loads-the-surface = {
    expr = builtins.attrNames (import ../repl.nix { inherit lib prelude graph; });
    expected = builtins.attrNames ({ inherit lib prelude genBind; } // genBind);
  };
}

# One supply in its own file, so a cell can import it along two paths: one declaration reached
# twice. Underscore-prefixed so import-tree does not collect it as a test module.
{ wrappedB, entity }:
{
  bindings.user = wrappedB "den" (_: "alice");
  proposals = { };
  origins.user = "users/alice.nix";
  valueIdentities.user = entity "alice";
}

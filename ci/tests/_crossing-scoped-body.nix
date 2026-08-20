# Fixture for population P-B: a body that is a Nix expression in its OWN FILE,
# naming a free variable the substrate supplies through the scope.
#
# Underscore-prefixed so import-tree does not pick it up as a flake-parts module.
# It is deliberately NOT a function of its inputs: the whole point of the
# population is that the substrate DECIDES what the body can name, rather than
# the body reaching for it.
{
  value = supplied;
  viaBaseScope = builtins.length [
    1
    2
  ];
}

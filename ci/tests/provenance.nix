{ lib, bindLib, ... }:
let
  inherit (bindLib) provenance;
in
{

  flake.tests.provenance.test-format-source-only = {
    expr = provenance.format { source = "env-to-hosts"; };
    expected = "provided by 'env-to-hosts'";
  };

  flake.tests.provenance.test-format-source-and-scope = {
    expr = provenance.format {
      source = "env-to-hosts";
      scope = "host=igloo";
    };
    expected = "provided by 'env-to-hosts' at scope 'host=igloo'";
  };

  flake.tests.provenance.test-format-null-returns-empty = {
    expr = provenance.format null;
    expected = "";
  };
}

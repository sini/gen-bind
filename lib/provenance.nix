# Blame tracking for binding provenance.
#
# Provenance is metadata on the wrap() CALL, not on binding values.
# It surfaces in collision error messages and contract violations,
# producing actionable blame trails.
#
# Academic: Findler & Felleisen 2002 — blame assignment for contract
# violations identifies WHICH party caused the conflict. gen-bind
# adapts this: provenance identifies which binding source (scope rule,
# policy, manual wiring) provided a conflicting value.
{ prelude }:
{
  format =
    prov:
    if prov == null then
      ""
    else
      "provided by '${prov.source}'"
      + prelude.optionalString (prov.scope or null != null) " at scope '${prov.scope}'";
}

# Policy routing priorities

Policy routing priority names describe when a rule runs relative to the main routing table. This keeps the shared ordering explicit without encoding the rule's current producer or use case into the priority name.

## Names

| Priority | Current name | New name | Reason |
| ---: | --- | --- | --- |
| 50 | `sourcePolicy`, `sourcePolicyFallback`, `sourceOverride` | `preMain` | All three run before the main-table lookup. Management traffic intentionally bypasses the main table, while each `sourcePolicy` lookup and its `sourcePolicyFallback` rule share this priority and rely on insertion order. |
| 100 | `"100"` | `main` | Names the existing `lookup main suppress_prefixlength 0` stage instead of exposing its numeric priority at call sites. |
| 150 | `overlay` | `postMain` | The defining property is that these rules run after the main-table lookup, not that the current rule happens to serve an overlay network. |
| 200 | `outlet` | `wltOutlet` | Identifies the rules that dispatch WLT outlet marks to their routing tables. |
| 300 | `wanSource` | `wanSource` | The current name already states that a WAN source address selects its corresponding routing table. |
| 400 | `sourceSubnet` | Remove | No evaluated host currently produces a rule in this priority. |
| 900 | `fallback` | `defaultOutlet` | Describes the actual role: the final outlet used when no earlier rule matches. |

The resulting priority set is:

```nix
priorities = {
  preMain = 50;
  main = 100;
  postMain = 150;
  wltOutlet = 200;
  wanSource = 300;
  defaultOutlet = 900;
};
```

Rules sharing `preMain` must be added in their intended evaluation order. In particular, each `sourcePolicy` lookup and its `sourcePolicyFallback` rule remain adjacent, with the lookup added first.

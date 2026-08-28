# Policy routing marks

Outlet selectors use the low 12 bits of the packet mark and match them with
`/0xfff`.

## Nylon

A Nylon exit is encoded as `0xNNI` and uses routing table `5NNI`:

- `NN` is the decimal spelling of the node's Nylon address last octet and its
  first MPLS label. Selector nodes therefore use labels 16–99.
- `I` is the exit index, equal to the last digit of its second MPLS label
  (`100`–`109`).
- The table ID is `5000 + NN * 10 + I`.

For example, node `16`, exit label `100` produces:

```text
ip rule add pref 200 fwmark 0x160/0xfff lookup 5160
ip route add default encap mpls 16/100 dev nylon0 table 5160
```

The mark is a hexadecimal literal while MPLS labels and table IDs are decimal.
Their numeric values intentionally differ; the shared digits make the mapping
easy to read. The encoding is derived from topology rather than list order, so
adding or removing another exit cannot renumber it.

## WLT

WLT stores two 12-bit outlet marks in one value. Domestic selection occupies
bits 12–23 (`0xfff000`); overseas selection occupies bits 0–11 (`0xfff`). The
nftables classifier extracts them with `mark >> 12` and `mark & 0xfff`.
`0xfff` and routing table `4095` are reserved for the disabled-IPv6 route.
The 12-bit format starts a new `wlt_src2mark-v2.conf` snapshot so legacy raw
marks are not restored; existing selections must be made again after cutover.

## wgIplc

Every router uses selector mark `0x100` and routing table `5100` for wgIplc.
This is below the Nylon range, whose first possible selector is `0x160` and
table `5160`. WireGuard's `0x90000` socket mark only prevents tunnel recursion;
it is separate from the `0x100` traffic selector and remains unchanged.

## Cutover

Follow the topology change, checks, and deployment workflow in
[`docs/nylon.md` § 修改与部署](nylon.md#修改与部署). Deploy each affected selector with
`just sync-and-rebuild <host>`; its generated Nix configuration installs the
three-digit outlets, rules, and routes. Use a maintenance window when the change
invalidates stored WLT choices, and verify representative choices and the
affected mark → table → MPLS paths before ending the window. Legacy marks and
staged compatibility rules are not supported.

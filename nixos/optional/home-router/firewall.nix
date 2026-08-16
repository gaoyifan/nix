{
  config,
  lib,
  ...
}: let
  cfg = config.networking.homeRouter;
  wanNames = lib.attrNames cfg.wans;
  wans = lib.attrValues cfg.wans;
  addressWithoutPrefix = address: lib.head (lib.splitString "/" address);
  ipv4Addresses = addresses: lib.filter (address: !(lib.hasInfix ":" address)) addresses;
  ipv6Addresses = addresses: lib.filter (address: lib.hasInfix ":" address) addresses;

  ipv4NatRules = lib.concatMapStringsSep "\n" (wanName:
    lib.concatMapStringsSep "\n" (sourceSubnet: ''
      ip saddr ${sourceSubnet} oifname "${cfg.wans.${wanName}.interface}" masquerade
    '')
    cfg.wans.${wanName}.masquerade.ipv4SourceSubnets)
  wanNames;
  ipv6NatRules = lib.concatMapStringsSep "\n" (wanName:
    lib.concatMapStringsSep "\n" (sourceSubnet: ''
      ip6 saddr ${sourceSubnet} oifname "${cfg.wans.${wanName}.interface}" masquerade
    '')
    cfg.wans.${wanName}.masquerade.ipv6SourceSubnets)
  wanNames;
  hasIPv4Nat = lib.any (wan: wan.masquerade.ipv4SourceSubnets != []) wans;
  hasIPv6Nat = lib.any (wan: wan.masquerade.ipv6SourceSubnets != []) wans;

  markedWanEntries =
    lib.filter (entry:
      entry.value.routingTable != null && entry.value.addresses != [])
    (map (name: {
        inherit name;
        value = cfg.wans.${name};
      })
      wanNames);
  conntrackMarkRules = lib.concatMapStringsSep "\n" (entry:
    lib.concatStringsSep "\n" (
      map (address: ''
        ip daddr ${addressWithoutPrefix address} ct state new ct mark set ${toString entry.value.routingTable}
      '') (ipv4Addresses entry.value.addresses)
      ++ map (address: ''
        ip6 daddr ${addressWithoutPrefix address} ct state new ct mark set ${toString entry.value.routingTable}
      '') (ipv6Addresses entry.value.addresses)
    ))
  markedWanEntries;
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf (hasIPv4Nat || hasIPv6Nat) {
      networking.nftables.tables.home-router.content = ''
        chain nat-postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          ${ipv4NatRules}
          ${ipv6NatRules}
        }
      '';
    })

    (lib.mkIf (markedWanEntries != []) {
      networking.nftables.tables.home-router.content = ''
        chain wan-prerouting {
          type filter hook prerouting priority mangle; policy accept;
          ct state established,related ct mark != 0 meta mark set ct mark
          ${conntrackMarkRules}
          ct mark != 0 meta mark set ct mark
        }

        chain wan-output {
          type route hook output priority mangle; policy accept;
          ct mark != 0 meta mark set ct mark
        }
      '';
    })
  ]);
}

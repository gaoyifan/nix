{
  config,
  lib,
  options,
  pkgs,
  ...
}: let
  cfg = config.networking.homeRouter;
  nylonUdpPort =
    if lib.hasAttrByPath ["services" "nylon" "udpPort"] options
    then config.services.nylon.udpPort
    else 6622;
  classification = cfg.egress.classification;
  wans = lib.attrValues cfg.wans;
  addressWithoutPrefix = address: lib.head (lib.splitString "/" address);
  ipv4Addresses = addresses: lib.filter (address: !(lib.hasInfix ":" address)) addresses;
  ipv6Addresses = addresses: lib.filter (address: lib.hasInfix ":" address) addresses;
  nftSet = values: lib.concatMapStringsSep ", " toString values;

  markedWans = lib.filter (wan: wan.routingTable != null && wan.addresses != []) wans;
  conntrackMarkRules = lib.concatMapStringsSep "\n" (wan:
    lib.concatStringsSep "\n" (
      map (address: ''
        ip daddr ${addressWithoutPrefix address} ct state new ct mark set ${toString wan.routingTable}
      '') (ipv4Addresses wan.addresses)
      ++ map (address: ''
        ip6 daddr ${addressWithoutPrefix address} ct state new ct mark set ${toString wan.routingTable}
      '') (ipv6Addresses wan.addresses)
    ))
  markedWans;

  geoSetNames = lib.unique (
    [
      "cn"
      "cn6"
    ]
    ++ map (rule: rule.set) classification.destinationAddressSetRules
  );
  geoSetIncludes = lib.concatMapStringsSep "\n" (name: ''include "${pkgs.nft-geo-sets}/set-${name}.conf"'') geoSetNames;
  renderMark = mark: ''meta mark set ${mark} ct mark set meta mark return'';
  destinationAddressSetRules =
    lib.concatMapStringsSep "\n" (
      rule: "${
        if rule.set == "cn6"
        then "ip6"
        else "ip"
      } daddr @${rule.set} ${renderMark rule.mark}"
    )
    classification.destinationAddressSetRules;
  extraClassificationRules = lib.concatStringsSep "\n" classification.extraRules;
  classifiedIngressInterfaces = lib.unique (cfg.internalInterfaces ++ classification.extraIngressInterfaces);
  classifiedIngressRules = lib.concatMapStringsSep "\n" (interface: ''iifname "${interface}" jump egress-classify'') classifiedIngressInterfaces;
  preroutingChain = lib.optionalString (classifiedIngressInterfaces != []) ''
    chain egress-prerouting {
      type filter hook prerouting priority mangle + 1; policy accept;
      ${classifiedIngressRules}
    }
  '';
  overseasIpv4Rule = lib.optionalString cfg.wgIplc.enable ''
    ip daddr != @cn ${renderMark cfg.wgIplc.mark}
  '';
  outputClassificationRule =
    if classification.outputClassificationInterface == null
    then "jump egress-classify"
    else ''oifname "${classification.outputClassificationInterface}" jump egress-classify'';
  privateIpv4Sources = [
    "10.0.0.0/8"
    "100.64.0.0/10"
    "172.16.0.0/12"
    "192.168.0.0/16"
    cfg.serviceAddresses.ipv4
  ];
  privateIpv6Sources = [
    "fc00::/7"
    cfg.serviceAddresses.ipv6
  ];
  wanInterfaces = lib.unique (lib.filter (interface: interface != "") (map (wan: wan.interface) wans));
  wanMasqueradeRules = lib.concatStringsSep "\n" (
    map (interface: ''ip saddr @private_v4 oifname "${interface}" masquerade'') wanInterfaces
    ++ map (interface: ''ip6 saddr @private_v6 oifname "${interface}" masquerade'') wanInterfaces
  );
  markedWanSnatRules = lib.concatMapStringsSep "\n" (wan: let
    mark = toString wan.routingTable;
    interface = wan.interface;
    ipv4 = ipv4Addresses wan.addresses;
    ipv6 = ipv6Addresses wan.addresses;
  in
    lib.concatStringsSep "\n" (
      lib.optional (ipv4 != []) ''oifname "${interface}" meta mark ${mark} snat ip to ${addressWithoutPrefix (lib.head ipv4)}''
      ++ lib.optional (ipv6 != []) ''oifname "${interface}" meta mark ${mark} snat ip6 to ${addressWithoutPrefix (lib.head ipv6)}''
    ))
  markedWans;
  wgIplcMasqueradeRule = lib.optionalString cfg.wgIplc.enable ''
    oifname "wg-iplc" meta mark ${cfg.wgIplc.mark} masquerade
  '';
  extraMasqueradeRules = lib.concatStringsSep "\n" (
    lib.concatMap (interface: [
      ''ip saddr @private_v4 oifname "${interface}" masquerade''
      ''ip6 saddr @private_v6 oifname "${interface}" masquerade''
    ])
    cfg.egress.masquerade.extraInterfaces
    ++ cfg.egress.masquerade.extraRules
  );
in {
  config = lib.mkIf cfg.enable {
    networking.nftables.tables.home-router.content = ''
      ${geoSetIncludes}

      set private_v4 {
        type ipv4_addr
        flags constant, interval
        elements = { ${nftSet privateIpv4Sources} }
      }
      set private_v6 {
        type ipv6_addr
        flags constant, interval
        elements = { ${nftSet privateIpv6Sources} }
      }

      chain egress-classify {
        ct mark != 0 meta mark set ct mark return
        ct direction reply ct state established,related return
        meta mark != 0 return
        fib daddr type local return
        udp sport { ${toString nylonUdpPort}, ${toString config.services.tailscale.port} } return
        ${extraClassificationRules}
        ${destinationAddressSetRules}
        ip daddr @private_v4 return
        ${overseasIpv4Rule}
        ip6 daddr 2000::/3 ip6 daddr != @cn6 meta l4proto ipv6-icmp return
        ip6 daddr 2000::/3 ip6 daddr != @cn6 meta l4proto tcp reject with tcp reset
        ip6 daddr 2000::/3 ip6 daddr != @cn6 reject with icmpv6 type no-route
      }

      ${preroutingChain}

      chain egress-output {
        type route hook output priority mangle + 1; policy accept;
        ${outputClassificationRule}
      }

      chain egress-postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ${markedWanSnatRules}
        ${wgIplcMasqueradeRule}
        ${wanMasqueradeRules}
        ${extraMasqueradeRules}
      }

      ${lib.optionalString (markedWans != []) ''
        chain wan-prerouting {
          type filter hook prerouting priority mangle; policy accept;
          ct state established,related ct mark != 0 meta mark set ct mark
          ${conntrackMarkRules}
          ct mark != 0 meta mark set ct mark
        }
      ''}
    '';
  };
}

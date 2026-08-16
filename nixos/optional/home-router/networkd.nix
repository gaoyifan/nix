{
  config,
  lib,
  ...
}: let
  cfg = config.networking.homeRouter;
  bridgeName = cfg.switch.name;
  interfaceForVlan = vlan: "${bridgeName}.${toString vlan}";

  lanNames = lib.attrNames cfg.lans;
  lans = lib.attrValues cfg.lans;
  wanNames = lib.attrNames cfg.wans;
  wans = lib.attrValues cfg.wans;
  routingPolicyNames = lib.attrNames cfg.routingPolicies;
  routingPolicyEntries =
    map (name: {
      inherit name;
      value = cfg.routingPolicies.${name};
    })
    routingPolicyNames;

  switchedWanNames = lib.filter (name: cfg.wans.${name}.vlan != null) wanNames;
  standaloneWanNames = lib.filter (name: cfg.wans.${name}.device != null) wanNames;
  switchedVlanIds = lib.unique (
    map (name: cfg.lans.${name}.vlan) lanNames
    ++ map (name: cfg.wans.${name}.vlan) switchedWanNames
  );

  lanNamesForInterface = interface:
    lib.filter (name: cfg.lans.${name}.interface == interface) lanNames;
  wanNamesForInterface = interface:
    lib.filter (name: cfg.wans.${name}.interface == interface) wanNames;
  namesForInterface = interface:
    lanNamesForInterface interface ++ wanNamesForInterface interface;
  lansForInterface = interface:
    map (name: cfg.lans.${name}) (lanNamesForInterface interface);
  allInterfaceNames = lib.unique (
    map (lan: lan.interface) lans
    ++ map (wan: wan.interface) wans
  );

  addressWithoutPrefix = address: lib.head (lib.splitString "/" address);
  ipv4Addresses = addresses: lib.filter (address: !(lib.hasInfix ":" address)) addresses;
  ipv6Addresses = addresses: lib.filter (address: lib.hasInfix ":" address) addresses;
  preferredSource = addresses:
    if addresses == []
    then null
    else addressWithoutPrefix (lib.head addresses);

  routedWanNames = lib.filter (name: cfg.wans.${name}.routingTable != null) wanNames;
  routedWanEntries =
    map (name: {
      inherit name;
      value = cfg.wans.${name};
    })
    routedWanNames;
  policyLan = policy:
    lib.attrByPath [policy.from] {
      vlan = 0;
      addresses = [];
    }
    cfg.lans;
  policyRouteTable = policy: 10000 + (policyLan policy).vlan;
  routingPolicyRouteTables = lib.listToAttrs (map (entry:
    lib.nameValuePair entry.name (policyRouteTable entry.value))
  routingPolicyEntries);
  routeTableIds =
    map (entry: entry.value.routingTable) routedWanEntries
    ++ map (entry: policyRouteTable entry.value) routingPolicyEntries;

  routingPoliciesForWan = wanName:
    lib.filter (entry: entry.value.via == wanName) routingPolicyEntries;
  sourcePrefixesForPolicy = policy:
    lib.unique (ipv4Addresses (policyLan policy).addresses);
  preMainRules = lib.concatMap (entry:
    lib.concatMap (sourcePrefix: [
      "from ${sourcePrefix} lookup ${entry.name}"
      "from ${sourcePrefix} unreachable"
    ])
    (sourcePrefixesForPolicy entry.value))
  routingPolicyEntries;

  routesForWan = wanName: let
    wan = cfg.wans.${wanName};
    mkRoutes = gateway: addresses: let
      route =
        {
          Gateway = gateway;
          GatewayOnLink = true;
        }
        // lib.optionalAttrs (preferredSource addresses != null) {
          PreferredSource = preferredSource addresses;
        };
    in
      lib.optionals (gateway != null) (
        lib.optional (wan.defaultRoute || wan.routingTable == null) route
        ++ lib.optional (wan.routingTable != null) (route // {Table = wanName;})
      );
  in
    mkRoutes wan.gateway4 (ipv4Addresses wan.addresses)
    ++ mkRoutes wan.gateway6 (ipv6Addresses wan.addresses)
    ++ wan.routes
    ++ map (entry: {
      Gateway = "_dhcp4";
      Table = entry.name;
    })
    (routingPoliciesForWan wanName);

  addressesForInterface = interface:
    lib.concatMap (lan: lan.addresses) (lansForInterface interface)
    ++ lib.concatMap (name: cfg.wans.${name}.addresses) (wanNamesForInterface interface);
  dnsForInterface = interface:
    lib.unique (lib.concatMap (lan: lan.dns) (lansForInterface interface));
  domainsForInterface = interface:
    lib.unique (lib.concatMap (lan: lan.domains) (lansForInterface interface));
  routesForInterface = interface:
    lib.concatMap routesForWan (wanNamesForInterface interface);
  announceIPv6ForInterface = interface:
    lib.any (lan: lan.ipv6.enable) (lansForInterface interface);
  ipv6PrefixesForInterface = interface:
    lib.concatMap (lan: lan.ipv6.prefixes) (lansForInterface interface);

  ipv4PolicyRules = {
    preMain = preMainRules;
    wltOutlet = lib.concatMap (entry:
      lib.optional (entry.value.gateway4 != null)
      "fwmark ${toString entry.value.routingTable} lookup ${entry.name}")
    routedWanEntries;
    wanSource = lib.concatMap (entry:
      map (address: "from ${addressWithoutPrefix address}/32 lookup ${entry.name}")
      (ipv4Addresses entry.value.addresses))
    routedWanEntries;
  };
  ipv6PolicyRules = {
    wltOutlet = lib.concatMap (entry:
      lib.optional (entry.value.gateway6 != null)
      "fwmark ${toString entry.value.routingTable} lookup ${entry.name}")
    routedWanEntries;
    wanSource = lib.concatMap (entry:
      map (address: "from ${addressWithoutPrefix address}/128 lookup ${entry.name}")
      (ipv6Addresses entry.value.addresses))
    routedWanEntries;
  };
  mkRuleBuckets = rules:
    lib.mapAttrs (_: value: lib.mkBefore value) (lib.filterAttrs (_: value: value != []) rules);

  portNames = lib.attrNames cfg.switch.ports;
  bondPortNames = lib.filter (portName: cfg.switch.ports.${portName}.bond != null) portNames;
  mkPortBridgeVlans = port:
    lib.optional (port.untagged != null) {
      PVID = port.untagged;
      EgressUntagged = port.untagged;
    }
    ++ map (vlan: {VLAN = vlan;}) port.tagged;

  bondNetdevs = lib.listToAttrs (map (portName: let
    bond = cfg.switch.ports.${portName}.bond;
  in
    lib.nameValuePair "21-${portName}" {
      netdevConfig = {
        Kind = "bond";
        Name = portName;
      };
      bondConfig = {
        Mode = "active-backup";
        MIIMonitorSec = "1s";
      };
    })
  bondPortNames);

  bondMemberNetworks = lib.listToAttrs (lib.flatten (map (portName: let
    bond = cfg.switch.ports.${portName}.bond;
  in
    map (member:
      lib.nameValuePair "30-${member}" {
        matchConfig.Name = member;
        networkConfig = {
          Bond = portName;
          PrimarySlave = member == bond.primary;
        };
        linkConfig.RequiredForOnline = "no";
      })
    bond.members)
  bondPortNames));

  bridgePortNetworks = lib.listToAttrs (map (portName:
    lib.nameValuePair "31-${portName}" {
      matchConfig.Name = portName;
      networkConfig.Bridge = bridgeName;
      bridgeVLANs = mkPortBridgeVlans cfg.switch.ports.${portName};
      linkConfig.RequiredForOnline = "no";
    })
  portNames);

  vlanNetdevs = lib.listToAttrs (map (vlan: let
    interface = interfaceForVlan vlan;
  in
    lib.nameValuePair "25-vlan${toString vlan}" {
      netdevConfig = {
        Kind = "vlan";
        Name = interface;
      };
      vlanConfig.Id = vlan;
    })
  switchedVlanIds);

  vlanNetworks = lib.listToAttrs (map (vlan: let
    interface = interfaceForVlan vlan;
    representativeName = lib.head (namesForInterface interface);
    announceIPv6 = announceIPv6ForInterface interface;
  in
    lib.nameValuePair "41-${representativeName}" {
      matchConfig.Name = interface;
      address = addressesForInterface interface;
      dns = dnsForInterface interface;
      domains = domainsForInterface interface;
      routes = routesForInterface interface;
      networkConfig = {
        DHCP = "no";
        ConfigureWithoutCarrier = true;
        IPv6AcceptRA = false;
        IPv6SendRA = announceIPv6;
        DHCPPrefixDelegation = announceIPv6;
      };
      ipv6Prefixes = map (prefix: {Prefix = prefix;}) (ipv6PrefixesForInterface interface);
      linkConfig.RequiredForOnline = lib.mkDefault (
        if wanNamesForInterface interface != []
        then "routable"
        else "no"
      );
    })
  switchedVlanIds);

  standaloneWanNetworks = lib.listToAttrs (map (wanName: let
    wan = cfg.wans.${wanName};
  in
    lib.nameValuePair "10-wan-${wanName}" {
      matchConfig.Name = wan.interface;
      address = wan.addresses;
      routes = routesForWan wanName;
      networkConfig = {
        DHCP =
          if wan.dhcp
          then "yes"
          else "no";
        IPv6AcceptRA = wan.dhcp;
      };
      dhcpV4Config.UseDNS = false;
      dhcpV6Config.UseDNS = false;
      ipv6AcceptRAConfig.UseDNS = false;
      linkConfig.RequiredForOnline = "routable";
    })
  standaloneWanNames);

  altnamesForInterface = interface:
    lib.unique (
      lib.concatMap (name: cfg.lans.${name}.altnames) (lanNamesForInterface interface)
      ++ lib.concatMap (name: cfg.wans.${name}.altnames) (wanNamesForInterface interface)
    );
  alternativeNameLinks = lib.listToAttrs (lib.concatMap (interface: let
    names = namesForInterface interface;
    altnames = altnamesForInterface interface;
  in
    lib.optional (altnames != []) (lib.nameValuePair "20-home-router-${lib.head names}" {
      matchConfig.OriginalName = interface;
      linkConfig.AlternativeName = altnames;
    }))
  allInterfaceNames);
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = lib.intersectLists lanNames wanNames == [];
          message = "homeRouter LAN and WAN names must be unique.";
        }
        {
          assertion = builtins.length (map (lan: lan.vlan) lans) == builtins.length (lib.unique (map (lan: lan.vlan) lans));
          message = "Each homeRouter LAN must use a distinct VLAN.";
        }
        {
          assertion = lib.all (wan: (wan.vlan == null) != (wan.device == null)) wans;
          message = "Every homeRouter WAN must set exactly one of vlan or device.";
        }
        {
          assertion = lib.intersectLists (map (lan: lan.vlan) lans) (map (name: cfg.wans.${name}.vlan) switchedWanNames) == [];
          message = "A homeRouter VLAN cannot carry both a LAN and a WAN.";
        }
        {
          assertion = builtins.length (map (name: cfg.wans.${name}.device) standaloneWanNames) == builtins.length (lib.unique (map (name: cfg.wans.${name}.device) standaloneWanNames));
          message = "Standalone homeRouter WAN devices must be unique.";
        }
        {
          assertion = builtins.length (lib.filter (wan: wan.defaultRoute) wans) <= 1;
          message = "Only one static homeRouter WAN may install default routes in the main table.";
        }
        {
          assertion = builtins.length routeTableIds == builtins.length (lib.unique routeTableIds);
          message = "homeRouter routing table IDs must be unique.";
        }
        {
          assertion = lib.all (portName: let
            bond = cfg.switch.ports.${portName}.bond;
          in
            lib.elem bond.primary bond.members)
          bondPortNames;
          message = "Every homeRouter bond primary must be one of its members.";
        }
        {
          assertion = lib.all (entry: entry.value.gateway4 != null || entry.value.gateway6 != null) routedWanEntries;
          message = "A homeRouter WAN with routingTable must define an IPv4 or IPv6 gateway.";
        }
        {
          assertion = lib.intersectLists routedWanNames routingPolicyNames == [];
          message = "homeRouter WANs and routing policies must use distinct route table names.";
        }
        {
          assertion = lib.all (entry: lib.hasAttr entry.value.from cfg.lans && ipv4Addresses (policyLan entry.value).addresses != []) routingPolicyEntries;
          message = "Every homeRouter routing policy source must name a LAN with an IPv4 address.";
        }
        {
          assertion = builtins.length (map (entry: entry.value.from) routingPolicyEntries) == builtins.length (lib.unique (map (entry: entry.value.from) routingPolicyEntries));
          message = "A homeRouter LAN may have only one source-routing policy.";
        }
        {
          assertion = lib.all (entry: lib.hasAttr entry.value.via cfg.wans && cfg.wans.${entry.value.via}.dhcp) routingPolicyEntries;
          message = "Every homeRouter routing policy via value must name a DHCP WAN.";
        }
      ];

      systemd.network = {
        config.routeTables =
          lib.listToAttrs (map (entry: lib.nameValuePair entry.name entry.value.routingTable) routedWanEntries)
          // routingPolicyRouteTables;
        links = alternativeNameLinks;
        netdevs =
          {
            "20-${bridgeName}" = {
              netdevConfig = {
                Kind = "bridge";
                Name = bridgeName;
              };
              bridgeConfig = {
                VLANFiltering = true;
                DefaultPVID = "none";
              };
            };
          }
          // bondNetdevs
          // vlanNetdevs;
        networks =
          {
            "40-${bridgeName}" = {
              matchConfig.Name = bridgeName;
              vlan = map interfaceForVlan switchedVlanIds;
              bridgeVLANs = map (vlan: {VLAN = vlan;}) switchedVlanIds;
              networkConfig = {
                DHCP = "no";
                ConfigureWithoutCarrier = true;
                LinkLocalAddressing = false;
                IPv6AcceptRA = false;
              };
              linkConfig.RequiredForOnline = "no";
            };
          }
          // standaloneWanNetworks
          // bondMemberNetworks
          // bridgePortNetworks
          // vlanNetworks;
      };
    }

    {
      networking.policyRouting = {
        ipv4.routingPolicyRules = mkRuleBuckets ipv4PolicyRules;
        ipv6.routingPolicyRules = mkRuleBuckets ipv6PolicyRules;
      };
    }
  ]);
}

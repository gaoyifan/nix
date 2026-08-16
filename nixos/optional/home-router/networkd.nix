{
  config,
  lib,
  ...
}: let
  cfg = config.networking.homeRouter;
  bridgeName = cfg.switch.name;

  switchedWans = lib.filterAttrs (_: wan: wan.vlan != null) cfg.wans;
  standaloneWans = lib.filterAttrs (_: wan: wan.device != null) cfg.wans;
  switchedVlanIds = lib.unique (
    map (lan: lan.vlan) (lib.attrValues cfg.lans)
    ++ map (wan: wan.vlan) (lib.attrValues switchedWans)
  );

  lansForInterface = interface:
    lib.filterAttrs (_: lan: lan.interface == interface) cfg.lans;
  wansForInterface = interface:
    lib.filterAttrs (_: wan: wan.interface == interface) cfg.wans;

  addressWithoutPrefix = address: lib.head (lib.splitString "/" address);
  ipv4Addresses = addresses: lib.filter (address: !(lib.hasInfix ":" address)) addresses;
  ipv6Addresses = addresses: lib.filter (address: lib.hasInfix ":" address) addresses;
  concatMapAttrsToList = f: attrs:
    lib.concatLists (lib.mapAttrsToList f attrs);

  routedWans = lib.filterAttrs (_: wan: wan.routingTable != null) cfg.wans;
  policyLan = policy:
    lib.attrByPath [policy.from] {
      vlan = 0;
      addresses = [];
    }
    cfg.lans;

  routesForWan = wanName: wan: let
    mkRoutes = gateway: addresses: let
      route =
        {
          Gateway = gateway;
          GatewayOnLink = true;
        }
        // lib.optionalAttrs (addresses != []) {
          PreferredSource = addressWithoutPrefix (lib.head addresses);
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
    ++ lib.mapAttrsToList (name: _: {
      Gateway = "_dhcp4";
      Table = name;
    })
    (lib.filterAttrs (_: policy: policy.via == wanName) cfg.routingPolicies);

  bondPorts = lib.filterAttrs (_: port: port.bond != null) cfg.switch.ports;
in {
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.intersectLists (lib.attrNames cfg.lans) (lib.attrNames cfg.wans) == [];
        message = "homeRouter LAN and WAN names must be unique.";
      }
      {
        assertion = lib.allUnique (map (lan: lan.vlan) (lib.attrValues cfg.lans));
        message = "Each homeRouter LAN must use a distinct VLAN.";
      }
      {
        assertion = lib.all (wan: (wan.vlan == null) != (wan.device == null)) (lib.attrValues cfg.wans);
        message = "Every homeRouter WAN must set exactly one of vlan or device.";
      }
      {
        assertion = lib.intersectLists (map (lan: lan.vlan) (lib.attrValues cfg.lans)) (map (wan: wan.vlan) (lib.attrValues switchedWans)) == [];
        message = "A homeRouter VLAN cannot carry both a LAN and a WAN.";
      }
      {
        assertion = lib.allUnique (map (wan: wan.device) (lib.attrValues standaloneWans));
        message = "Standalone homeRouter WAN devices must be unique.";
      }
      {
        assertion = builtins.length (lib.filter (wan: wan.defaultRoute) (lib.attrValues cfg.wans)) <= 1;
        message = "Only one static homeRouter WAN may install default routes in the main table.";
      }
      {
        assertion = lib.allUnique (
          map (wan: wan.routingTable) (lib.attrValues routedWans)
          ++ map (policy: 10000 + (policyLan policy).vlan) (lib.attrValues cfg.routingPolicies)
        );
        message = "homeRouter routing table IDs must be unique.";
      }
      {
        assertion = lib.all (port: lib.elem port.bond.primary port.bond.members) (lib.attrValues bondPorts);
        message = "Every homeRouter bond primary must be one of its members.";
      }
      {
        assertion = lib.all (wan: wan.gateway4 != null || wan.gateway6 != null) (lib.attrValues routedWans);
        message = "A homeRouter WAN with routingTable must define an IPv4 or IPv6 gateway.";
      }
      {
        assertion = lib.intersectLists (lib.attrNames routedWans) (lib.attrNames cfg.routingPolicies) == [];
        message = "homeRouter WANs and routing policies must use distinct route table names.";
      }
      {
        assertion = lib.all (policy: lib.hasAttr policy.from cfg.lans && ipv4Addresses (policyLan policy).addresses != []) (lib.attrValues cfg.routingPolicies);
        message = "Every homeRouter routing policy source must name a LAN with an IPv4 address.";
      }
      {
        assertion = lib.allUnique (map (policy: policy.from) (lib.attrValues cfg.routingPolicies));
        message = "A homeRouter LAN may have only one source-routing policy.";
      }
      {
        assertion = lib.all (policy: lib.hasAttr policy.via cfg.wans && cfg.wans.${policy.via}.dhcp) (lib.attrValues cfg.routingPolicies);
        message = "Every homeRouter routing policy via value must name a DHCP WAN.";
      }
    ];

    systemd.network = {
      config.routeTables =
        lib.mapAttrs (_: wan: wan.routingTable) routedWans
        // lib.mapAttrs (_: policy: 10000 + (policyLan policy).vlan) cfg.routingPolicies;
      links = lib.listToAttrs (lib.concatMap (interface: let
          interfaceLans = lansForInterface interface;
          interfaceWans = wansForInterface interface;
          altnames = lib.unique (
            lib.concatMap (lan: lan.altnames) (lib.attrValues interfaceLans)
            ++ lib.concatMap (wan: wan.altnames) (lib.attrValues interfaceWans)
          );
        in
          lib.optional (altnames != []) (lib.nameValuePair "20-home-router-${lib.head (lib.attrNames interfaceLans ++ lib.attrNames interfaceWans)}" {
            matchConfig.OriginalName = interface;
            linkConfig.AlternativeName = altnames;
          }))
        (lib.unique (
          map (lan: lan.interface) (lib.attrValues cfg.lans)
          ++ map (wan: wan.interface) (lib.attrValues cfg.wans)
        )));
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
        // lib.mapAttrs' (portName: _:
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
        bondPorts
        // lib.listToAttrs (map (vlan:
          lib.nameValuePair "25-vlan${toString vlan}" {
            netdevConfig = {
              Kind = "vlan";
              Name = "${bridgeName}.${toString vlan}";
            };
            vlanConfig.Id = vlan;
          })
        switchedVlanIds);
      networks =
        {
          "40-${bridgeName}" = {
            matchConfig.Name = bridgeName;
            vlan = map (vlan: "${bridgeName}.${toString vlan}") switchedVlanIds;
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
        // lib.mapAttrs' (wanName: wan:
          lib.nameValuePair "10-wan-${wanName}" {
            matchConfig.Name = wan.interface;
            address = wan.addresses;
            routes = routesForWan wanName wan;
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
        standaloneWans
        // lib.listToAttrs (concatMapAttrsToList (portName: port:
          map (member:
            lib.nameValuePair "30-${member}" {
              matchConfig.Name = member;
              networkConfig = {
                Bond = portName;
                PrimarySlave = member == port.bond.primary;
              };
              linkConfig.RequiredForOnline = "no";
            })
          port.bond.members)
        bondPorts)
        // lib.mapAttrs' (portName: port:
          lib.nameValuePair "31-${portName}" {
            matchConfig.Name = portName;
            networkConfig.Bridge = bridgeName;
            bridgeVLANs =
              lib.optional (port.untagged != null) {
                PVID = port.untagged;
                EgressUntagged = port.untagged;
              }
              ++ map (vlan: {VLAN = vlan;}) port.tagged;
            linkConfig.RequiredForOnline = "no";
          })
        cfg.switch.ports
        // lib.listToAttrs (map (vlan: let
          interface = "${bridgeName}.${toString vlan}";
          interfaceLans = lansForInterface interface;
          interfaceWans = wansForInterface interface;
          announceIPv6 = lib.any (lan: lan.ipv6.enable) (lib.attrValues interfaceLans);
        in
          lib.nameValuePair "41-${lib.head (lib.attrNames interfaceLans ++ lib.attrNames interfaceWans)}" {
            matchConfig.Name = interface;
            address =
              lib.concatMap (lan: lan.addresses) (lib.attrValues interfaceLans)
              ++ lib.concatMap (wan: wan.addresses) (lib.attrValues interfaceWans);
            dns = lib.unique (lib.concatMap (lan: lan.dns) (lib.attrValues interfaceLans));
            domains = lib.unique (lib.concatMap (lan: lan.domains) (lib.attrValues interfaceLans));
            routes = concatMapAttrsToList routesForWan interfaceWans;
            networkConfig = {
              DHCP = "no";
              ConfigureWithoutCarrier = true;
              IPv6AcceptRA = false;
              IPv6SendRA = announceIPv6;
              DHCPPrefixDelegation = announceIPv6;
            };
            ipv6Prefixes = map (prefix: {Prefix = prefix;}) (lib.concatMap (lan: lan.ipv6.prefixes) (lib.attrValues interfaceLans));
            linkConfig.RequiredForOnline = lib.mkDefault (
              if interfaceWans != {}
              then "routable"
              else "no"
            );
          })
        switchedVlanIds);
    };

    networking.policyRouting = {
      ipv4.routingPolicyRules = lib.mapAttrs (_: value: lib.mkBefore value) {
        preMain = concatMapAttrsToList (name: policy:
          lib.concatMap (sourcePrefix: [
            "from ${sourcePrefix} lookup ${name}"
            "from ${sourcePrefix} unreachable"
          ])
          (lib.unique (ipv4Addresses (policyLan policy).addresses)))
        cfg.routingPolicies;
        wltOutlet = concatMapAttrsToList (name: wan:
          lib.optional (wan.gateway4 != null)
          "fwmark ${toString wan.routingTable} lookup ${name}")
        routedWans;
        wanSource = concatMapAttrsToList (name: wan:
          map (address: "from ${addressWithoutPrefix address}/32 lookup ${name}")
          (ipv4Addresses wan.addresses))
        routedWans;
      };
      ipv6.routingPolicyRules = lib.mapAttrs (_: value: lib.mkBefore value) {
        wltOutlet = concatMapAttrsToList (name: wan:
          lib.optional (wan.gateway6 != null)
          "fwmark ${toString wan.routingTable} lookup ${name}")
        routedWans;
        wanSource = concatMapAttrsToList (name: wan:
          map (address: "from ${addressWithoutPrefix address}/128 lookup ${name}")
          (ipv6Addresses wan.addresses))
        routedWans;
      };
    };
  };
}

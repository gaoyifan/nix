{
  config,
  lib,
  ...
}: let
  cfg = config.networking.homeRouter;
  lanNames = lib.attrNames cfg.lans;
  allLanInterfaceNames = lib.unique (map (lan: lan.interface) (lib.attrValues cfg.lans));
  dhcpRanges = lib.concatMap (name:
    lib.optional (cfg.lans.${name}.dhcpServer.range != null) cfg.lans.${name}.dhcpServer.range)
  lanNames;
  dhcpHosts = lib.concatMap (name: cfg.lans.${name}.dhcpServer.hosts) lanNames ++ cfg.internalDhcpHosts;
  dhcpSettings = map (name: cfg.lans.${name}.dhcpServer.settings) lanNames;
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.resolved.settings.Resolve = {
        MulticastDNS = false;
        DNS = [cfg.serviceAddresses.ipv4];
        Domains = ["~."];
      };

      systemd.network.networks."60-lo-host-services" = {
        matchConfig.Name = "lo";
        address = [
          "${cfg.serviceAddresses.ipv4}/32"
          "${cfg.serviceAddresses.ipv6}/128"
        ];
        linkConfig.RequiredForOnline = "no";
      };

      services.dnsmasq = {
        enable = true;
        resolveLocalQueries = false;
        settings = lib.mkMerge (
          [
            {
              bind-dynamic = true;
              interface = lib.unique (["lo"] ++ allLanInterfaceNames ++ cfg.dnsmasq.extraInterfaces);
              no-resolv = true;
              domain = cfg.dnsmasq.domain;
              expand-hosts = true;
              dhcp-range = dhcpRanges;
              dhcp-host = dhcpHosts;
              dhcp-authoritative = true;
            }
          ]
          ++ dhcpSettings
        );
      };
    }

    (lib.mkIf cfg.avahi.enable {
      services.avahi = {
        enable = true;
        allowInterfaces = cfg.internalInterfaces;
        ipv6 = false;
        reflector = true;
        publish = {
          enable = true;
          addresses = true;
        };
      };
    })
  ]);
}

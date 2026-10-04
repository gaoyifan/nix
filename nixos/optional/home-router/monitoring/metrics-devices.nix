{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.networking.homeRouter;
  lans = lib.mapAttrs' (name: lan: lib.nameValuePair lan.interface name) cfg.lans;
  lanInterfaces = lib.attrNames lans;
  tailscale =
    if config.services.tailscale.enable && config.services.tailscale.interfaceName != "userspace-networking"
    then config.services.tailscale.interfaceName
    else null;
  wanInterfaces = map (wan: wan.interface) (lib.attrValues cfg.wans) ++ ["wg-iplc"];
  wireguardInterfaces = lib.filter (interface: !(lib.elem interface wanInterfaces)) (
    lib.unique (lib.attrNames config.networking.wireguard.interfaces ++ lib.attrNames config.networking.wg-quick.interfaces)
  );
  layer3Interfaces = wireguardInterfaces ++ lib.optional (tailscale != null) tailscale;
  nftInterfaces = interfaces: lib.concatMapStringsSep ", " builtins.toJSON interfaces;
  counterSet = name: keyType: ''
    set ${name} {
      type ifname . ${keyType};
      flags dynamic, timeout;
      timeout 7d;
      size 4096;
    }
  '';
  metricsDirectory = "/run/home-router-wan-metrics";
  collectorConfig = pkgs.writeText "home-router-device-metrics.json" (builtins.toJSON {
    inherit lans tailscale;
    wireguard = wireguardInterfaces;
    inherit (cfg.monitoring) wireguardPeerNamesDirectory;
    incus = config.virtualisation.incus.enable;
    leaseFile = lib.last (lib.toList config.services.dnsmasq.settings.dhcp-leasefile);
  });
  grafanaDashboard = import ../../grafana-dashboard.nix;
  dashboard = pkgs.writeTextDir "home-router-devices.json" (builtins.toJSON (grafanaDashboard.build {
    source = import ./dashboard-devices.nix;
    variables = [
      (grafanaDashboard.customVariable {
        name = "lan";
        label = "LAN";
        query = lib.concatStringsSep "," (lib.attrValues lans ++ layer3Interfaces);
        current = {
          text = "All";
          value = "$__all";
        };
      })
    ];
  }));
in {
  config = lib.mkIf (cfg.enable && cfg.monitoring.enable) {
    # Nixpkgs checks rules using LKL, whose kernel lacks wildcard device hooks.
    # Validate these chains against loopback there; runtime keeps the VLAN hooks.
    networking.nftables.preCheckRuleset = lib.mkIf (lanInterfaces != []) ''
      sed 's|device "${lib.escapeRegex "${cfg.switch.name}.*"}"|device "lo"|g' -i ruleset.conf
    '';

    networking.nftables.tables = {
      home-router-device-macs = lib.mkIf (lanInterfaces != []) {
        family = "netdev";
        name = "home-router-devices";
        content = ''
          ${counterSet "upload_mac" "ether_addr"}
          ${counterSet "download_mac" "ether_addr"}

          # Wildcard hooks also attach to VLAN interfaces created after nftables starts.
          # Match the configured LANs below so WAN VLANs never enter these counters.
          chain lan-ingress {
            type filter hook ingress device "${cfg.switch.name}.*" priority filter; policy accept;
            iifname { ${nftInterfaces lanInterfaces} } ether type { ip, ip6 } ether daddr & 01:00:00:00:00:00 == 00:00:00:00:00:00 update @upload_mac { meta iifname . ether saddr counter }
          }
          chain lan-egress {
            type filter hook egress device "${cfg.switch.name}.*" priority filter; policy accept;
            oifname { ${nftInterfaces lanInterfaces} } ether type { ip, ip6 } ether daddr & 01:00:00:00:00:00 == 00:00:00:00:00:00 update @download_mac { meta oifname . ether daddr counter }
          }
        '';
      };
      home-router-device-addresses = lib.mkIf (layer3Interfaces != []) {
        family = "inet";
        name = "home-router-devices";
        content = ''
          ${counterSet "upload4" "ipv4_addr"}
          ${counterSet "download4" "ipv4_addr"}
          ${counterSet "upload6" "ipv6_addr"}
          ${counterSet "download6" "ipv6_addr"}

          chain vpn-ingress {
            type filter hook prerouting priority filter; policy accept;
            iifname { ${nftInterfaces layer3Interfaces} } ip daddr != 224.0.0.0/4 ip daddr != 255.255.255.255 update @upload4 { meta iifname . ip saddr counter }
            iifname { ${nftInterfaces layer3Interfaces} } ip6 daddr != ff00::/8 update @upload6 { meta iifname . ip6 saddr counter }
          }
          chain vpn-egress {
            type filter hook postrouting priority filter; policy accept;
            oifname { ${nftInterfaces layer3Interfaces} } ip daddr != 224.0.0.0/4 ip daddr != 255.255.255.255 update @download4 { meta oifname . ip daddr counter }
            oifname { ${nftInterfaces layer3Interfaces} } ip6 daddr != ff00::/8 update @download6 { meta oifname . ip6 daddr counter }
          }
        '';
      };
    };

    systemd.services.home-router-device-metrics = {
      description = "Export Home Router device traffic and names for Prometheus";
      wantedBy = ["multi-user.target"];
      after = ["nftables.service"];
      requires = ["nftables.service"];
      partOf = ["nftables.service"];
      path = [pkgs.nftables pkgs.wireguard-tools];
      serviceConfig = {
        RuntimeDirectory = "home-router-wan-metrics";
        RuntimeDirectoryPreserve = true;
        ExecStart = "${pkgs.python3}/bin/python3 ${./collect-device-metrics.py} ${collectorConfig} ${metricsDirectory}/home-router-devices.prom";
        Restart = "on-failure";
        RestartSec = "15s";
      };
    };
    services.grafana.provision.dashboards.settings.providers = [
      {
        name = "home-router-devices";
        options.path = dashboard;
      }
    ];
  };
}

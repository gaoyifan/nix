# Network configuration for somo-nanopi-r4s.
#
# WAN: end0 (CPU internal GMAC). USB tethering WANs: iOS ipheth or RNDIS.
# LAN trunk: enp1s0 untagged to br-somo2, VLAN 652 to br-gnet2, VLAN 654 to br-guest2.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  lanDomain = "somo.gaof.net";
  divergeListen = "127.0.0.1:1054";
  usbWanGroup = 6505;
  wgEl2 = config.services.secrets.nixos."somo-nanopi-r4s".wgEl2;

  divergeConf = pkgs.writeText "diverge.conf" ''
    [global]
    listen = ${divergeListen}

    [CN]
    addresses = 223.5.5.5 223.6.6.6
    protocol = udp
    port = 53
    ips = chnroutes.txt

    [X]
    addresses = 1.1.1.1 1.0.0.1
    protocol = https
    tls_dns_name = cloudflare-dns.com
  '';
in {
  imports = [
    ../../optional/home-router.nix
    ../../optional/nylon.nix
    ../../optional/policy-routing.nix
    ../../optional/wlt.nix
  ];

  networking.hostName = "somo-nanopi-r4s";

  services.usbmuxd.enable = true;

  systemd.network.wait-online.anyInterface = true;

  systemd.network.networks."11-usb-wan" = {
    matchConfig.Driver = "ipheth rndis_host";
    networkConfig = {
      DHCP = "ipv4";
      IPv6AcceptRA = false;
    };
    dhcpV4Config = {
      RouteMetric = 512;
      UseDNS = false;
    };
    linkConfig = {
      Group = usbWanGroup;
      RequiredForOnline = "routable";
    };
  };

  # Guest traffic follows only the primary WAN and fails closed when its DHCP
  # route is absent instead of falling through to USB tethering.
  systemd.network.config.routeTables.guest = 6504;
  systemd.network.networks."10-end0".routes = [
    {
      Gateway = "_dhcp4";
      Table = 6504;
    }
  ];

  networking.homeRouter = {
    enable = true;

    monitoring = {
      enable = true;
      grafana = {
        port = 3001;
        extraInterfaces = ["tailscale0"];
      };
    };

    wan.interface = "end0";

    trunks.enp1s0 = {
      untaggedBridge = "br-somo2";
      vlans."652".bridge = "br-gnet2";
      vlans."654".bridge = "br-guest2";
    };

    bridges = {
      br-gnet2 = {
        addresses = [
          "100.65.12.254/24"
          "fd9a:2d16:5c3e:12::254/64"
        ];
        ipv6.prefixes = ["fd9a:2d16:5c3e:12::/64"];
      };

      br-guest2 = {
        addresses = ["100.65.14.254/24"];
        ipv6.enable = false;
      };

      br-somo2 = {
        addresses = [
          "100.65.13.254/24"
          "fd9a:2d16:5c3e:13::254/64"
        ];
        ipv6.prefixes = ["fd9a:2d16:5c3e:13::/64"];
      };
    };

    nat = {
      ipv4SourceSubnet = "100.64.0.0/10";
      ipv6SourceSubnets = [
        "fd9a:2d16:5c3e:12::/64"
        "fd9a:2d16:5c3e:13::/64"
      ];
    };

    dnsmasq = {
      domain = lanDomain;
      servers = [
        "/cjia.gaof.net/100.65.1.254"
        "127.0.0.1#1054"
      ];
      extraInterfaces = ["tailscale0"];
      dhcpRanges = [
        "100.65.12.100,100.65.12.200,24h"
        "100.65.13.100,100.65.13.200,24h"
        "set:guest,100.65.14.100,100.65.14.200,24h"
      ];
      extraSettings.dhcp-option = [
        "tag:guest,option:dns-server,223.5.5.5,223.6.6.6"
      ];
    };
  };

  services.avahi.allowInterfaces = lib.mkForce ["br-gnet2" "br-somo2"];

  services.nylon = {
    enable = true;
    overlay = {
      ipv4Subnet = "10.250.10.0/24";
      ipv6Subnet = "fd10:250:10::/64";
    };
    exit = {
      enable = true;
      label = 100;
    };
  };

  services.wlt = {
    enable = true;
    domain = "gaof.net";
    lanInterfaces = ["br-gnet2" "br-somo2"];
    defaultOutletMark = {
      ipv4 = "0x42";
      ipv6 = "0x44";
    };
  };

  networking.policyRouting = {
    enable = true;

    ipv4 = {
      rules = [
        "pref 90 from 100.65.14.0/24 lookup 6504"
        "pref 91 from 100.65.14.0/24 unreachable"
        "pref 100 lookup main suppress_prefixlength 0"
        "pref 110 lookup 52 suppress_prefixlength 0"
        "pref 200 fwmark ${wgEl2.mark}/0xffffffff lookup ${wgEl2.routeTable}"
        "pref 32766 lookup main"
        "pref 32767 lookup default"
      ];
      ruleFiles = ["/var/lib/nylon/policy-routing/rules4.batch"];
    };

    ipv6 = {
      rules = [
        "pref 100 lookup main suppress_prefixlength 0"
        "pref 110 lookup 52 suppress_prefixlength 0"
        "pref 300 fwmark 0xff/0xff lookup 5255"
        "pref 32766 lookup main"
      ];
      ruleFiles = ["/var/lib/nylon/policy-routing/rules6.batch"];
    };
  };

  virtualisation.oci-containers.containers.diverge = {
    image = "ghcr.io/gaoyifan/diverge-rs:master";
    volumes = [
      "${inputs.chnroutes2}/chnroutes.txt:/chnroutes.txt:ro"
      "${divergeConf}:/diverge.conf:ro"
    ];
    extraOptions = ["--network=host"];
  };

  services.resolved.settings.Resolve = {
    DNS = ["1.1.1.1" "1.0.0.1" "223.5.5.5"];
    Domains = ["~."];
  };
  services.resolved.dnsDelegates.cjia = {
    Delegate = {
      DNS = ["100.65.1.254"];
      Domains = ["cjia.gaof.net"];
    };
  };

  systemd.network.networks."40-br-gnet2" = {
    dns = ["100.65.12.254"];
    domains = ["~${lanDomain}"];
  };

  networking.nftables.tables.filter = {
    family = "inet";
    content = ''
      chain input {
        type filter hook input priority filter; policy accept;
        iifname "br-guest2" udp dport 67 accept
        iifname "br-guest2" drop
      }

      chain forward {
        type filter hook forward priority filter; policy accept;
        iifname "br-somo2" oifname "tailscale0" ct state established,related accept
        iifname "br-somo2" oifname "tailscale0" ip daddr 100.65.1.63 tcp dport 8178 accept
        iifname "br-somo2" oifname "tailscale0" drop
        iifname "br-guest2" meta nfproto ipv4 oifname "end0" accept
        iifname "br-guest2" drop
      }
    '';
  };

  networking.nftables.tables.somo-host-egress = {
    family = "inet";
    content = ''
      include "${pkgs.nft-geo-sets}/set-cn.conf"
      include "${pkgs.nft-geo-sets}/set-cn6.conf"

      chain output {
        type route hook output priority mangle; policy accept;
        meta mark != 0 return
        udp sport ${toString config.services.nylon.udpPort} return
        ip daddr != @cn meta mark set ${wgEl2.mark}
        ip6 daddr != @cn6 icmpv6 type echo-request return
        ip6 daddr != @cn6 meta mark set 0xff
      }
    '';
  };

  networking.nftables.tables.wg-el2-nat = {
    family = "ip";
    content = ''
      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "${wgEl2.interfaceName}" meta mark ${wgEl2.mark} masquerade
      }
    '';
  };

  networking.nftables.tables.usb-wan-nat = {
    family = "ip";
    content = ''
      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ip saddr 100.64.0.0/10 oifgroup ${toString usbWanGroup} masquerade
      }
    '';
  };
}

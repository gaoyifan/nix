# Network configuration for somo-minisforum.
#
# WAN: enp3s0. USB tethering WANs: iOS ipheth or RNDIS interfaces.
# LAN trunk: enp4s0 untagged to br-somo and VLAN 652 to br-gnet.
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
  wgEl2 = config.services.secrets.nixos."somo-minisforum".wgEl2;
  vms = config.services.secrets.nixos."somo-minisforum".vms;
  hermesContainers = config.services.hermes-nspawn.containers;
  staticLeases =
    lib.mapAttrsToList
    (name: vm: "${vm.devices.eth0.hwaddr},${vm.staticLease},${name}")
    (lib.filterAttrs (_: vm: vm ? staticLease) vms)
    ++ lib.mapAttrsToList
    (name: vm: "${vm.macAddress},${vm.staticLease},hermes-nix-${name}")
    hermesContainers;

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

  networking.hostName = "somo-minisforum";

  services.usbmuxd.enable = true;

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
      RequiredForOnline = "no";
    };
  };

  # Guest traffic has its own fail-closed table: the default route follows
  # enp3s0's DHCP gateway, but never falls through to USB tethering.
  systemd.network.config.routeTables.guest = 6504;
  systemd.network.networks."10-enp3s0".routes = [
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

    wan.interface = "enp3s0";

    trunks.enp4s0 = {
      untaggedBridge = "br-somo";
      vlans."652".bridge = "br-gnet";
      vlans."654".bridge = "br-guest";
    };

    bridges = {
      br-gnet = {
        addresses = [
          "100.65.2.254/24"
          "fd9a:2d16:5c3e:2::254/64"
        ];
        ipv6.prefixes = ["fd9a:2d16:5c3e:2::/64"];
      };

      br-guest = {
        addresses = ["100.65.4.254/24"];
        ipv6.enable = false;
      };

      br-somo = {
        addresses = [
          "100.65.3.254/24"
          "fd9a:2d16:5c3e:3::254/64"
        ];
        ipv6.prefixes = ["fd9a:2d16:5c3e:3::/64"];
      };
    };

    nat = {
      ipv4SourceSubnet = "100.64.0.0/10";
      ipv6SourceSubnets = [
        "fd9a:2d16:5c3e:2::/64"
        "fd9a:2d16:5c3e:3::/64"
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
        "100.65.2.100,100.65.2.200,24h"
        "100.65.3.100,100.65.3.200,24h"
        "set:guest,100.65.4.100,100.65.4.200,24h"
      ];
      dhcpHosts = staticLeases;
      extraSettings.dhcp-option = [
        "tag:guest,option:dns-server,223.5.5.5,223.6.6.6"
      ];
    };
  };

  # Do not reflect internal service discovery into the guest network.
  services.avahi.allowInterfaces = lib.mkForce ["br-gnet" "br-somo"];

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
    lanInterfaces = ["br-gnet" "br-somo"];
    # Default overseas egress for LAN clients without an explicit selection:
    # IPv4 via "JP Tokyo | ALVIDI" (0x42), IPv6 via "JP Tokyo | Cloudflare
    # WARP" (0x44); marks come from nylon.toml / nylon.batch. CN destinations
    # keep mark 0 and leave via the WAN uplink. Only LAN bridges get these
    # defaults: WAN return traffic and forwarded tailnet flows keep their path.
    defaultOutletMark = {
      ipv4 = "0x42";
      ipv6 = "0x44";
    };
  };

  networking.policyRouting = {
    enable = true;

    ipv4 = {
      rules = [
        # Route guests through enp3s0's DHCP gateway before consulting any
        # internal or marked routes. Fail closed when that route is absent.
        "pref 90 from 100.65.4.0/24 lookup 6504"
        "pref 91 from 100.65.4.0/24 unreachable"

        # Local and tailnet routes must win before fwmark-selected default routes.
        "pref 100 lookup main suppress_prefixlength 0"
        "pref 110 lookup 52 suppress_prefixlength 0"

        # SOMO host-originated overseas IPv4 via wg-el2.
        "pref 200 fwmark ${wgEl2.mark}/0xffffffff lookup ${wgEl2.routeTable}"

        "pref 32766 lookup main"
        "pref 32767 lookup default"
      ];
      ruleFiles = [
        "/var/lib/nylon/policy-routing/rules4.batch"
      ];
    };

    ipv6 = {
      rules = [
        # Local and tailnet routes must win before fwmark-selected default routes.
        "pref 100 lookup main suppress_prefixlength 0"
        "pref 110 lookup 52 suppress_prefixlength 0"

        # WLT IPv6 disable outlet.
        "pref 300 fwmark 0xff/0xff lookup 5255"

        "pref 32766 lookup main"
      ];
      ruleFiles = [
        "/var/lib/nylon/policy-routing/rules6.batch"
      ];
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
    DNS = ["1.1.1.1" "1.0.0.1"];
    Domains = ["~."];
  };
  services.resolved.dnsDelegates.cjia = {
    Delegate = {
      DNS = ["100.65.1.254"];
      Domains = ["cjia.gaof.net"];
    };
  };

  systemd.network.networks."40-br-gnet" = {
    dns = ["100.65.2.254"];
    domains = ["~${lanDomain}"];
  };

  # SOMO policy: br-somo guests must not initiate tailnet connections, while
  # tailnet peers may still initiate connections into br-somo. The guest LAN
  # may use DHCP on the host and forward IPv4 only through enp3s0.
  networking.nftables.tables.filter = {
    family = "inet";
    content = ''
      chain input {
        type filter hook input priority filter; policy accept;
        iifname "br-guest" udp dport 67 accept
        iifname "br-guest" drop
      }

      chain forward {
        type filter hook forward priority filter; policy accept;
        iifname "br-somo" oifname "tailscale0" ct state established,related accept
        iifname "br-somo" oifname "tailscale0" ip daddr 100.65.1.63 tcp dport 8178 accept
        iifname "br-somo" oifname "tailscale0" drop
        iifname "br-guest" meta nfproto ipv4 oifname "enp3s0" accept
        iifname "br-guest" drop
      }
    '';
  };

  # SOMO policy: host-originated IPv4 overseas traffic uses wg-el2; overseas
  # IPv6 is disabled except echo requests for diagnostics.
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

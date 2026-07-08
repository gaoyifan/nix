# Network configuration for somo-minisforum.
#
# WAN: enp3s0. LAN trunk: enp4s0 untagged to br-somo and VLAN 652 to br-gnet.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  lanDomain = "somo.gaof.net";
  divergeListen = "127.0.0.1:1054";
  wgEl2 = config.services.secrets.nixos."somo-minisforum".wgEl2;
  vms = config.services.secrets.nixos."somo-minisforum".vms;
  staticLeases =
    lib.mapAttrsToList
    (name: vm: "${vm.devices.eth0.hwaddr},${vm.staticLease},${name}")
    (lib.filterAttrs (_: vm: vm ? staticLease) vms);

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

  networking.homeRouter = {
    enable = true;

    wan.interface = "enp3s0";

    trunks.enp4s0 = {
      untaggedBridge = "br-somo";
      vlans."652".bridge = "br-gnet";
    };

    bridges = {
      br-gnet = {
        addresses = [
          "100.65.2.254/24"
          "fd9a:2d16:5c3e:2::254/64"
        ];
        ipv6.prefixes = ["fd9a:2d16:5c3e:2::/64"];
      };

      br-somo = {
        addresses = [
          "100.65.3.254/24"
          "fd9a:2d16:5c3e:3::254/64"
        ];
        ipv6.prefixes = ["fd9a:2d16:5c3e:3::/64"];
      };
    };

    nat.sourceSubnet = "100.64.0.0/10";

    dnsmasq = {
      domain = lanDomain;
      servers = ["127.0.0.1#1054"];
      extraInterfaces = ["tailscale0"];
      dhcpRanges = [
        "100.65.2.100,100.65.2.200,24h"
        "100.65.3.100,100.65.3.200,24h"
      ];
      dhcpHosts = staticLeases;
    };
  };

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
  # tailnet peers may still initiate connections into br-somo.
  networking.nftables.tables.filter = {
    family = "inet";
    content = ''
      chain forward {
        type filter hook forward priority filter; policy accept;
        iifname "br-somo" oifname "tailscale0" ct state established,related accept
        iifname "br-somo" oifname "tailscale0" drop
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
}

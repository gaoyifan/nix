{
  config,
  lib,
  pkgs,
  ...
}: let
  hostPkgs = pkgs;
  headscaleIpv4Route = "100.124.0.0/16";
  headscaleIpv6Route = "fd7a:115c:a1e0:124::/64";
  hostTransitIpv4 = "10.255.124.1";
  containerTransitIpv4 = "10.255.124.2";
  hostTransitIpv6 = "fd00:124::1";
  containerTransitIpv6 = "fd00:124::2";
  headscalePort = 41641;
  chinanetMark = toString config.networking.homeRouter.wans.chinanet.routingTable;

  headscaleAdvertisedIpv4Routes = [
    "100.64.0.0/11"
    "100.96.0.0/12"
    "100.112.0.0/13"
    "100.120.0.0/14"
    "100.125.0.0/16"
    "100.126.0.0/15"
  ];
  headscaleAdvertisedIpv6Routes = [
    "fd7a:115c:a1e0::/56"
    "fd7a:115c:a1e0:100::/59"
    "fd7a:115c:a1e0:120::/62"
    "fd7a:115c:a1e0:125::/64"
    "fd7a:115c:a1e0:126::/63"
    "fd7a:115c:a1e0:128::/61"
    "fd7a:115c:a1e0:130::/60"
    "fd7a:115c:a1e0:140::/58"
    "fd7a:115c:a1e0:180::/57"
    "fd7a:115c:a1e0:200::/55"
    "fd7a:115c:a1e0:400::/54"
    "fd7a:115c:a1e0:800::/53"
    "fd7a:115c:a1e0:1000::/52"
    "fd7a:115c:a1e0:2000::/51"
    "fd7a:115c:a1e0:4000::/50"
    "fd7a:115c:a1e0:8000::/49"
  ];
  routeAttrs = cidr: let
    parts = lib.splitString "/" cidr;
  in {
    address = lib.head parts;
    prefixLength = lib.toInt (lib.last parts);
  };
  primaryAdvertisedRoutes = [
    "10.250.10.0/24"
    "11.13.112.0/24"
    "100.64.2.0/24"
    "100.64.110.0/24"
    # The control plane intentionally leaves 192.168.93.0/24 unapproved; it is
    # advertised only to work around an exit-node bug. The overlapping
    # 192.168.93.151/32 is the route actually approved for tailnet clients.
    "192.168.93.0/24"
    "202.38.93.0/24"
    "202.141.162.0/24"
    "202.141.178.0/24"
    "192.168.93.151/32"
    "192.168.225.50/32"
    headscaleIpv4Route
    headscaleIpv6Route
  ];
  headscaleSetFlags = [
    "--accept-dns=false"
    "--accept-routes=false"
    "--advertise-routes=${lib.concatStringsSep "," (headscaleAdvertisedIpv4Routes ++ headscaleAdvertisedIpv6Routes)}"
    "--hostname=el2-headscale-router"
    "--netfilter-mode=off"
    "--snat-subnet-routes=false"
  ];
in {
  imports = [../../optional/tailscale-gnet.nix];

  age.secrets.headscale-router-auth-key = lib.mkIf config.services.secrets.hasRealFiles {
    file = config.services.secrets.filesDir + "/nixos/el2/headscale-router-auth-key.age";
  };

  services.tailscale = {
    extraUpFlags = [
      "--advertise-connector"
      "--advertise-routes=${lib.concatStringsSep "," primaryAdvertisedRoutes}"
    ];
    port = 6627;
    serve = {
      enable = true;
      services = {
        immich2.endpoints."tcp:80" = "tcp://127.0.0.1:2283";
        restic-115.endpoints."tcp:80" = "http://127.0.0.1:8006";
        restic-123pan.endpoints."tcp:80" = "http://127.0.0.1:8005";
        restic-nas.endpoints."tcp:80" = "http://127.0.0.1:8000";
      };
    };
  };

  containers.hs-router = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = hostTransitIpv4;
    localAddress = containerTransitIpv4;
    hostAddress6 = hostTransitIpv6;
    localAddress6 = containerTransitIpv6;
    forwardPorts = [
      {
        protocol = "udp";
        hostPort = headscalePort;
      }
    ];
    allowedDevices = [
      {
        node = "/dev/net/tun";
        modifier = "rwm";
      }
    ];
    bindMounts = {
      "/dev/net/tun".isReadOnly = false;
      "/run/headscale-router-auth-key" = {
        hostPath = "/run/agenix/headscale-router-auth-key";
      };
    };
    config = {...}: {
      nixpkgs.pkgs = hostPkgs;

      networking = {
        useNetworkd = true;
        useHostResolvConf = false;
        nameservers = ["223.5.5.5"];
        firewall.enable = false;
        nftables = {
          enable = true;
          tables.hs-router = {
            family = "inet";
            content = ''
              chain postrouting {
                type nat hook postrouting priority srcnat;
                ip saddr ${hostTransitIpv4} ip daddr ${headscaleIpv4Route} oifname "tailscale0" masquerade
                ip6 saddr ${hostTransitIpv6} ip6 daddr ${headscaleIpv6Route} oifname "tailscale0" masquerade
              }
            '';
          };
        };
        interfaces.eth0 = {
          ipv4.routes =
            [
              {
                address = "0.0.0.0";
                prefixLength = 0;
                via = hostTransitIpv4;
                options.onlink = "";
              }
            ]
            ++ map (cidr:
              routeAttrs cidr
              // {
                via = hostTransitIpv4;
                options.onlink = "";
              })
            headscaleAdvertisedIpv4Routes;
          ipv6.routes =
            [
              {
                address = hostTransitIpv6;
                prefixLength = 128;
              }
            ]
            ++ map (cidr:
              routeAttrs cidr
              // {
                via = hostTransitIpv6;
              })
            headscaleAdvertisedIpv6Routes;
        };
      };

      # Main-table blackholes terminate unassigned Headscale addresses instead
      # of returning them to the host. The IPv6 routes in table 52 override
      # Tailscale's ULA /48 for the complementary main-tailnet prefixes.
      systemd.network.networks."40-eth0".routes =
        [
          {
            Destination = headscaleIpv4Route;
            Type = "blackhole";
          }
          {
            Destination = headscaleIpv6Route;
            Type = "blackhole";
          }
        ]
        ++ map (cidr: {
          Destination = cidr;
          Gateway = hostTransitIpv6;
          GatewayOnLink = true;
          Table = 52;
        })
        headscaleAdvertisedIpv6Routes;

      services.tailscale = {
        enable = true;
        port = headscalePort;
        authKeyFile = "/run/headscale-router-auth-key";
        useRoutingFeatures = "server";
        extraUpFlags = ["--login-server=https://headscale.auramont.cn"] ++ headscaleSetFlags;
        extraSetFlags = headscaleSetFlags;
      };

      system.stateVersion = "26.05";
    };
  };

  # networkd owns the host end of the veth, so the generated container
  # post-start commands must not add the same addresses and routes again.
  systemd.services."container@hs-router".postStart = lib.mkForce "";

  systemd.network.networks."05-hs-router" = {
    matchConfig.Name = "ve-hs-router";
    address = [
      "${hostTransitIpv4}/32"
      "${hostTransitIpv6}/128"
    ];
    routes = [
      {
        Destination = "${containerTransitIpv4}/32";
        Scope = "link";
      }
      {
        Destination = headscaleIpv4Route;
        Gateway = containerTransitIpv4;
        GatewayOnLink = true;
      }
      {
        Destination = "${containerTransitIpv6}/128";
        Scope = "link";
      }
      {
        Destination = headscaleIpv6Route;
        Gateway = containerTransitIpv6;
        GatewayOnLink = true;
      }
    ];
    networkConfig = {
      IPv6AcceptRA = false;
      # Forwarded packets cannot supply a local source address for NDP. The
      # kernel therefore needs an IPv6 link-local address to solicit the peer.
      LinkLocalAddressing = "ipv6";
    };
    linkConfig.RequiredForOnline = "no";
  };

  networking.edgeFirewall.extraForwardRules = [
    ''iifname "ve-hs-router" ip saddr ${containerTransitIpv4} accept''
  ];

  networking.nftables.tables.hs-router-egress = {
    family = "inet";
    content = ''
      chain prerouting {
        type filter hook prerouting priority mangle;
        iifname "ve-hs-router" ip saddr ${containerTransitIpv4} meta mark set ${chinanetMark}
      }
    '';
  };
}

{
  config,
  lib,
  pkgs,
  ...
}: let
  hostPkgs = pkgs;
  chinanetMark = toString config.networking.homeRouter.wans.chinanet.routingTable;

  headscaleRouters = {
    auramont = {
      containerName = "hs-router-auramont";
      syncZone = "kxing.gaof.net.";
      hostname = "el2-headscale-router";
      loginServer = "https://headscale.auramont.cn";
      ipv4Route = "100.124.0.0/16";
      ipv6Route = "fd7a:115c:a1e0:124::/64";
      hostTransitIpv4 = "10.255.124.1";
      containerTransitIpv4 = "10.255.124.2";
      hostTransitIpv6 = "fd00:124::1";
      containerTransitIpv6 = "fd00:124::2";
      port = 41641;
      authKeySecret = "headscale-router-auth-key";
      caCertificate = null;
    };
    library = {
      containerName = "hs-router-library";
      syncZone = "lib.gaof.net.";
      hostname = "el2-gateway-headscale-router";
      loginServer = "https://gw-hs.lib.ustc.edu.cn";
      ipv4Route = "100.64.74.0/24";
      ipv6Route = "fd7a:115c:a1e0:6474::/64";
      hostTransitIpv4 = "10.255.74.1";
      containerTransitIpv4 = "10.255.74.2";
      hostTransitIpv6 = "fd00:6474::1";
      containerTransitIpv6 = "fd00:6474::2";
      port = 41642;
      authKeySecret = null;
      caCertificate = ../gateway-headscale-ca.crt;
    };
  };

  primaryAdvertisedRoutes =
    [
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
    ]
    ++ lib.concatMap (router: [router.ipv4Route router.ipv6Route]) (lib.attrValues headscaleRouters);

  mkHeadscaleRouter = name: router: let
    authKeyPath = "/run/agenix/${router.authKeySecret}";
    containerAuthKeyPath = "/run/${router.authKeySecret}";
    hostTailscaleRuntimeDirectory = "/run/${router.containerName}-tailscale";
    hostVethName = "ve-${router.containerName}";
    # nspawn shortens long veth names to the first 11 characters plus a hash.
    # networkd resolves the full alternative name, while nftables needs the
    # shortened primary-name pattern.
    hostVethPattern = "${builtins.substring 0 11 hostVethName}*";
    setFlags = [
      "--accept-dns=false"
      "--accept-routes=false"
      "--advertise-routes="
      "--hostname=${router.hostname}"
      "--netfilter-mode=off"
      "--snat-subnet-routes=false"
    ];
  in {
    services.authoritativeNs.tailscaleSyncers.${name} = {
      zone = router.syncZone;
      socketPath = "${hostTailscaleRuntimeDirectory}/tailscaled.sock";
      sourceUnit = "container@${router.containerName}.service";
    };

    age.secrets = lib.optionalAttrs (router.authKeySecret != null) {
      ${router.authKeySecret} = lib.mkIf config.services.secrets.hasRealFiles {
        file = config.services.secrets.filesDir + "/nixos/el2/${router.authKeySecret}.age";
      };
    };

    containers.${router.containerName} = {
      autoStart = true;
      privateNetwork = true;
      hostAddress = router.hostTransitIpv4;
      localAddress = router.containerTransitIpv4;
      hostAddress6 = router.hostTransitIpv6;
      localAddress6 = router.containerTransitIpv6;
      forwardPorts = [
        {
          protocol = "udp";
          hostPort = router.port;
        }
      ];
      allowedDevices = [
        {
          node = "/dev/net/tun";
          modifier = "rwm";
        }
      ];
      bindMounts =
        {
          "/dev/net/tun".isReadOnly = false;
          "/run/tailscale" = {
            hostPath = hostTailscaleRuntimeDirectory;
            isReadOnly = false;
          };
        }
        // lib.optionalAttrs (router.authKeySecret != null) {
          ${containerAuthKeyPath} = {
            hostPath = authKeyPath;
          };
        };
      config = {...}: {
        nixpkgs.pkgs = hostPkgs;

        security.pki.certificateFiles = lib.optional (router.caCertificate != null) router.caCertificate;

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
                chain forward {
                  type filter hook forward priority filter; policy drop;
                  ct state established,related accept
                  iifname "eth0" oifname "tailscale0" ip daddr ${router.ipv4Route} accept
                  iifname "eth0" oifname "tailscale0" ip6 daddr ${router.ipv6Route} accept
                }

                chain postrouting {
                  type nat hook postrouting priority srcnat;
                  iifname "eth0" oifname "tailscale0" ip daddr ${router.ipv4Route} masquerade
                  iifname "eth0" oifname "tailscale0" ip6 daddr ${router.ipv6Route} masquerade
                }
              '';
            };
          };
          interfaces.eth0 = {
            ipv4.routes = [
              {
                address = "0.0.0.0";
                prefixLength = 0;
                via = router.hostTransitIpv4;
                options.onlink = "";
              }
            ];
            ipv6.routes = [
              {
                address = router.hostTransitIpv6;
                prefixLength = 128;
              }
            ];
          };
        };

        # Terminate unassigned addresses locally. Tailscale's more-specific
        # peer routes in table 52 still take precedence for active peers.
        systemd.network.networks."40-eth0".routes = [
          {
            Destination = router.ipv4Route;
            Type = "blackhole";
          }
          {
            Destination = router.ipv6Route;
            Type = "blackhole";
          }
        ];

        services.tailscale = {
          enable = true;
          port = router.port;
          authKeyFile =
            if router.authKeySecret == null
            then null
            else containerAuthKeyPath;
          useRoutingFeatures = "server";
          extraUpFlags = ["--login-server=${router.loginServer}"] ++ setFlags;
          extraSetFlags = setFlags;
        };

        system.stateVersion = "26.05";
      };
    };

    # networkd owns the host end of the veth, so the generated container
    # post-start commands must not add the same addresses and routes again.
    systemd.services."container@${router.containerName}".postStart = lib.mkForce "";

    systemd.tmpfiles.rules = ["d ${hostTailscaleRuntimeDirectory} 0755 root root -"];

    systemd.network.networks."05-${router.containerName}" = {
      matchConfig.Name = hostVethName;
      address = [
        "${router.hostTransitIpv4}/32"
        "${router.hostTransitIpv6}/128"
      ];
      routes = [
        {
          Destination = "${router.containerTransitIpv4}/32";
          Scope = "link";
        }
        {
          Destination = router.ipv4Route;
          Gateway = router.containerTransitIpv4;
          GatewayOnLink = true;
        }
        {
          Destination = "${router.containerTransitIpv6}/128";
          Scope = "link";
        }
        {
          Destination = router.ipv6Route;
          Gateway = router.containerTransitIpv6;
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

    # The router daemon needs Internet access to reach its control plane.
    # Packets received from Headscale peers do not match these source addresses.
    networking.edgeFirewall.extraForwardRules = [
      ''iifname "${hostVethPattern}" ip saddr ${router.containerTransitIpv4} accept''
    ];

    networking.nftables.tables."${router.containerName}-egress" = {
      family = "inet";
      content = ''
        chain prerouting {
          type filter hook prerouting priority mangle;
          iifname "${hostVethPattern}" ip saddr ${router.containerTransitIpv4} meta mark set ${chinanetMark}
        }

        chain postrouting {
          type nat hook postrouting priority srcnat;
          iifname "tailscale0" oifname "${hostVethPattern}" ip daddr ${router.ipv4Route} masquerade
          iifname "tailscale0" oifname "${hostVethPattern}" ip6 daddr ${router.ipv6Route} masquerade
        }
      '';
    };
  };
in
  lib.mkMerge (
    [
      {
        services.tailscale = {
          extraUpFlags = [
            "--advertise-connector"
            "--advertise-routes=${lib.concatStringsSep "," primaryAdvertisedRoutes}"
          ];
          serve = {
            enable = true;
            services = {
              bitmagnet2.endpoints."tcp:80" = "http://${config.services.bitmagnet.settings.http_server.port}";
              immich2.endpoints."tcp:80" = "tcp://127.0.0.1:2283";
              restic-115.endpoints."tcp:80" = "http://127.0.0.1:8006";
              restic-123pan.endpoints."tcp:80" = "http://127.0.0.1:8005";
              restic-nas.endpoints."tcp:80" = "http://127.0.0.1:8000";
            };
          };
        };
      }
    ]
    ++ lib.mapAttrsToList mkHeadscaleRouter headscaleRouters
  )

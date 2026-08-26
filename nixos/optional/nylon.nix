# Reusable NixOS module for the Nylon mesh router.
#
# Split responsibility with the server-maintenance Ansible repo:
#   * Nix: nylon binary, MPLS kernel setup, systemd services, local datapath.
#   * Ansible: keypair plus central/node YAML and rendered policy batches.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.nylon;
  exitsEnabled = cfg.exits != {};
  interfaceName = "nylon0";
  configDir = "/etc/nylon";
  centralConfigFile = "${configDir}/central.yaml";
  nodeConfigFile = "${configDir}/node.yaml";
  policyRoutingDir = "/var/lib/nylon/policy-routing";
  routes4File = "${policyRoutingDir}/routes4.batch";
  routes6File = "${policyRoutingDir}/routes6.batch";
  rules4File = "${policyRoutingDir}/rules4.batch";
  rules6File = "${policyRoutingDir}/rules6.batch";
  types = lib.types;
in {
  disabledModules = ["services/networking/nylon.nix"];
  imports = [./policy-routing.nix];

  options.services.nylon = {
    enable = lib.mkEnableOption "Nylon mesh router";

    overlay.nat.enable = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Whether to masquerade non-overlay sources leaving through Nylon.";
    };

    udpPort = lib.mkOption {
      type = types.port;
      default = 6622;
      description = "Nylon UDP transport source port.";
    };

    policyRouting.enable = lib.mkEnableOption "loading rendered Nylon policy rules through networking.policyRouting";

    cloudflareWarp = {
      enable = lib.mkEnableOption "a Cloudflare WARP Nylon exit";
      label = lib.mkOption {
        type = types.ints.positive;
        description = "MPLS label for the Cloudflare WARP exit.";
      };
      ipv6Address = lib.mkOption {
        type = types.singleLineStr;
        description = "IPv6 address assigned to this WARP registration, without the /128 prefix.";
      };
      reserved = lib.mkOption {
        type = types.singleLineStr;
        description = "24-bit WireGuard reserved value assigned to this WARP registration.";
      };
    };

    exits = lib.mkOption {
      type = types.attrsOf (types.submodule ({name, ...}: {
        options = {
          label = lib.mkOption {
            type = types.ints.positive;
            example = 100;
            description = "MPLS label for the ${name} exit.";
          };
          interface = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "wg-cloudflare";
            description = "Fixed egress interface, or null to follow the IPv4 default route.";
          };
          gateway4 = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "192.0.2.1";
            description = "IPv4 next hop for this MPLS exit; null is suitable for point-to-point interfaces.";
          };
          ipv4Address = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "192.0.2.2";
            description = "IPv4 SNAT address; null uses the first global address on the egress interface.";
          };
          ipv6Address = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "2001:db8::2";
            description = "IPv6 SNAT address; null uses the first global address on the egress interface.";
          };
        };
      }));
      default = {};
      description = "Named local MPLS exits.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (let
      nylonMssV6 = 1400 - 8 - 60;
    in {
      networking.nftables.enable = true;
      networking.nftables.tables.nylon = {
        family = "inet";
        content = ''
          chain prerouting-mss {
            type filter hook prerouting priority mangle; policy accept;
            iifname "${interfaceName}" tcp flags syn tcp option maxseg size > ${toString nylonMssV6} tcp option maxseg size set ${toString nylonMssV6}
          }
        '';
      };
    })

    {
      assertions = [
        {
          assertion =
            builtins.length (map (exit: exit.label) (lib.attrValues cfg.exits))
            == builtins.length (lib.unique (map (exit: exit.label) (lib.attrValues cfg.exits)));
          message = "Nylon exit labels must be unique.";
        }
      ];

      # mpls_iptunnel serves the WLT selector's `encap mpls` policy routes.
      boot.kernelModules = [
        "act_ct"
        "act_skbedit"
        "cls_flower"
        "mpls_router"
        "mpls_iptunnel"
      ];
      boot.kernel.sysctl."net.mpls.platform_labels" = 256;

      # `nylon` on PATH lets Ansible generate/verify keys and configs; python3
      # is what Ansible modules run under on this host.
      environment.systemPackages = [
        pkgs.nylon
        pkgs.python3
      ];

      systemd.tmpfiles.rules =
        [
          "d ${configDir} 0700 root root -"
        ]
        ++ lib.optionals cfg.policyRouting.enable [
          "d ${policyRoutingDir} 0755 root root -"
          "f ${routes4File} 0644 root root -"
          "f ${routes6File} 0644 root root -"
          "f ${rules4File} 0644 root root -"
          "f ${rules6File} 0644 root root -"
        ];

      systemd.services.nylon = {
        description = "Nylon mesh router";
        wants =
          ["network-online.target"]
          ++ lib.optional cfg.policyRouting.enable "nylon-routes.service"
          ++ lib.optional exitsEnabled "nylon-exit.service";
        after = ["network-online.target"];
        wantedBy = ["multi-user.target"];
        # nylon shells out to `ip` for interface/route setup.
        path = [pkgs.iproute2];
        unitConfig.ConditionPathExists = [
          centralConfigFile
          nodeConfigFile
        ];
        serviceConfig = {
          ExecStart = "${lib.getExe pkgs.nylon} run -c ${centralConfigFile} -n ${nodeConfigFile}";
          WorkingDirectory = configDir;
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };
    }

    (lib.mkIf cfg.overlay.nat.enable {
      networking.nftables.enable = true;
      networking.nftables.tables.nylon.content = ''
        chain overlay-nat-postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          oifname "${interfaceName}" ip saddr != 10.250.10.0/24 masquerade
          oifname "${interfaceName}" ip6 saddr != fd10:250:10::/64 masquerade
        }
      '';
    })

    (lib.mkIf cfg.policyRouting.enable {
      systemd.services.nylon-routes = {
        description = "Nylon MPLS route batches";
        after = ["nylon.service"];
        # A nylon restart recreates nylon0, dropping MPLS routes in the per-exit
        # tables; PartOf makes that restart re-run this unit.
        partOf = ["nylon.service"];
        wantedBy = ["multi-user.target"];
        path = [pkgs.iproute2];
        unitConfig.ConditionPathExists = [
          centralConfigFile
          nodeConfigFile
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = "10s";
        };
        script = ''
          for _ in {1..50}; do
            ip -brief link show dev ${interfaceName} 2>/dev/null | grep -qw LOWER_UP && break
            sleep 0.2
          done
          if ! ip -brief link show dev ${interfaceName} | grep -qw LOWER_UP; then
            echo "${interfaceName} not LOWER_UP; cannot apply Nylon route batches" >&2
            exit 1
          fi

          if [ -s ${routes4File} ]; then
            ip -4 -force -batch ${routes4File}
          fi
          if [ -s ${routes6File} ]; then
            ip -6 -force -batch ${routes6File}
          fi
        '';
      };
    })

    (lib.mkIf cfg.policyRouting.enable {
      networking.policyRouting = {
        ipv4.routingPolicyRules.wltOutlet = [{file = rules4File;}];
        ipv6.routingPolicyRules.wltOutlet = [{file = rules6File;}];
      };
    })

    (lib.mkIf cfg.cloudflareWarp.enable {
      networking = {
        nftables.enable = true;
        nftables.tables.nylon.content = ''
          set warp_endpoints_v4 {
            type ipv4_addr
            elements = { 162.159.192.1, 162.159.192.2, 162.159.192.3, 162.159.192.4, 162.159.192.5, 162.159.193.1, 162.159.193.2, 162.159.193.3, 162.159.193.4, 162.159.193.5 }
          }
          set warp_endpoints_v6 {
            type ipv6_addr
            elements = { 2606:4700:d0::a29f:c001, 2606:4700:d0::a29f:c002, 2606:4700:d0::a29f:c003, 2606:4700:d0::a29f:c004, 2606:4700:d0::a29f:c005 }
          }
          set warp_udp_ports {
            type inet_service
            elements = { 500, 1701, 2408, 4500 }
          }
          chain warp-in {
            type filter hook input priority mangle; policy accept;
            ip saddr @warp_endpoints_v4 udp sport @warp_udp_ports @th,72,24 set 0x0
            ip6 saddr @warp_endpoints_v6 udp sport @warp_udp_ports @th,72,24 set 0x0
          }
          chain warp-out {
            type filter hook output priority mangle; policy accept;
            ip daddr @warp_endpoints_v4 udp dport @warp_udp_ports @th,72,24 set ${cfg.cloudflareWarp.reserved}
            ip6 daddr @warp_endpoints_v6 udp dport @warp_udp_ports @th,72,24 set ${cfg.cloudflareWarp.reserved}
          }
        '';
        wireguard.interfaces.wg-cloudflare = {
          ips = [
            "172.16.0.2/32"
            "${cfg.cloudflareWarp.ipv6Address}/128"
          ];
          privateKeyFile = "/var/lib/wireguard/wg-cloudflare-private-key";
          allowedIPsAsRoutes = false;
          peers = [
            {
              publicKey = "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=";
              allowedIPs = [
                "0.0.0.0/0"
                "::/0"
              ];
              endpoint = "162.159.192.1:2408";
              persistentKeepalive = 25;
            }
          ];
        };
      };

      services.nylon.exits.warp = {
        label = cfg.cloudflareWarp.label;
        interface = "wg-cloudflare";
      };

      systemd = {
        services.nylon-exit = {
          after = ["systemd-networkd.service"];
          partOf = ["systemd-networkd.service"];
        };
        tmpfiles.rules = ["d /var/lib/wireguard 0700 root root -"];
      };
    })

    (lib.mkIf exitsEnabled {
      networking.nftables.enable = true;

      # tc act_ct tracks conntrack inline but never registers netfilter's
      # inbound conntrack/nat hooks, so replies would stay UNREPLIED and never
      # be reverse-translated. The masquerade rules in the Nylon or system NAT
      # register these hooks already; this anchor makes the exit independent.
      networking.nftables.tables.nylon.content = ''
        chain exit-track {
          type filter hook prerouting priority -300; policy accept;
          ct state established,related accept
        }
        chain exit-nat-prerouting {
          type nat hook prerouting priority -90; policy accept;
        }
        chain exit-nat-postrouting {
          type nat hook postrouting priority 90; policy accept;
        }
      '';
    })

    (lib.mkIf exitsEnabled {
      # ${interfaceName} is created by nylon at startup, and its MPLS input
      # flag dies with it, so this must re-run on every nylon restart (PartOf).
      # The LSP and tc filters live on the WAN interface and would survive, but
      # replacing them is idempotent.
      systemd.services.nylon-exit = {
        description = "Nylon MPLS exits: static LSPs and egress SNAT";
        after = ["nylon.service"];
        partOf = ["nylon.service"];
        wantedBy = ["multi-user.target"];
        path = [
          pkgs.iproute2
          pkgs.gawk
        ];
        unitConfig.ConditionPathExists = [
          centralConfigFile
          nodeConfigFile
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = "10s";
        };
        script = ''
          for _ in {1..50}; do
            ip link show ${interfaceName} >/dev/null 2>&1 && break
            sleep 0.2
          done
          if ! ip link show ${interfaceName} >/dev/null 2>&1; then
            echo "${interfaceName} absent; cannot configure Nylon exits" >&2
            exit 1
          fi

          # Accept MPLS packets nylon writes to its TUN after the outer pop.
          echo 1 > /proc/sys/net/mpls/conf/${interfaceName}/input
          tc qdisc replace dev ${interfaceName} clsact
          tc filter del dev ${interfaceName} ingress 2>/dev/null || true
          declare -A configured_interfaces=()
          ${lib.concatMapAttrsStringSep "\n" (name: exitConfig:
            (
              if exitConfig.interface != null
              then ''
                iface="${exitConfig.interface}"
                if ! ip link show "$iface" >/dev/null 2>&1; then
                  echo "egress interface $iface for Nylon exit ${name} is absent" >&2
                  exit 1
                fi
                ${
                  if exitConfig.gateway4 != null
                  then ''ip -f mpls route replace ${toString exitConfig.label} via inet ${exitConfig.gateway4} dev "$iface"''
                  else ''ip -f mpls route replace ${toString exitConfig.label} dev "$iface"''
                }
              ''
              else ''
                default=$(ip -4 route show default | head -1)
                gw=$(awk '{print $3}' <<< "$default")
                iface=$(awk '{print $5}' <<< "$default")
                if [ -z "$gw" ] || [ -z "$iface" ]; then
                  echo "no IPv4 default gateway for Nylon exit ${name}" >&2
                  exit 1
                fi
                ip -f mpls route replace ${toString exitConfig.label} via inet "$gw" dev "$iface"
              ''
            )
            + ''
              mark=$((0x10000 + ${toString exitConfig.label}))
              tc filter add dev ${interfaceName} ingress protocol mpls_uc pref ${toString exitConfig.label} \
                flower mpls_label ${toString exitConfig.label} action skbedit mark "$mark"

              if [[ ! -v "configured_interfaces[$iface]" ]]; then
                tc qdisc replace dev "$iface" clsact
                tc filter del dev "$iface" egress 2>/dev/null || true
                configured_interfaces["$iface"]=1
              fi

              filters=0
              ip4="${lib.optionalString (exitConfig.ipv4Address != null) exitConfig.ipv4Address}"
              if [ -z "$ip4" ]; then
                ip4=$(ip -o -4 addr show dev "$iface" scope global | awk '{print $4}' | cut -d/ -f1 | head -1)
              fi
              if [ -n "$ip4" ]; then
                tc filter add dev "$iface" egress protocol ip pref ${toString exitConfig.label} handle "$mark" fw \
                  action ct commit nat src addr "$ip4" pipe
                filters=$((filters + 1))
                echo "nylon-exit ${name}: IPv4 SNAT to $ip4 on $iface"
              fi
              ip6="${lib.optionalString (exitConfig.ipv6Address != null) exitConfig.ipv6Address}"
              if [ -z "$ip6" ]; then
                ip6=$(ip -o -6 addr show dev "$iface" scope global | awk '{print $4}' | cut -d/ -f1 | head -1)
              fi
              if [ -n "$ip6" ]; then
                tc filter add dev "$iface" egress protocol ipv6 pref ${toString (exitConfig.label + 1000)} handle "$mark" fw \
                  action ct commit nat src addr "$ip6" pipe
                filters=$((filters + 1))
                echo "nylon-exit ${name}: IPv6 SNAT to $ip6 on $iface"
              fi
              if [ "$filters" -eq 0 ]; then
                echo "no configured overlay address family is available on $iface" >&2
                exit 1
              fi
              echo "nylon-exit ${name}: label ${toString exitConfig.label} via $iface"
            '')
          cfg.exits}
        '';
      };
    })
  ]);
}

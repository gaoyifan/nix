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
  overlayConfigured = cfg.overlay.ipv4Subnet != null || cfg.overlay.ipv6Subnet != null;
  types = lib.types;
in {
  disabledModules = ["services/networking/nylon.nix"];

  options.services.nylon = {
    enable = lib.mkEnableOption "Nylon mesh router";

    package = lib.mkOption {
      type = types.package;
      default = pkgs.nylon;
      description = "Nylon package to run and expose on PATH.";
    };

    interfaceName = lib.mkOption {
      type = types.str;
      default = "nylon0";
      description = "Nylon TUN interface name.";
    };

    udpPort = lib.mkOption {
      type = types.port;
      default = 6622;
      description = "Nylon UDP transport source port.";
    };

    mtu = lib.mkOption {
      type = types.ints.positive;
      default = 1400;
      description = "Mesh-wide Nylon interface MTU.";
    };

    configDir = lib.mkOption {
      type = types.str;
      default = "/etc/nylon";
      description = "Directory containing Nylon node configuration.";
    };

    centralConfigFile = lib.mkOption {
      type = types.str;
      default = "${cfg.configDir}/central.yaml";
      defaultText = lib.literalExpression ''"${config.services.nylon.configDir}/central.yaml"'';
      description = "Path to Nylon central.yaml.";
    };

    nodeConfigFile = lib.mkOption {
      type = types.str;
      default = "${cfg.configDir}/node.yaml";
      defaultText = lib.literalExpression ''"${config.services.nylon.configDir}/node.yaml"'';
      description = "Path to Nylon node.yaml.";
    };

    overlay = {
      ipv4Subnet = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "10.0.10.0/24";
        description = "IPv4 overlay subnet used by exits for reverse translation.";
      };
      ipv6Subnet = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "fd00:10::/64";
        description = "IPv6 overlay subnet used by exits for reverse translation.";
      };
      nat.enable = lib.mkOption {
        type = types.bool;
        default = true;
        description = "Whether to masquerade non-overlay sources leaving through Nylon.";
      };
    };

    routeBatch = {
      enable = lib.mkOption {
        type = types.bool;
        default = true;
        description = "Whether to run rendered Nylon MPLS route batches.";
      };
      dir = lib.mkOption {
        type = types.str;
        default = "/var/lib/nylon/policy-routing";
        description = "Directory containing Nylon policy-routing batch fragments.";
      };
      ipv4File = lib.mkOption {
        type = types.str;
        default = "${cfg.routeBatch.dir}/routes4.batch";
        defaultText = lib.literalExpression ''"${config.services.nylon.routeBatch.dir}/routes4.batch"'';
        description = "IPv4 route batch rendered outside Nix.";
      };
      ipv6File = lib.mkOption {
        type = types.str;
        default = "${cfg.routeBatch.dir}/routes6.batch";
        defaultText = lib.literalExpression ''"${config.services.nylon.routeBatch.dir}/routes6.batch"'';
        description = "IPv6 route batch rendered outside Nix.";
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
      nylonMssV6 = cfg.mtu - 8 - 60;
    in {
      networking.nftables.enable = true;
      networking.nftables.tables.nylon-mss = {
        family = "inet";
        content = ''
          chain prerouting-mss {
            type filter hook prerouting priority mangle; policy accept;
            iifname "${cfg.interfaceName}" tcp flags syn tcp option maxseg size > ${toString nylonMssV6} tcp option maxseg size set ${toString nylonMssV6}
          }
        '';
      };
    })

    {
      assertions = [
        {
          assertion =
            !(cfg.overlay.nat.enable || exitsEnabled)
            || overlayConfigured;
          message = "Nylon NAT and exits require an overlay IPv4 or IPv6 subnet.";
        }
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
        cfg.package
        pkgs.python3
      ];

      systemd.tmpfiles.rules =
        [
          "d ${cfg.configDir} 0700 root root -"
        ]
        ++ lib.optionals cfg.routeBatch.enable [
          "d ${cfg.routeBatch.dir} 0755 root root -"
          "f ${cfg.routeBatch.dir}/routes4.batch 0644 root root -"
          "f ${cfg.routeBatch.dir}/routes6.batch 0644 root root -"
          "f ${cfg.routeBatch.dir}/rules4.batch 0644 root root -"
          "f ${cfg.routeBatch.dir}/rules6.batch 0644 root root -"
        ];

      systemd.services.nylon = {
        description = "Nylon mesh router";
        wants = ["network-online.target"];
        after = ["network-online.target"];
        wantedBy = ["multi-user.target"];
        # nylon shells out to `ip` for interface/route setup.
        path = [pkgs.iproute2];
        unitConfig.ConditionPathExists = [
          cfg.centralConfigFile
          cfg.nodeConfigFile
        ];
        serviceConfig = {
          ExecStart = "${lib.getExe cfg.package} run -c ${cfg.centralConfigFile} -n ${cfg.nodeConfigFile}";
          WorkingDirectory = cfg.configDir;
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };
    }

    (lib.mkIf (cfg.overlay.nat.enable && overlayConfigured) {
      networking.nftables.enable = true;
      networking.nftables.tables.nylon-nat = {
        family = "inet";
        content = ''
          chain postrouting {
            type nat hook postrouting priority srcnat; policy accept;
            ${lib.optionalString (cfg.overlay.ipv4Subnet != null) ''oifname "${cfg.interfaceName}" ip saddr != ${cfg.overlay.ipv4Subnet} masquerade''}
            ${lib.optionalString (cfg.overlay.ipv6Subnet != null) ''oifname "${cfg.interfaceName}" ip6 saddr != ${cfg.overlay.ipv6Subnet} masquerade''}
          }
        '';
      };
    })

    (lib.mkIf cfg.routeBatch.enable {
      systemd.services.nylon-routes = {
        description = "Nylon MPLS route batches";
        wants = ["nylon.service" "network-online.target"];
        after = ["nylon.service" "network-online.target"];
        # A nylon restart recreates nylon0, dropping MPLS routes in the per-exit
        # tables; PartOf makes that restart re-run this unit.
        partOf = ["nylon.service"];
        wantedBy = [
          "multi-user.target"
          "nylon.service"
        ];
        path = [pkgs.iproute2];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = "10s";
        };
        script = ''
          for _ in {1..50}; do
            ip -brief link show dev ${cfg.interfaceName} 2>/dev/null | grep -qw LOWER_UP && break
            sleep 0.2
          done
          if ! ip -brief link show dev ${cfg.interfaceName} | grep -qw LOWER_UP; then
            echo "${cfg.interfaceName} not LOWER_UP; cannot apply Nylon route batches" >&2
            exit 1
          fi

          if [ -s ${cfg.routeBatch.ipv4File} ]; then
            ip -4 -force -batch ${cfg.routeBatch.ipv4File}
          fi
          if [ -s ${cfg.routeBatch.ipv6File} ]; then
            ip -6 -force -batch ${cfg.routeBatch.ipv6File}
          fi
        '';
      };
    })

    (lib.mkIf exitsEnabled {
      networking.nftables.enable = true;

      # tc act_ct tracks conntrack inline but never registers netfilter's
      # inbound conntrack/nat hooks, so replies would stay UNREPLIED and never
      # be reverse-translated. The masquerade rules in nylon-nat/nat likely
      # register these hooks already; this anchor makes the exit independent.
      networking.nftables.tables.nylon-exit = {
        family = "inet";
        content = ''
          chain track {
            type filter hook prerouting priority -300; policy accept;
            ct state established,related accept
          }
          chain pre {
            type nat hook prerouting priority -90; policy accept;
          }
          chain post {
            type nat hook postrouting priority 90; policy accept;
          }
        '';
      };
    })

    (lib.mkIf (exitsEnabled && overlayConfigured) {
      # ${cfg.interfaceName} is created by nylon at startup, and its MPLS input
      # flag dies with it, so this must re-run on every nylon restart (PartOf).
      # The LSP and tc filters live on the WAN interface and would survive, but
      # replacing them is idempotent.
      systemd.services.nylon-exit = {
        description = "Nylon MPLS exits: static LSPs and egress SNAT";
        wants = ["nylon.service" "network-online.target"];
        after = ["nylon.service" "network-online.target"];
        partOf = ["nylon.service"];
        wantedBy = [
          "multi-user.target"
          "nylon.service"
        ];
        path = [
          pkgs.iproute2
          pkgs.gawk
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = "10s";
        };
        script = ''
          for _ in {1..50}; do
            ip link show ${cfg.interfaceName} >/dev/null 2>&1 && break
            sleep 0.2
          done
          if ! ip link show ${cfg.interfaceName} >/dev/null 2>&1; then
            echo "${cfg.interfaceName} absent; cannot configure Nylon exits" >&2
            exit 1
          fi

          # Accept MPLS packets nylon writes to its TUN after the outer pop.
          echo 1 > /proc/sys/net/mpls/conf/${cfg.interfaceName}/input
          tc qdisc replace dev ${cfg.interfaceName} clsact
          tc filter del dev ${cfg.interfaceName} ingress 2>/dev/null || true
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
              tc filter add dev ${cfg.interfaceName} ingress protocol mpls_uc pref ${toString exitConfig.label} \
                flower mpls_label ${toString exitConfig.label} action skbedit mark "$mark"

              if [[ ! -v "configured_interfaces[$iface]" ]]; then
                tc qdisc replace dev "$iface" clsact
                tc filter del dev "$iface" egress 2>/dev/null || true
                configured_interfaces["$iface"]=1
              fi

              filters=0
              ${lib.optionalString (cfg.overlay.ipv4Subnet != null) ''
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
              ''}
              ${lib.optionalString (cfg.overlay.ipv6Subnet != null) ''
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
              ''}
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

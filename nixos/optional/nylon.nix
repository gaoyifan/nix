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

    policyBatch = {
      enable = lib.mkOption {
        type = types.bool;
        default = true;
        description = "Whether to run the rendered Nylon policy-route batch.";
      };
      file = lib.mkOption {
        type = types.str;
        default = "/opt/nylon.batch";
        description = "Executable policy batch rendered outside Nix.";
      };
    };

    exit = {
      enable = lib.mkEnableOption "local Nylon MPLS exit";
      label = lib.mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
        example = 100;
        description = "MPLS label for this local exit.";
      };
      wanInterface = lib.mkOption {
        type = types.nullOr types.str;
        default = config.networking.homeRouter.wan.interface;
        defaultText = lib.literalExpression "config.networking.homeRouter.wan.interface";
        description = "WAN interface used by this local Nylon exit.";
      };
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
          assertion = !cfg.overlay.nat.enable || (cfg.overlay.ipv4Subnet != null && cfg.overlay.ipv6Subnet != null);
          message = "services.nylon.overlay.ipv4Subnet and ipv6Subnet must be set when Nylon overlay NAT is enabled.";
        }
        {
          assertion = !cfg.exit.enable || cfg.exit.label != null;
          message = "services.nylon.exit.label must be set when the local Nylon exit is enabled.";
        }
        {
          assertion = !cfg.exit.enable || cfg.exit.wanInterface != null;
          message = "services.nylon.exit.wanInterface must be set when the local Nylon exit is enabled.";
        }
        {
          assertion = !cfg.exit.enable || cfg.overlay.ipv4Subnet != null;
          message = "services.nylon.overlay.ipv4Subnet must be set when the local Nylon exit is enabled.";
        }
      ];

      # mpls_iptunnel serves the WLT selector's `encap mpls` policy routes.
      boot.kernelModules = ["mpls_router" "mpls_iptunnel"];
      boot.kernel.sysctl."net.mpls.platform_labels" = 256;

      # `nylon` on PATH lets Ansible generate/verify keys and configs; python3
      # is what Ansible modules run under on this host.
      environment.systemPackages = [
        cfg.package
        pkgs.python3
      ];

      systemd.tmpfiles.rules = [
        "d ${cfg.configDir} 0700 root root -"
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

    (lib.mkIf (cfg.overlay.nat.enable && cfg.overlay.ipv4Subnet != null && cfg.overlay.ipv6Subnet != null) {
      networking.nftables.enable = true;
      networking.nftables.tables.nylon-nat = {
        family = "inet";
        content = ''
          chain postrouting {
            type nat hook postrouting priority srcnat; policy accept;
            oifname "${cfg.interfaceName}" ip saddr != ${cfg.overlay.ipv4Subnet} masquerade
            oifname "${cfg.interfaceName}" ip6 saddr != ${cfg.overlay.ipv6Subnet} masquerade
          }
        '';
      };
    })

    (lib.mkIf cfg.policyBatch.enable {
      systemd.services.nylon-policy-batch = {
        description = "Nylon policy-route batch";
        wants = ["nylon.service"] ++ lib.optional config.services.wlt.enable "wlt-routing.service";
        after = ["nylon.service"] ++ lib.optional config.services.wlt.enable "wlt-routing.service";
        # A nylon restart recreates nylon0, dropping MPLS routes in the
        # per-exit tables; PartOf makes that restart re-run this unit.
        partOf = ["nylon.service"];
        wantedBy = [
          "multi-user.target"
          "nylon.service"
        ];
        path = [pkgs.iproute2];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          if [ -x ${cfg.policyBatch.file} ]; then
            for _ in $(seq 30); do
              ip link show ${cfg.interfaceName} >/dev/null 2>&1 && break
              sleep 1
            done
            if ip link show ${cfg.interfaceName} >/dev/null 2>&1; then
              ${cfg.policyBatch.file}
            else
              echo "${cfg.interfaceName} absent; skipping ${cfg.policyBatch.file}" >&2
            fi
          fi
        '';
      };
    })

    (lib.mkIf cfg.exit.enable {
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

    (lib.mkIf (cfg.exit.enable && cfg.exit.label != null && cfg.exit.wanInterface != null && cfg.overlay.ipv4Subnet != null) {
      # ${cfg.interfaceName} is created by nylon at startup, and its MPLS input
      # flag dies with it, so this must re-run on every nylon restart (PartOf).
      # The LSP and tc filters live on the WAN interface and would survive, but
      # replacing them is idempotent.
      systemd.services.nylon-exit = {
        description = "Nylon MPLS exit: static LSP + egress SNAT on ${cfg.exit.wanInterface}";
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
          for _ in $(seq 30); do
            ip link show ${cfg.interfaceName} >/dev/null 2>&1 && break
            sleep 1
          done
          if ! ip link show ${cfg.interfaceName} >/dev/null 2>&1; then
            echo "${cfg.interfaceName} absent (nylon not configured yet); skipping exit setup" >&2
            exit 0
          fi

          # Accept MPLS packets nylon writes to its TUN after the outer pop.
          echo 1 > /proc/sys/net/mpls/conf/${cfg.interfaceName}/input

          # Static LSP: pop the exit label and forward via the DHCP default
          # gateway. Its MAC also routes IPv6, like the Debian L2 exits.
          gw=""
          for _ in $(seq 60); do
            gw=$(ip -4 route show default dev ${cfg.exit.wanInterface} | awk '{print $3; exit}')
            [ -n "$gw" ] && break
            sleep 1
          done
          [ -n "$gw" ] || {
            echo "no IPv4 default gateway on ${cfg.exit.wanInterface} after wait" >&2
            exit 1
          }
          ip -f mpls route replace ${toString cfg.exit.label} via inet "$gw" dev ${cfg.exit.wanInterface}

          # Egress SNAT for the popped packets. The uplink is DHCP, so wait for
          # the address.
          ip4=""
          for _ in $(seq 60); do
            ip4=$(ip -o -4 addr show dev ${cfg.exit.wanInterface} scope global | awk '{print $4}' | cut -d/ -f1 | head -1)
            [ -n "$ip4" ] && break
            sleep 1
          done
          [ -n "$ip4" ] || {
            echo "no global IPv4 on ${cfg.exit.wanInterface} after wait" >&2
            exit 1
          }
          # This unit is the only user of the clsact egress hook on the WAN.
          tc qdisc replace dev ${cfg.exit.wanInterface} clsact
          tc filter del dev ${cfg.exit.wanInterface} egress 2>/dev/null || true
          tc filter add dev ${cfg.exit.wanInterface} egress protocol ip flower src_ip ${cfg.overlay.ipv4Subnet} \
            action ct commit nat src addr "$ip4" pipe
          echo "nylon-exit: SNAT ${cfg.overlay.ipv4Subnet} -> $ip4 on ${cfg.exit.wanInterface}"
        '';
      };
    })
  ]);
}

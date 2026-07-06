# wlt outlet selector (https://github.com/gaoyifan/wlt): LAN clients pick a
# nylon MPLS exit per source IP via a web portal, modeled on the el2 instance.
#
# Split responsibility with the server-maintenance Ansible repo:
#   * Nix (here): podman containers, base config.toml, the nftables `wlt`
#     table (src2mark maps + CN/overseas destination split), portal addresses
#     on lo, guard/pinned policy-routing rules, snapshot persistence wiring.
#   * Ansible (playbooks/nylon-wlt-deploy.yml): the per-exit outlets
#     (/var/lib/wlt/config.d/nylon.toml) and MPLS policy routes
#     (/opt/nylon.batch), both rendered from host_vars.
{
  config,
  inputs,
  pkgs,
  ...
}: let
  image = "ghcr.io/gaoyifan/wlt:main";

  # Shared portal addresses (wlt-ipv4/wlt-ipv6.gaof.net) bound on lo; LAN
  # clients reach them through this host because it is their default gateway.
  portalV4 = "198.18.255.254";
  portalV6 = "2001:2::ffff";

  overlayV4 = "10.250.10.0/24";
  overlayV6 = "fd10:250:10::/64";

  wgEl2 = config.services.secrets.nixos."somo-minisforum".wgEl2;

  configD = "/var/lib/wlt/config.d";
  persistDir = "/var/lib/wlt/persist";
  sshDir = "/var/lib/wlt/ssh";

  # Mesh-wide nylon interface MTU (node.yaml `mtu`, rendered by Ansible from
  # nylon_default_mtu) and the worst-case TCP MSS through an MPLS exit.
  nylonMtu = 1400;
  nylonMssV6 = nylonMtu - 8 - 60;
  snapshotFile = "${persistDir}/wlt_src2mark.conf";

  # nftables CN destination sets, same upstream lists as el2 uses:
  # chnroutes2 for IPv4, china-operator-ip for IPv6.
  cnSets = pkgs.runCommand "wlt-nft-cn-sets" {} ''
    mkdir -p $out
    gen() {
      local name=$1 type=$2 src=$3
      {
        echo "set $name {"
        echo "  type $type"
        echo "  flags constant, interval"
        echo "  elements = {"
        grep -v '^#' "$src" | awk 'NF { printf("    %s,\n", $1) }'
        echo "  }"
        echo "}"
      } > "$out/set-$name.conf"
    }
    gen cn ipv4_addr ${inputs.chnroutes2}/chnroutes.txt
    gen cn6 ipv6_addr ${inputs.china-operator-ip}/china6.txt
  '';

  # Base config; Ansible merges the nylon exits into the same outlet groups
  # via ${configD}/nylon.toml. This host has no local alternative uplinks, so
  # the base groups only carry the defaults.
  wltConfig = pkgs.writeText "wlt-config.toml" ''
    time_limits = [1, 4, 10, 24, 0] # 1小时, 4小时, 10小时, 24小时, 永久

    [flask]
    host = "::"
    port = 80
    debug = false

    [nftables]
    family = "inet"
    table = "wlt"
    map = "src2mark"        # IPv4 client src -> mark
    map_v6 = "src2mark6"    # IPv6 client src -> mark

    [portal]
    # Split-horizon hostnames for the dual-stack SPA (one address family
    # each); they resolve to the portal addresses bound on lo below.
    v4_host = "wlt-ipv4.gaof.net"
    v6_host = "wlt-ipv6.gaof.net"

    [[outlet_groups]]
    title = "国内出口"
    mask = 0xFF00
    [outlet_groups.outlets]
    "默认" = 0x0
    [outlet_groups.outlets_v6]
    "默认" = 0x0
    "禁用 IPv6" = 0xff00

    [[outlet_groups]]
    title = "海外出口"
    cn_last = true
    mask = 0xFF
    [outlet_groups.outlets]
    "默认" = 0x0
    [outlet_groups.outlets_v6]
    "默认" = 0x0
    "禁用 IPv6" = 0xff
  '';

  commonContainer = {
    inherit image;
    volumes = [
      "${wltConfig}:/app/config.toml:ro"
      "${configD}:/app/config.d:ro"
    ];
    extraOptions = [
      "--network=host"
      "--cap-add=NET_ADMIN"
    ];
  };
in {
  # Containers run with host networking only: podman is daemonless and its
  # netavark firewall driver only installs rules for bridged networks, so
  # nftables owns the ruleset alone.
  virtualisation.podman.enable = true;

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      wlt =
        commonContainer
        // {
          # Bind explicitly to the lo portal addresses: this host runs no
          # packet filter, so do not expose the portal on every interface.
          cmd = [
            "uv"
            "run"
            "gunicorn"
            "-c"
            "python:wlt.web"
            "-b"
            "${portalV4}:80"
            "-b"
            "[${portalV6}]:80"
            "wlt.web:app"
          ];
        };
      wlt-persist =
        commonContainer
        // {
          cmd = ["uv" "run" "wlt-persist"];
          volumes = commonContainer.volumes ++ ["${persistDir}:/etc/nftables"];
        };
      # SSH TUI for outlet selection (ssh -p 2222 <host>), same image and
      # config as the portal; the host key persists across restarts.
      wlt-ssh =
        commonContainer
        // {
          cmd = ["uv" "run" "wlt-ssh"];
          volumes = commonContainer.volumes ++ ["${sshDir}:/data"];
          environment.SSH_HOST_KEY = "/data/ssh_host_key";
        };
    };
  };

  systemd.tmpfiles.rules = [
    "d ${configD} 0755 root root -"
    "d ${persistDir} 0755 root root -"
    "d ${sshDir} 0700 root root -"
    # The ruleset includes the snapshot, so it must exist before nftables
    # loads (wlt-persist overwrites it every 5 minutes).
    "f ${snapshotFile} 0644 root root -"
  ];

  # Shared portal addresses on lo, managed declaratively by networkd (the
  # loopback 127.0.0.1/::1 addresses are kernel-owned and left alone).
  systemd.network.networks."60-lo-wlt-portal" = {
    matchConfig.Name = "lo";
    address = [
      "${portalV4}/32"
      "${portalV6}/128"
    ];
    linkConfig.RequiredForOnline = "no";
  };

  # All packet filtering on this host is declared in nix (podman containers
  # use host networking only, incus only attaches to the unmanaged bridges,
  # tailscale runs with netfilter-mode=off), so flush the whole ruleset on
  # reload to keep kernel state exactly consistent with this configuration.
  networking.nftables.flushRuleset = true;

  networking.nftables.tables.wlt = {
    family = "inet";
    content = ''
      include "${cnSets}/set-cn.conf"
      include "${cnSets}/set-cn6.conf"

      map src2mark {
        type ipv4_addr : mark
        flags interval, timeout
      }
      map src2mark6 {
        type ipv6_addr : mark
        flags timeout
      }

      chain prerouting {
        type filter hook prerouting priority mangle - 1; policy accept;
        # src2mark: high byte selects the CN outlet, low byte the overseas one
        ip daddr @cn    meta mark set ip saddr map @src2mark meta mark set mark >> 8
        ip daddr != @cn meta mark set ip saddr map @src2mark meta mark set mark & 0xff
        ip6 daddr @cn6    meta mark set ip6 saddr map @src2mark6 meta mark set mark >> 8
        ip6 daddr != @cn6 meta mark set ip6 saddr map @src2mark6 meta mark set mark & 0xff
        # Default overseas egress for LAN clients without an explicit
        # selection: IPv4 via "JP Tokyo | ALVIDI" (0x42), IPv6 via "JP Tokyo
        # | Cloudflare WARP" (0x44); marks from nylon.toml / nylon.batch. CN
        # destinations keep mark 0 and leave via the WAN uplink. Only the
        # LAN bridges: WAN return traffic and forwarded tailnet flows (exit
        # node users) keep their current path.
        iifname { "br-gnet", "br-somo" } ip daddr != @cn meta mark 0 meta mark set 0x42
        iifname { "br-gnet", "br-somo" } ip6 daddr != @cn6 meta mark 0 meta mark set 0x44
      }

      # Host-originated IPv4 overseas traffic uses the dedicated WireGuard
      # egress. Overseas IPv6 is disabled because that tunnel is IPv4-only.
      # `type route` re-runs the routing decision after the mark changes.
      # Exemptions: anything already marked (tailscale sockets carry 0x80000)
      # and nylon's own UDP transport (sport 6622), which must reach its peers
      # via the real uplink or the MPLS default would loop through itself.
      chain output {
        type route hook output priority mangle; policy accept;
        meta mark != 0 return
        udp sport 6622 return
        ip daddr != @cn meta mark set ${wgEl2.mark}
        ip6 daddr != @cn6 meta mark set 0xff
      }

      # MPLS-encapped exits shrink the path MTU below the LAN's; clamp TCP
      # so clients do not rely on PMTUD. Postrouting (rather than forward)
      # also covers host-originated flows, whose sockets negotiate MSS
      # against the unmarked route (enp3s0, MTU 1500) before the output
      # chain diverts them to nylon0. rt mtu accounts for the MPLS label
      # headroom on the encap routes automatically.
      chain postrouting {
        type filter hook postrouting priority mangle; policy accept;
        tcp flags syn tcp option maxseg size set rt mtu
      }

      # Reverse direction for nylon ingress: the peer's advertised MSS
      # governs what this side sends, and for host flows an oversized local
      # segment would generate a PMTU exception in the main table (exception
      # lookups ignore the fwmark), which defeats the suppress_prefixlength
      # guard and flips the live flow back to enp3s0, breaking the NAT'd
      # connection. ${toString nylonMssV6} = ${toString nylonMtu} (mesh MTU,
      # Ansible nylon_default_mtu) - 8 (MPLS labels) - 60 (IPv6+TCP).
      chain prerouting-mss {
        type filter hook prerouting priority mangle; policy accept;
        iifname "nylon0" tcp flags syn tcp option maxseg size > ${toString nylonMssV6} tcp option maxseg size set ${toString nylonMssV6}
      }

      # The SSH selector (wlt-ssh) listens on 2222; let LAN clients reach it
      # on the portal addresses' plain SSH port.
      chain portal-dnat {
        type nat hook prerouting priority dstnat; policy accept;
        ip daddr ${portalV4} tcp dport 22 dnat ip to ${portalV4}:2222
        ip6 daddr ${portalV6} tcp dport 22 dnat ip6 to [${portalV6}]:2222
      }
    '';
  };

  # LAN traffic leaving via nylon0 must be SNAT'd to this node's overlay
  # address: the exit nodes only reverse-translate the overlay ranges.
  networking.nftables.tables.nylon-nat = {
    family = "inet";
    content = ''
      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "nylon0" ip saddr != ${overlayV4} masquerade
        oifname "nylon0" ip6 saddr != ${overlayV6} masquerade
      }
    '';
  };

  # Host-originated packets marked for the WireGuard egress may keep the
  # source address chosen before the output-chain reroute. SNAT them to this
  # node's tunnel address so the peer can return traffic.
  networking.nftables.tables.wg-el2-nat = {
    family = "ip";
    content = ''
      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "${wgEl2.interfaceName}" meta mark ${wgEl2.mark} masquerade
      }
    '';
  };

  # Restore the persisted outlet selections after the table is recreated.
  networking.nftables.ruleset = ''
    include "${snapshotFile}"
  '';

  # The snapshot lives outside the store; drop its include for the sandboxed
  # build-time `nft --check` (libredirect does not catch nft's include open).
  networking.nftables.preCheckRuleset = ''
    sed 's|include "${snapshotFile}"||' -i ruleset.conf
  '';

  # Policy-routing skeleton for the wlt fwmark scheme. The per-exit MPLS
  # tables and fwmark rules come from the Ansible-rendered /opt/nylon.batch;
  # rerun this service after Ansible updates it. This stays a oneshot script
  # rather than systemd.network RoutingPolicyRule: the batch's MPLS-encap
  # routes are inexpressible in networkd anyway, and letting networkd manage
  # part of the rule DB risks its foreign-rule cleanup fighting the
  # Ansible/tailscale rules.
  systemd.services.wlt-routing = {
    description = "nylon policy routing for the wlt fwmark scheme";
    wants = ["nylon.service"];
    after = ["nylon.service"];
    # A nylon restart recreates nylon0, dropping the MPLS routes in the
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
      # Idempotent `ip rule` install: drop any previous instance, then add.
      # Leading -4/-6 selects the family; without it the rule is dual-stack.
      rule() {
        case $1 in
          -4 | -6)
            local fam=$1
            shift
            ip "$fam" rule del "$@" 2>/dev/null || true
            ip "$fam" rule add "$@"
            ;;
          *)
            rule -4 "$@"
            rule -6 "$@"
            ;;
        esac
      }

      # Local and tailscale (table 52) destinations must win over the
      # fwmark rules (pref 10) that only carry default routes.
      rule pref 5 lookup main suppress_prefixlength 0
      rule pref 6 lookup 52 suppress_prefixlength 0
      rule -4 pref 7 fwmark ${wgEl2.mark}/0xffffffff lookup ${wgEl2.routeTable}

      # "禁用 IPv6" outlet: final fwmark 0xff sends v6 to an unreachable table.
      ip -6 route replace unreachable default table 5255
      rule -6 pref 10 fwmark 0xff/0xff lookup 5255

      # Per-exit MPLS routes need the nylon0 device; wait for nylon to
      # bring it up (the unit may be condition-skipped before Ansible ran).
      if [ -x /opt/nylon.batch ]; then
        for _ in $(seq 30); do
          ip link show nylon0 >/dev/null 2>&1 && break
          sleep 1
        done
        if ip link show nylon0 >/dev/null 2>&1; then
          /opt/nylon.batch
        else
          echo "nylon0 absent; skipping /opt/nylon.batch" >&2
        fi
      fi
    '';
  };
}

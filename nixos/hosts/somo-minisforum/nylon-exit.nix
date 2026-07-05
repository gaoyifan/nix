# Nylon MPLS exit over the enp3s0 uplink (中国移动, exit label 100, IPv4 only:
# host_vars exit_ipv6 is empty, so no selector routes v6 through this exit and
# the datapath below only SNATs v4).
#
# As a wlt selector this host still offers v6 exits (remote ones): that
# direction relies on nylon0's bound overlay address (fd10:250:10::28) for the
# `oifname nylon0` masquerade in wlt.nix, not on anything here.
#
# Unlike the Debian exit nodes (patched FRR programming the static LSP), the
# whole exit datapath is expressed with iproute2 + nftables here; Ansible only
# advertises the exit in host_vars (exits / nylon_advertise_exit_node with
# frr_skip: true, so frr-deploy and exit-snat-deploy leave this host alone).
#
# Datapath: nylon pops the outer node-id label (28) and writes the remaining
# MPLS(100)+IP packet to nylon0; the kernel (mpls input enabled below) pops the
# inner label via the static LSP and forwards out enp3s0. That MPLS forwarding
# path bypasses netfilter nat/postrouting, so a plain masquerade never sees the
# packet -- SNAT happens at tc clsact egress (act_ct) instead, committed to
# conntrack so replies reverse-NAT on the normal ingress path.
{pkgs, ...}: let
  exitLabel = 100;
  wanIface = "enp3s0";
  overlayV4 = "10.250.10.0/24";
in {
  # tc act_ct tracks conntrack inline but never registers netfilter's inbound
  # conntrack/nat hooks, so replies would stay UNREPLIED and never be
  # reverse-translated. The masquerade rules in nylon-nat/nat likely register
  # these hooks already; this anchor makes the exit independent of them.
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

  # nylon0 is created by nylon at startup, and its mpls input flag dies with
  # it, so this must re-run on every nylon restart (PartOf). The LSP and tc
  # filters live on ${wanIface} and would survive, but replacing them is
  # idempotent.
  systemd.services.nylon-exit = {
    description = "Nylon MPLS exit: static LSP + egress SNAT on ${wanIface}";
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
        ip link show nylon0 >/dev/null 2>&1 && break
        sleep 1
      done
      if ! ip link show nylon0 >/dev/null 2>&1; then
        echo "nylon0 absent (nylon not configured yet); skipping exit setup" >&2
        exit 0
      fi

      # Accept MPLS packets nylon writes to its TUN after the outer pop.
      echo 1 > /proc/sys/net/mpls/conf/nylon0/input

      # Static LSP: pop label ${toString exitLabel} and forward via the DHCP
      # default gateway (its MAC also routes IPv6, like the Debian L2 exits).
      gw=""
      for _ in $(seq 60); do
        gw=$(ip -4 route show default dev ${wanIface} | awk '{print $3; exit}')
        [ -n "$gw" ] && break
        sleep 1
      done
      [ -n "$gw" ] || {
        echo "no IPv4 default gateway on ${wanIface} after wait" >&2
        exit 1
      }
      ip -f mpls route replace ${toString exitLabel} via inet "$gw" dev ${wanIface}

      # Egress SNAT for the popped packets (see header). The uplink is DHCP,
      # so wait for the address.
      ip4=""
      for _ in $(seq 60); do
        ip4=$(ip -o -4 addr show dev ${wanIface} scope global | awk '{print $4}' | cut -d/ -f1 | head -1)
        [ -n "$ip4" ] && break
        sleep 1
      done
      [ -n "$ip4" ] || {
        echo "no global IPv4 on ${wanIface} after wait" >&2
        exit 1
      }
      # This unit is the only user of the clsact egress hook on ${wanIface}.
      tc qdisc replace dev ${wanIface} clsact
      tc filter del dev ${wanIface} egress 2>/dev/null || true
      tc filter add dev ${wanIface} egress protocol ip flower src_ip ${overlayV4} \
        action ct commit nat src addr "$ip4" pipe
      echo "nylon-exit: SNAT ${overlayV4} -> $ip4 on ${wanIface}"
    '';
  };
}

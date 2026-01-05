# nftables firewall configuration
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.router;
  lanIf = cfg.lan.ifname;
  pppIf = cfg.pppoe.ifname;
  wgIf = cfg.wgWan.ifname;
  tsEnabled = cfg.tailscale.enable;
  wgMark = cfg.policyRouting.wgMark;
  lanSubnet = "${cfg.lan.address}/${toString cfg.lan.prefixLength}";

  wgDestsElements =
    if cfg.policyRouting.wgDestinations == []
    then ""
    else "elements = { ${lib.concatStringsSep ", " cfg.policyRouting.wgDestinations} }";
in {
  networking.nftables = {
    enable = true;
    flushRuleset = true;
    checkRuleset = true;

    ruleset = ''
      define LAN_IF = "${lanIf}"
      define PPP_IF = "${pppIf}"
      define WG_IF  = "${wgIf}"
      ${
        if tsEnabled
        then ''define TRUSTED_IFS = { $LAN_IF, "tailscale0" }''
        else ''define TRUSTED_IFS = { $LAN_IF }''
      }
      define WAN_IFS = { $PPP_IF, $WG_IF }

      # Policy routing marks
      table inet mangle {
        set wg_destinations {
          type ipv4_addr
          flags interval
          ${wgDestsElements}
        }

        chain prerouting {
          type filter hook prerouting priority mangle; policy accept;
          ct state established,related meta mark set ct mark
          ct state new iifname $TRUSTED_IFS jump classify_traffic
        }

        chain classify_traffic {
          ip daddr @wg_destinations meta mark set ${toString wgMark} counter
          meta mark != 0 ct mark set meta mark
        }

        chain output {
          type route hook output priority mangle; policy accept;
          ct state established,related meta mark set ct mark
        }
      }

      # Firewall
      table inet filter {
        chain input {
          type filter hook input priority filter; policy drop;
          iif "lo" accept
          ct state established,related accept
          ct state invalid drop
          ip protocol icmp accept
          ip6 nexthdr icmpv6 accept

          tcp dport 22 accept

          iifname $TRUSTED_IFS udp dport { 53, 67 } accept
          iifname $TRUSTED_IFS tcp dport { 53, ${toString cfg.adguard.webPort} } accept

          iifname $PPP_IF udp dport { 41641, ${toString cfg.wgWan.listenPort} } accept

          iifname $WAN_IFS limit rate 5/minute log prefix "nftables-drop: " drop
        }

        chain forward {
          type filter hook forward priority filter; policy drop;
          ct state established,related accept
          ct state invalid drop

          ${lib.optionalString tsEnabled ''
        iifname $LAN_IF oifname "tailscale0" accept
        iifname "tailscale0" oifname $LAN_IF accept
      ''}

          iifname $TRUSTED_IFS oifname $WAN_IFS accept
          limit rate 5/minute log prefix "nftables-fwd-drop: " drop
        }

        chain output {
          type filter hook output priority filter; policy accept;
        }
      }

      # NAT
      table ip nat {
        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          ip saddr ${lanSubnet} oifname $PPP_IF masquerade
          ip saddr ${lanSubnet} oifname $WG_IF masquerade
          ${lib.optionalString tsEnabled ''
        iifname "tailscale0" oifname { $PPP_IF, $WG_IF } masquerade
      ''}
        }
      }
    '';
  };
}

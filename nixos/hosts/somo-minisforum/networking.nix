# Network configuration for somo-minisforum.
#
# The host acts as a gateway for two independent LANs:
#   WAN: enp3s0 (Realtek 2.5G, DHCP from the upstream LAN)
#   br-gnet: enp4s0 VLAN 652 + wlp6s0 (hostapd AP), 100.65.2.0/24
#   br-somo: enp4s0 untagged + Incus guests, 100.65.3.0/24
#
# enp4s0 is a trunk port: a VLAN device on a bridge port grabs tagged frames
# before the bridge does, so untagged traffic lands in br-somo while VLAN 652
# lands in br-gnet.
#
# IPv6: the host announces a ULA /64 per bridge via router advertisements, so
# guests autoconfigure with SLAAC. DHCPPrefixDelegation additionally hands out
# a global /64 per bridge whenever the upstream ever offers DHCPv6-PD (it does
# not today).
let
  mkLanBridgeNetwork = name: hostV4: hostV6: ulaPrefix: {
    matchConfig.Name = name;
    address = [hostV4 hostV6];
    networkConfig = {
      DHCP = "no";
      # Keep the bridge (and the services bound to it) up even when no cable
      # or VM is attached.
      ConfigureWithoutCarrier = true;
      # This host is the router on these segments.
      IPv6AcceptRA = false;
      IPv6SendRA = true;
      DHCPPrefixDelegation = true;
    };
    ipv6Prefixes = [{Prefix = ulaPrefix;}];
    linkConfig.RequiredForOnline = "no";
  };
in {
  networking.hostName = "somo-minisforum";
  networking.useDHCP = false;
  networking.useNetworkd = true;

  # Skip the NixOS firewall abstraction and declare only the nftables rules
  # we actually need (NAT for the VM LANs plus the br-somo isolation below).
  networking.firewall.enable = false;
  networking.nftables.enable = true;
  # Masquerade the whole CGNAT block: it covers both LAN bridges
  # (100.65.2.0/24, 100.65.3.0/24) and Tailscale peer addresses, which need
  # SNAT when this node forwards their traffic as an exit node
  # (netfilter-mode=off means tailscaled installs no NAT of its own).
  networking.nftables.tables.nat = {
    family = "ip";
    content = ''
      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ip saddr 100.64.0.0/10 oifname "enp3s0" masquerade
      }
    '';
  };

  # Stateful isolation: br-somo guests must not reach the tailnet, but
  # tailnet peers may still initiate connections into br-somo (the return
  # traffic matches established/related). No other interface is filtered.
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

  # Forward guest traffic between the LAN bridges and the WAN port.
  # (Tailscale's useRoutingFeatures = "server" sets the same sysctls; keep
  # them explicit so routing does not silently depend on the Tailscale
  # module.)
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = true;
    "net.ipv6.conf.all.forwarding" = true;
  };

  services.resolved.enable = true;

  systemd.network = {
    enable = true;
    # The wlt/nylon policy routes and rules (wlt-routing service,
    # /opt/nylon.batch) live outside networkd; without this, every networkd
    # restart silently deletes them as "foreign".
    config.networkConfig.ManageForeignRoutes = false;
    config.networkConfig.ManageForeignRoutingPolicyRules = false;
    networks."10-enp3s0" = {
      matchConfig.Name = "enp3s0";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
      # The ISP resolvers handed out here are poisoned; the host resolves
      # via Cloudflare over the nylon exit instead (see dnsmasq.nix).
      dhcpV4Config.UseDNS = false;
      dhcpV6Config.UseDNS = false;
      ipv6AcceptRAConfig.UseDNS = false;
      linkConfig.RequiredForOnline = "routable";
    };

    netdevs."20-br-gnet".netdevConfig = {
      Kind = "bridge";
      Name = "br-gnet";
    };
    netdevs."20-br-somo".netdevConfig = {
      Kind = "bridge";
      Name = "br-somo";
    };
    netdevs."25-enp4s0-vlan652" = {
      netdevConfig = {
        Kind = "vlan";
        Name = "enp4s0.652";
      };
      vlanConfig.Id = 652;
    };

    networks."30-enp4s0" = {
      matchConfig.Name = "enp4s0";
      vlan = ["enp4s0.652"];
      networkConfig.Bridge = "br-somo";
      linkConfig.RequiredForOnline = "no";
    };
    networks."31-enp4s0-vlan652" = {
      matchConfig.Name = "enp4s0.652";
      networkConfig.Bridge = "br-gnet";
      linkConfig.RequiredForOnline = "no";
    };

    # The host is the gateway on both bridges; dnsmasq serves DHCP/DNS.
    networks."40-br-gnet" =
      mkLanBridgeNetwork "br-gnet"
      "100.65.2.254/24"
      "fd9a:2d16:5c3e:2::254/64"
      "fd9a:2d16:5c3e:2::/64";
    networks."41-br-somo" =
      mkLanBridgeNetwork "br-somo"
      "100.65.3.254/24"
      "fd9a:2d16:5c3e:3::254/64"
      "fd9a:2d16:5c3e:3::/64";
  };
}

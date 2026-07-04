# Network configuration for somo-minisforum.
#
# The host acts as a gateway for its VMs:
#   WAN: enp4s0 (Intel I226-V 2.5G, DHCP from the upstream LAN)
#   LAN: br0 = enp3s0 (Realtek 2.5G) + Incus guests, 100.65.2.0/24
{
  networking.hostName = "somo-minisforum";
  networking.useDHCP = false;
  networking.useNetworkd = true;

  # No packet filtering on this host: skip the NixOS firewall abstraction and
  # declare only the nftables rules we actually need (NAT for the VM LAN).
  networking.firewall.enable = false;
  networking.nftables.enable = true;
  # Masquerade the whole CGNAT block: it covers both the VM LAN
  # (100.65.2.0/24) and Tailscale peer addresses, which need SNAT when this
  # node forwards their traffic as an exit node (netfilter-mode=off means
  # tailscaled installs no NAT of its own).
  networking.nftables.tables.nat = {
    family = "ip";
    content = ''
      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ip saddr 100.64.0.0/10 oifname "enp4s0" masquerade
      }
    '';
  };

  # Forward guest traffic between br0 and the WAN port. (Tailscale's
  # useRoutingFeatures = "server" sets the same sysctls; keep them explicit
  # so NAT does not silently depend on the Tailscale module.)
  boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = true;

  services.resolved.enable = true;

  systemd.network = {
    enable = true;
    networks."10-enp4s0" = {
      matchConfig.Name = "enp4s0";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
      linkConfig.RequiredForOnline = "routable";
    };

    # br0: LAN bridge for Incus VMs and the physical enp3s0 port. The host
    # is the gateway (100.65.2.254); AdGuard Home serves DHCP/DNS on it.
    netdevs."20-br0" = {
      netdevConfig = {
        Kind = "bridge";
        Name = "br0";
      };
    };
    networks."30-enp3s0" = {
      matchConfig.Name = "enp3s0";
      networkConfig.Bridge = "br0";
      linkConfig.RequiredForOnline = "no";
    };
    networks."40-br0" = {
      matchConfig.Name = "br0";
      address = ["100.65.2.254/24"];
      networkConfig = {
        DHCP = "no";
        # Keep br0 (and the services bound to it) up even when no cable or
        # VM is attached.
        ConfigureWithoutCarrier = true;
      };
      linkConfig.RequiredForOnline = "no";
    };
  };
}

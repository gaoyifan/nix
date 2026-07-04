# Tailscale for internal access only: it must not touch the host firewall
# (netfilter-mode=off) or DNS (accept-dns=false). The node advertises the VM
# LAN (100.65.2.0/24) and acts as an exit node.
{config, ...}: {
  services.tailscale = {
    enable = true;
    authKeyFile = "${config.services.secrets.filesDir}/nixos/somo-minisforum/tailscale-auth-key";
    # Enable IPv4/IPv6 forwarding sysctls for subnet routing / exit node.
    useRoutingFeatures = "server";
    extraUpFlags = [
      "--accept-dns=false"
      "--accept-routes"
      "--advertise-exit-node"
      "--advertise-routes=100.65.2.0/24"
      "--netfilter-mode=off"
      "--snat-subnet-routes=false"
    ];
  };
}

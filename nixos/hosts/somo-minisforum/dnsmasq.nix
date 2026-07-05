# dnsmasq: DNS and DHCP for both LAN bridges (AdGuard Home only supports a
# single DHCP interface, so it was replaced when br-somo was added).
#   br-gnet: 100.65.2.0/24
#   br-somo: 100.65.3.0/24
# DHCP clients register under *.somo.gaof.net, so hostnames resolve via
# dig @100.65.2.254 <name>.somo.gaof.net.
{
  config,
  lib,
  ...
}: let
  lanDomain = "somo.gaof.net";

  # Static DHCP leases come from the (secret) VM definitions: any VM with a
  # `staticLease` attribute gets a MAC-bound reservation and a DNS name.
  vms = config.services.secrets.nixos."somo-minisforum".vms;
  staticLeases =
    lib.mapAttrsToList
    (name: vm: "${vm.devices.eth0.hwaddr},${vm.staticLease},${name}")
    (lib.filterAttrs (_: vm: vm ? staticLease) vms);
in {
  services.dnsmasq = {
    enable = true;
    # The host itself keeps using systemd-resolved (upstream DHCP DNS);
    # dnsmasq only serves the LAN bridges.
    resolveLocalQueries = false;
    settings = {
      # bind-dynamic (instead of bind-interfaces) tolerates the bridges
      # appearing after dnsmasq starts and stays off every other interface.
      bind-dynamic = true;
      interface = ["br-gnet" "br-somo"];

      # Mainland-reachable public resolvers (AliDNS, DNSPod); ignore
      # /etc/resolv.conf, which points at resolved's stub.
      no-resolv = true;
      server = ["223.5.5.5" "119.29.29.29"];

      # DHCP hostnames live under the LAN domain and never leak upstream.
      domain = lanDomain;
      local = "/${lanDomain}/";
      expand-hosts = true;

      # One pool per bridge; dnsmasq matches each range to the interface
      # subnet and advertises the interface address as gateway and DNS.
      # .1-.99 is reserved for static assignments (dhcp-host or in-guest).
      dhcp-range = [
        "100.65.2.100,100.65.2.200,24h"
        "100.65.3.100,100.65.3.200,24h"
      ];
      dhcp-host = staticLeases;
      dhcp-authoritative = true;
    };
  };
}

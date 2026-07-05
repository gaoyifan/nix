# dnsmasq: DNS and DHCP for both LAN bridges (AdGuard Home only supports a
# single DHCP interface, so it was replaced when br-somo was added).
#   br-gnet: 100.65.2.0/24
#   br-somo: 100.65.3.0/24
# DHCP clients register under *.somo.gaof.net, so hostnames resolve via
# dig @100.65.2.254 <name>.somo.gaof.net.
#
# Upstream resolution goes through diverge (gaoyifan/diverge-rs, modeled on
# the el2 instance): CN domains are answered by AliDNS over plain UDP, and
# anything resolving outside chnroutes goes to Cloudflare DoH, so poisoned
# answers for blocked domains (e.g. www.youtube.com) never reach clients.
# The DoH connection itself rides the host's default overseas egress (the
# nylon Tokyo exit, see wlt.nix), which keeps it reachable and clean.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  lanDomain = "somo.gaof.net";

  divergeListen = "127.0.0.1:1054";

  divergeConf = pkgs.writeText "diverge.conf" ''
    [global]
    listen = ${divergeListen}

    [CN]
    addresses = 223.5.5.5 223.6.6.6
    protocol = udp
    port = 53
    ips = chnroutes.txt

    [X]
    addresses = 1.1.1.1 1.0.0.1
    protocol = https
    tls_dns_name = cloudflare-dns.com
  '';

  # Static DHCP leases come from the (secret) VM definitions: any VM with a
  # `staticLease` attribute gets a MAC-bound reservation and a DNS name.
  vms = config.services.secrets.nixos."somo-minisforum".vms;
  staticLeases =
    lib.mapAttrsToList
    (name: vm: "${vm.devices.eth0.hwaddr},${vm.staticLease},${name}")
    (lib.filterAttrs (_: vm: vm ? staticLease) vms);
in {
  # docker with host networking and no netfilter management, same as the wlt
  # containers (see wlt.nix).
  virtualisation.oci-containers.containers.diverge = {
    image = "ghcr.io/gaoyifan/diverge-rs:master";
    volumes = [
      "${inputs.chnroutes2}/chnroutes.txt:/chnroutes.txt:ro"
      "${divergeConf}:/diverge.conf:ro"
    ];
    extraOptions = ["--network=host"];
  };

  # The host resolves through diverge too (the ISP resolvers from DHCP are
  # poisoned); enp3s0's DHCP/RA DNS is ignored in networking.nix. LAN
  # hostnames still resolve via dnsmasq on the br-gnet address.
  services.resolved.domains = ["~."];
  services.resolved.settings.Resolve.DNS = [divergeListen];
  systemd.network.networks."40-br-gnet" = {
    dns = ["100.65.2.254"];
    domains = ["~${lanDomain}"];
  };

  services.dnsmasq = {
    enable = true;
    # The host uses resolved -> diverge directly; dnsmasq only serves the
    # LAN bridges.
    resolveLocalQueries = false;
    settings = {
      # bind-dynamic (instead of bind-interfaces) tolerates the bridges
      # appearing after dnsmasq starts and stays off every other interface.
      bind-dynamic = true;
      interface = ["br-gnet" "br-somo"];

      # All queries go to the local diverge splitter; ignore
      # /etc/resolv.conf, which points at resolved's stub.
      no-resolv = true;
      server = ["127.0.0.1#1054"];

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

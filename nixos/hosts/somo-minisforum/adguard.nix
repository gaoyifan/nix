# AdGuard Home: DNS and DHCP for the br0 VM LAN (100.65.2.0/24).
# DHCP clients register under *.somo.gaof.net, so VM hostnames resolve via
# dig @100.65.2.254 <name>.somo.gaof.net.
{config, ...}: let
  lanAddress = "100.65.2.254";
  lanDomain = "somo.gaof.net";
in {
  services.adguardhome = {
    enable = true;
    # The host runs no packet filter; exposure is limited by binding DNS and
    # the web UI to the br0 address only.
    openFirewall = false;
    allowDHCP = true;
    mutableSettings = false;

    settings = {
      http.address = "${lanAddress}:3000";

      users = [
        {
          name = "admin";
          # Path concatenation (not string interpolation) so readFile reads
          # the source tree directly instead of an unrealised store path.
          password = builtins.readFile (config.services.secrets.filesDir + "/nixos/adguard-password-hash");
        }
      ];

      dns = {
        bind_hosts = ["127.0.0.1" lanAddress];
        port = 53;
        # Mainland-reachable public resolvers (AliDNS, DNSPod).
        upstream_dns = ["223.5.5.5" "119.29.29.29"];
        # Only used to resolve DoH/DoT upstream hostnames (ours are plain
        # IPs), but the NixOS module requires the field to exist.
        bootstrap_dns = ["223.5.5.5" "119.29.29.29"];
        # AGH answers DHCP hostname (A) queries only for clients from
        # "locally served" networks. Our 100.65.2.0/24 LAN is CGNAT space
        # (100.64.0.0/10), not in the RFC 6303 default set, so list it
        # explicitly. Setting this replaces the defaults, so include them.
        private_networks = [
          "100.64.0.0/10"
          "10.0.0.0/8"
          "172.16.0.0/12"
          "192.168.0.0/16"
          "169.254.0.0/16"
          "127.0.0.0/8"
          "fd00::/8"
          "fe80::/10"
          "::1/128"
        ];
      };

      dhcp = {
        enabled = true;
        interface_name = "br0";
        local_domain_name = lanDomain;
        dhcpv4 = {
          gateway_ip = lanAddress;
          subnet_mask = "255.255.255.0";
          range_start = "100.65.2.10";
          range_end = "100.65.2.200";
          lease_duration = 86400;
        };
      };

      # Keep the query log short; the default retention is 90 days.
      querylog.interval = "24h";
    };
  };
}

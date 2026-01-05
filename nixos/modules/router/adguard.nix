# AdGuard Home configuration for DNS and DHCP
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.router;
  adg = cfg.adguard;
in
  lib.mkIf adg.enable {
    services.adguardhome = {
      enable = true;
      openFirewall = false;
      allowDHCP = true;
      mutableSettings = false;

      settings = {
        schema_version = 29;

        http.address = "${cfg.lan.address}:${toString adg.webPort}";

        users = [
          {
            name = "admin";
            password = "$2a$10$WzFYwQ9gNjF8F8e8H8f8H.8f8f8f8f8f8f8f8f8f8f8f8f8f8f8f8";
          }
        ];

        dns = {
          bind_hosts = ["127.0.0.1" cfg.lan.address];
          port = 53;
          upstream_dns = adg.upstreamDns;
          bootstrap_dns = adg.bootstrapDns;
          enable_dnssec = true;
          fastest_addr = true;
          cache_size = 4194304;
          cache_ttl_min = 300;
          cache_ttl_max = 86400;
          ratelimit = 100;
          protection_enabled = true;
          blocking_mode = "default";
          blocked_response_ttl = 10;
          allowed_clients = [];
          use_private_ptr_resolvers = true;
          local_ptr_upstreams = [];
        };

        filtering = {
          filtering_enabled = true;
          safe_search.enabled = false;
          parental_enabled = false;
          safebrowsing_enabled = true;
        };

        filters = [
          {
            enabled = true;
            url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
            name = "AdGuard DNS filter";
            id = 1;
          }
          {
            enabled = true;
            url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt";
            name = "AdAway Default Blocklist";
            id = 2;
          }
        ];

        dhcp = {
          enabled = true;
          interface_name = cfg.lan.ifname;
          local_domain_name = cfg.lan.domain;
          dhcpv4 = {
            gateway_ip = cfg.lan.address;
            subnet_mask = "255.255.255.0";
            range_start = cfg.lan.dhcpRange.start;
            range_end = cfg.lan.dhcpRange.end;
            lease_duration = 86400;
          };
          dhcpv6 = {
            range_start = "";
            lease_duration = 86400;
          };
        };

        querylog = {
          enabled = true;
          file_enabled = true;
          interval = "24h";
          size_memory = 1000;
        };
        statistics = {
          enabled = true;
          interval = "24h";
        };
        os = {
          group = "";
          user = "";
          rlimit_nofile = 0;
        };
        log = {
          file = "";
          max_backups = 0;
          max_size = 100;
          max_age = 3;
          compress = false;
          local_time = false;
          verbose = false;
        };
      };
    };
  }

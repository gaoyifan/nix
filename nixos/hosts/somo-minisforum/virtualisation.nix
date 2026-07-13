# Incus daemon for KVM virtual machines.
# Guests attach by default to the br-somo bridge defined in networking.nix
# (no Incus-managed incusbr0 NAT bridge); dnsmasq provides DHCP/DNS there.
# Individual VMs may override eth0 to join br-gnet instead.
{
  pkgs,
  username,
  ...
}: let
  metricsPort = 8444;
in {
  virtualisation.incus = {
    enable = true;
    preseed = {
      config = {
        "core.metrics_address" = "127.0.0.1:${toString metricsPort}";
        "core.metrics_authentication" = "false";
      };
      storage_pools = [
        {
          name = "default";
          driver = "dir";
        }
      ];
      profiles = [
        {
          name = "default";
          devices = {
            eth0 = {
              type = "nic";
              name = "eth0";
              nictype = "bridged";
              parent = "br-somo";
            };
            root = {
              type = "disk";
              path = "/";
              pool = "default";
            };
          };
        }
      ];
    };
  };

  services.prometheus.scrapeConfigs = [
    {
      job_name = "incus";
      metrics_path = "/1.0/metrics";
      scheme = "https";
      static_configs = [
        {
          targets = ["127.0.0.1:${toString metricsPort}"];
        }
      ];
      tls_config.insecure_skip_verify = true;
    }
  ];

  services.grafana.provision.dashboards.settings.providers = [
    {
      name = "incus-vm-performance";
      options.path = pkgs.writeTextDir "incus-vm-performance.json" (
        builtins.readFile ./incus-vm-performance.json
      );
    }
  ];

  # Manage Incus without sudo.
  users.users.${username}.extraGroups = ["incus-admin"];
}

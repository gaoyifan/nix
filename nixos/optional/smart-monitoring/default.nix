{
  config,
  lib,
  pkgs,
  ...
}: let
  grafanaDashboard = import ../grafana-dashboard.nix;
in {
  imports = [../local-monitoring.nix];

  options.services.smartMonitoring.enable = lib.mkEnableOption "disk SMART monitoring and Grafana dashboard";

  config = lib.mkIf config.services.smartMonitoring.enable {
    services.localMonitoring.enable = true;
    services.prometheus = {
      exporters.smartctl = {
        enable = true;
        listenAddress = "127.0.0.1";
        extraFlags = ["--smartctl.scan-device-type=by-id"];
      };
      scrapeConfigs = [
        {
          job_name = "smartctl";
          scrape_interval = "60s";
          static_configs = [
            {targets = ["127.0.0.1:${toString config.services.prometheus.exporters.smartctl.port}"];}
          ];
        }
      ];
    };
    services.grafana.provision.dashboards.settings.providers = [
      {
        name = "disk-smart";
        options.path = pkgs.writeTextDir "disk-smart.json" (builtins.toJSON (grafanaDashboard.build {
          source = import ./dashboard.nix;
          variables = [
            (grafanaDashboard.queryVariable {
              name = "device";
              label = "Disks";
              query = ''label_values(smartctl_device{job="smartctl"}, device)'';
            })
          ];
        }));
      }
    ];
  };
}

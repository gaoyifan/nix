{
  config,
  pkgs,
  ...
}: let
  metricsFile = "/var/lib/codex-monitoring/codex.prom";
  grafanaDashboard = import ../../../optional/grafana-dashboard.nix;
in {
  # Reuse the existing textfile collector; the service owns only its own state directory.
  systemd.tmpfiles.rules = [
    "L /var/lib/prometheus-node-exporter-text-files/codex.prom - - - - ${metricsFile}"
  ];

  systemd.services.codex-usage-metrics = {
    description = "Record Codex weekly quota usage";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    path = [pkgs.codex];
    environment.CODEX_HOME = "${config.users.users.yifan.home}/.syncd-dotfiles/.codex";
    serviceConfig = {
      Type = "oneshot";
      User = "yifan";
      StateDirectory = "codex-monitoring";
      TimeoutStartSec = "60s";
      ExecStart = "${pkgs.python3}/bin/python3 ${./codex-usage-metrics.py} ${metricsFile}";
    };
  };

  systemd.timers.codex-usage-metrics = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:0/30";
      Persistent = true;
    };
  };

  services.grafana.provision.dashboards.settings.providers = [
    {
      name = "codex-usage";
      options.path = pkgs.writeTextDir "codex-usage.json" (builtins.toJSON (grafanaDashboard.build {
        variables = [];
        source = {
          name = "codex-usage";
          title = "Codex weekly usage";
          tags = ["codex"];
          timeFrom = "now-14d";
          panels =
            map (item: {
              inherit (item) id title;
              description = item.description or "";
              queries = [
                {
                  refId = "A";
                  query = {
                    inherit (item) expr;
                    legendFormat = item.legendFormat or item.title;
                    range = true;
                  };
                }
              ];
              visualization = {
                type = "timeseries";
                fillOpacity = 10;
                legendCalcs = ["lastNotNull"];
                fieldDefaults =
                  {min = 0;}
                  // item.fieldDefaults;
              };
            }) [
              {
                id = 1;
                title = "Weekly quota used";
                description = "Codex is sampled every 30 minutes; Prometheus scrapes the cached sample.";
                expr = ''codex_weekly_used_percent{job="node"}'';
                legendFormat = "Used";
                fieldDefaults = {
                  unit = "percent";
                  max = 100;
                };
              }
              {
                id = 3;
                title = "Until weekly reset";
                expr = ''clamp_min(codex_weekly_reset_timestamp_seconds{job="node"} - time(), 0)'';
                fieldDefaults = {
                  unit = "dtdurations";
                  noValue = "No data";
                };
              }
              {
                id = 4;
                title = "Age of last successful sample";
                expr = ''time() - codex_usage_last_success_timestamp_seconds{job="node"}'';
                fieldDefaults = {
                  unit = "dtdurations";
                  noValue = "No data";
                };
              }
            ];
          rows = [
            {
              title = "History";
              panels = [1 3 4];
              rowHeightMode = "standard";
              maxColumnCount = 1;
            }
          ];
        };
      }));
    }
  ];
}

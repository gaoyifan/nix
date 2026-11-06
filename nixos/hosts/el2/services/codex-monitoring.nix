{
  config,
  pkgs,
  ...
}: let
  metricsPort = 9842;
  grafanaDashboard = import ../../../optional/grafana-dashboard.nix;
in {
  systemd.sockets.codex-usage-metrics = {
    wantedBy = ["sockets.target"];
    listenStreams = ["127.0.0.1:${toString metricsPort}"];
    socketConfig.Accept = true;
  };

  systemd.services."codex-usage-metrics@" = {
    description = "Export Codex weekly quota usage";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    path = [pkgs.codex];
    environment.CODEX_HOME = "${config.users.users.yifan.home}/.syncd-dotfiles/.codex";
    unitConfig.CollectMode = "inactive-or-failed";
    serviceConfig = {
      User = "yifan";
      StandardInput = "socket";
      StandardOutput = "journal";
      RuntimeMaxSec = "60s";
      ExecStart = "${pkgs.python3}/bin/python3 ${./codex-usage-metrics.py}";
    };
  };

  services.prometheus.scrapeConfigs = [
    {
      job_name = "codex";
      scrape_interval = "30m";
      scrape_timeout = "60s";
      static_configs = [{targets = ["127.0.0.1:${toString metricsPort}"];}];
    }
  ];

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
                description = "Prometheus samples Codex directly every 30 minutes.";
                expr = ''last_over_time(codex_weekly_used_percent{job="codex"}[1h])'';
                legendFormat = "Used";
                fieldDefaults = {
                  unit = "percent";
                  max = 100;
                };
              }
              {
                id = 3;
                title = "Until weekly reset";
                expr = ''clamp_min(last_over_time(codex_weekly_reset_timestamp_seconds{job="codex"}[1h]) - time(), 0)'';
                fieldDefaults = {
                  unit = "dtdurations";
                  noValue = "No data";
                };
              }
              {
                id = 4;
                title = "Age of last successful sample";
                expr = ''time() - last_over_time(codex_usage_last_success_timestamp_seconds{job="codex"}[24h])'';
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

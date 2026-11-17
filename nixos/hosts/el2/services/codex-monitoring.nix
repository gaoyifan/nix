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
                overrides = item.overrides or [];
                fieldDefaults =
                  {min = 0;}
                  // item.fieldDefaults;
              };
            }) [
              {
                id = 2;
                title = "Weekly quota headroom";
                description = "Remaining quota fraction / remaining fraction of the 7-day window. The dashed 1× line marks balance; below 1× = tight; above 1× = ample. This compares the remaining daily budget with the standard daily budget, not recent usage speed. Grafana automatically scales the base-2 logarithmic axis to the data. Zero cannot be plotted on a logarithmic axis. Quota samples update every 30 minutes.";
                expr = ''
                  (1 - last_over_time(codex_weekly_used_percent{job="codex"}[1h]) / 100)
                  / ((last_over_time(codex_weekly_reset_timestamp_seconds{job="codex"}[1h]) - time()) / 604800 > 0)
                '';
                legendFormat = "Headroom";
                fieldDefaults = {
                  unit = "suffix:×";
                  decimals = 2;
                  min = null;
                  noValue = "No data";
                  thresholds = {
                    mode = "absolute";
                    steps = [
                      {
                        color = "transparent";
                        value = null;
                      }
                      {
                        color = "gray";
                        value = 1;
                      }
                    ];
                  };
                };
                overrides = [
                  {
                    matcher = {
                      id = "byName";
                      options = "Headroom";
                    };
                    properties = [
                      {
                        id = "custom.scaleDistribution";
                        value = {
                          type = "log";
                          log = 2;
                        };
                      }
                      {
                        id = "custom.spanNulls";
                        value = false;
                      }
                      {
                        id = "custom.thresholdsStyle";
                        value = {mode = "dashed";};
                      }
                    ];
                  }
                ];
              }
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
              panels = [2 1 3 4];
              rowHeightMode = "standard";
              maxColumnCount = 2;
            }
          ];
        };
      }));
    }
  ];
}

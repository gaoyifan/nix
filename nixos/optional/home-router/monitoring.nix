{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.networking.homeRouter;
  monitoringCfg = cfg.monitoring;
  allInterfaceNames = lib.unique (
    map (lan: lan.interface) (lib.attrValues cfg.lans)
    ++ map (wan: wan.interface) (lib.attrValues cfg.wans)
  );
  monitoringInterface =
    if monitoringCfg.wan == null
    then null
    else cfg.wans.${monitoringCfg.wan}.interface;
  grafanaInputInterfaces = ["lo"] ++ cfg.internalInterfaces ++ monitoringCfg.grafana.extraInterfaces;
  grafanaInputInterfaceSet = lib.concatMapStringsSep ", " (interface: ''"${interface}"'') grafanaInputInterfaces;
  overviewDashboard = pkgs.writeTextDir "home-router-overview.json" (
    builtins.replaceStrings
    ["__HOME_ROUTER_INTERFACES__"]
    [(lib.concatStringsSep "," allInterfaceNames)]
    (builtins.readFile ./overview.json)
  );
  publicEgressDashboard = pkgs.writeTextDir "home-router-public-egress.json" (
    builtins.replaceStrings
    ["__WAN_INTERFACE__"]
    [(toString monitoringInterface)]
    (builtins.readFile ./public-egress.json)
  );
in {
  config = lib.mkIf (cfg.enable && monitoringCfg.enable) {
    services.prometheus = {
      enable = true;
      listenAddress = "127.0.0.1";
      retentionTime = lib.mkDefault "90d";
      globalConfig.scrape_interval = "15s";
      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [{targets = ["127.0.0.1:${toString config.services.prometheus.exporters.node.port}"];}];
        }
        {
          job_name = "ping";
          static_configs = [{targets = ["127.0.0.1:${toString config.services.prometheus.exporters.ping.port}"];}];
        }
      ];
    };

    services.prometheus.exporters = {
      node = {
        enable = true;
        listenAddress = "127.0.0.1";
      };
      ping = {
        enable = true;
        listenAddress = "127.0.0.1";
        settings = {
          targets = lib.mkDefault [
            "223.5.5.5"
            "119.29.29.29"
            "180.76.76.76"
            "1.1.1.1"
            "8.8.8.8"
            "2400:3200::1"
            "2606:4700:4700::1111"
            "2001:4860:4860::8888"
          ];
          ping.fw-mark = lib.mkDefault 65536;
        };
      };
    };

    services.grafana = {
      enable = true;
      settings = {
        server.http_addr = "";
        server.http_port = monitoringCfg.grafana.port;
        auth.disable_login_form = true;
        "auth.anonymous".enabled = true;
        "auth.basic".enabled = false;
        security.secret_key = "SW2YcwTIb9zpOOhoPsMm";
      };
      provision = {
        enable = true;
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            uid = "home-router-prometheus";
            type = "prometheus";
            url = "http://127.0.0.1:${toString config.services.prometheus.port}";
          }
        ];
        dashboards.settings.providers = [
          {
            name = "home-router-overview";
            options.path = overviewDashboard;
          }
          {
            name = "home-router-public-egress";
            options.path = publicEgressDashboard;
          }
        ];
      };
    };

    networking.nftables.tables.home-router-monitoring = {
      family = "inet";
      content = ''
        chain input {
          type filter hook input priority filter; policy accept;
          iifname { ${grafanaInputInterfaceSet} } tcp dport ${toString config.services.grafana.settings.server.http_port} accept
          tcp dport ${toString config.services.grafana.settings.server.http_port} drop
        }
      '';
    };
  };
}

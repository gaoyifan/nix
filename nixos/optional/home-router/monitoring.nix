{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.networking.homeRouter;
  monitoringCfg = cfg.monitoring;
  pingPort = 9427;
  ipv4Targets = [
    "223.5.5.5"
    "119.29.29.29"
    "180.76.76.76"
    "1.1.1.1"
    "8.8.8.8"
  ];
  ipv6Targets = [
    "2400:3200::1"
    "2606:4700:4700::1111"
    "2001:4860:4860::8888"
  ];
  allInterfaceNames = lib.unique (
    map (lan: lan.interface) (lib.attrValues cfg.lans)
    ++ map (wan: wan.interface) (lib.attrValues cfg.wans)
  );
  grafanaInputInterfaces =
    [
      "lo"
      "tailscale0"
    ]
    ++ cfg.internalInterfaces;
  grafanaInputInterfaceSet = lib.concatMapStringsSep ", " (interface: ''"${interface}"'') grafanaInputInterfaces;
  monitoredWans =
    lib.imap0 (index: name: {
      inherit name;
      inherit (cfg.wans.${name}) interface routingTable;
      port = pingPort + index;
      targets = let
        wan = cfg.wans.${name};
        staticAddressFamilies =
          lib.optionals (wan.gateway4 != null) ipv4Targets
          ++ lib.optionals (wan.gateway6 != null) ipv6Targets;
      in
        if staticAddressFamilies == []
        then ipv4Targets ++ ipv6Targets
        else staticAddressFamilies;
    })
    monitoringCfg.wans;
  overviewDashboard = pkgs.writeTextDir "home-router-overview.json" (
    builtins.replaceStrings
    ["__HOME_ROUTER_INTERFACES__"]
    [(lib.concatStringsSep "," allInterfaceNames)]
    (builtins.readFile ./overview.json)
  );
  publicEgressDashboard = pkgs.writeTextDir "home-router-public-egress.json" (
    builtins.replaceStrings
    ["__MONITORED_WANS__"]
    [(lib.concatMapStringsSep "," (wan: wan.name) monitoredWans)]
    (builtins.readFile ./public-egress.json)
  );
in {
  config = lib.mkIf (cfg.enable && monitoringCfg.enable) {
    services.prometheus = {
      enable = true;
      listenAddress = "127.0.0.1";
      retentionTime = lib.mkDefault "90d";
      globalConfig.scrape_interval = "15s";
      scrapeConfigs =
        [
          {
            job_name = "node";
            static_configs = [{targets = ["127.0.0.1:${toString config.services.prometheus.exporters.node.port}"];}];
          }
          {
            job_name = "ping";
            static_configs =
              map (wan: {
                targets = ["127.0.0.1:${toString wan.port}"];
                labels.wan = wan.name;
              })
              monitoredWans;
          }
        ]
        ++ map (wan: {
          job_name = "node-wan-${wan.name}";
          static_configs = [
            {
              targets = ["127.0.0.1:${toString config.services.prometheus.exporters.node.port}"];
              labels.wan = wan.name;
            }
          ];
          metric_relabel_configs = [
            {
              source_labels = ["device"];
              regex = lib.escapeRegex wan.interface;
              action = "keep";
            }
          ];
        })
        monitoredWans;
    };

    services.prometheus.exporters.node = {
      enable = true;
      listenAddress = "127.0.0.1";
    };

    systemd.services = lib.listToAttrs (map (wan: let
      pingConfigFile = (pkgs.formats.yaml {}).generate "home-router-ping-${wan.name}.yaml" {
        inherit (wan) targets;
        ping = lib.optionalAttrs (wan.routingTable != null) {
          fw-mark = wan.routingTable;
        };
      };
    in
      lib.nameValuePair "prometheus-ping-${wan.name}-exporter" {
        description = "Prometheus ping exporter for ${wan.name}";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target"];
        wants = ["network-online.target"];
        serviceConfig = {
          ExecStart = ''
            ${pkgs.prometheus-ping-exporter}/bin/ping_exporter \
              --web.listen-address=127.0.0.1:${toString wan.port} \
              --config.path=${pingConfigFile}
          '';
          Restart = "always";
          DynamicUser = true;
          CapabilityBoundingSet = ["CAP_NET_RAW"];
          AmbientCapabilities = ["CAP_NET_RAW"];
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
          ];
        };
      })
    monitoredWans);

    services.grafana = {
      enable = true;
      settings = {
        server.http_addr = "";
        server.http_port = 3001;
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

    networking.nftables.tables.home-router.content = ''
      chain monitoring-input {
        type filter hook input priority filter; policy accept;
        iifname { ${grafanaInputInterfaceSet} } tcp dport ${toString config.services.grafana.settings.server.http_port} accept
        tcp dport ${toString config.services.grafana.settings.server.http_port} drop
      }
    '';
  };
}

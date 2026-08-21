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
  addressWithoutPrefix = address: lib.head (lib.splitString "/" address);
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
      counterId = toString index;
      inherit name;
      inherit (cfg.wans.${name}) addresses interface routingTable;
      port = pingPort + index;
      sharedInterface =
        builtins.length (lib.filter (wan: wan.interface == cfg.wans.${name}.interface) (lib.attrValues cfg.wans))
        > 1;
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
  wanCounterName = wan: direction: "home_router_wan_${wan.counterId}_${direction}";
  wanCounterDefinitions =
    lib.concatMapStringsSep "\n" (wan: ''
      counter ${wanCounterName wan "receive"} {}
      counter ${wanCounterName wan "transmit"} {}
    '')
    monitoredWans;
  wanAccountingRules = direction:
    lib.concatMapStringsSep "\n" (wan: let
      interfaceSelector =
        if direction == "receive"
        then "iifname"
        else "oifname";
      addressSelector =
        if direction == "receive"
        then "daddr"
        else "saddr";
      counter = wanCounterName wan direction;
      addressRule = address: let
        family =
          if lib.hasInfix ":" address
          then "ip6"
          else "ip";
      in ''${interfaceSelector} "${wan.interface}" ${family} ${addressSelector} ${addressWithoutPrefix address} counter name ${counter}'';
    in
      if wan.sharedInterface
      then lib.concatMapStringsSep "\n" addressRule wan.addresses
      else ''${interfaceSelector} "${wan.interface}" counter name ${counter}'')
    monitoredWans;
  wanMetricsFile = "/run/prometheus-node-exporter/home-router-wan.prom";
  collectWanMetrics = pkgs.writeShellScript "collect-home-router-wan-metrics" ''
    set -euo pipefail

    counters_file="$(${pkgs.coreutils}/bin/mktemp /run/prometheus-node-exporter/.home-router-wan-counters.XXXXXX)"
    metrics_file="$(${pkgs.coreutils}/bin/mktemp /run/prometheus-node-exporter/.home-router-wan-metrics.XXXXXX)"
    trap '${pkgs.coreutils}/bin/rm -f "$counters_file" "$metrics_file"' EXIT

    ${lib.getExe pkgs.nftables} --json list counters inet home-router > "$counters_file"

    counter_bytes() {
      ${lib.getExe pkgs.jq} --exit-status --raw-output \
        --arg name "$1" \
        '.nftables[] | select(.counter.name == $name) | .counter.bytes' \
        "$counters_file"
    }

    {
      printf '# HELP home_router_wan_receive_bytes_total Bytes received through a WAN.\n'
      printf '# TYPE home_router_wan_receive_bytes_total counter\n'
      printf '# HELP home_router_wan_transmit_bytes_total Bytes transmitted through a WAN.\n'
      printf '# TYPE home_router_wan_transmit_bytes_total counter\n'
      ${lib.concatMapStringsSep "\n" (wan: ''
        printf 'home_router_wan_receive_bytes_total{wan=%s} %s\n' \
          ${lib.escapeShellArg (builtins.toJSON wan.name)} \
          "$(counter_bytes ${lib.escapeShellArg (wanCounterName wan "receive")})"
        printf 'home_router_wan_transmit_bytes_total{wan=%s} %s\n' \
          ${lib.escapeShellArg (builtins.toJSON wan.name)} \
          "$(counter_bytes ${lib.escapeShellArg (wanCounterName wan "transmit")})"
      '')
      monitoredWans}
    } > "$metrics_file"

    ${pkgs.coreutils}/bin/chmod 0644 "$metrics_file"
    ${pkgs.coreutils}/bin/mv "$metrics_file" ${lib.escapeShellArg wanMetricsFile}
  '';
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
    assertions = [
      {
        assertion = lib.all (wan: !wan.sharedInterface || wan.addresses != []) monitoredWans;
        message = "Monitored WANs sharing an interface must declare addresses for per-WAN throughput accounting.";
      }
    ];

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
            {
              source_labels = ["__name__"];
              regex = "node_network_(up|carrier|receive_errs_total|transmit_errs_total|receive_drop_total|transmit_drop_total)";
              action = "keep";
            }
          ];
        })
        monitoredWans;
    };

    services.prometheus.exporters.node = {
      enable = true;
      listenAddress = "127.0.0.1";
      extraFlags = ["--collector.textfile.directory=/run/prometheus-node-exporter"];
    };

    systemd.services =
      lib.listToAttrs (map (wan: let
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
      monitoredWans)
      // {
        home-router-wan-metrics = {
          description = "Export Home Router WAN counters for Prometheus";
          after = [
            "nftables.service"
            "prometheus-node-exporter.service"
          ];
          requires = [
            "nftables.service"
            "prometheus-node-exporter.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = collectWanMetrics;
          };
        };
      };

    systemd.timers.home-router-wan-metrics = {
      description = "Periodically export Home Router WAN counters";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "5s";
        OnUnitActiveSec = "15s";
        AccuracySec = "1s";
      };
    };

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
      ${wanCounterDefinitions}

      chain wan-accounting-prerouting {
        type filter hook prerouting priority dstnat - 1; policy accept;
        ${wanAccountingRules "receive"}
      }

      chain wan-accounting-postrouting {
        type filter hook postrouting priority srcnat + 1; policy accept;
        ${wanAccountingRules "transmit"}
      }

      chain monitoring-input {
        type filter hook input priority filter; policy accept;
        iifname { ${grafanaInputInterfaceSet} } tcp dport ${toString config.services.grafana.settings.server.http_port} accept
        tcp dport ${toString config.services.grafana.settings.server.http_port} drop
      }
    '';
  };
}

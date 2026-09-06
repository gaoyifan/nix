{
  config,
  lib,
  pkgs,
  ...
}: let
  grafanaDashboard = import ../grafana-dashboard.nix;
in {
  imports = [../local-monitoring.nix];

  options.services.zfsMonitoring.enable = lib.mkEnableOption "ZFS monitoring and Grafana dashboard";

  config = lib.mkIf config.services.zfsMonitoring.enable {
    services.localMonitoring.enable = true;
    services.prometheus = {
      exporters = {
        zfs = {
          enable = true;
          listenAddress = "127.0.0.1";
          extraFlags = [
            "--properties.pool=allocated,free,freeing,health,size,fragmentation"
            "--properties.dataset-filesystem=available,used,usedbysnapshots,quota,refquota,referenced,compressratio"
            "--properties.dataset-volume=available,used,usedbysnapshots,referenced,volsize,compressratio"
          ];
        };
        zfs-siebenmann = {
          enable = true;
          listenAddress = "127.0.0.1";
          depth = 2;
        };
        node = {
          enable = true;
          listenAddress = "127.0.0.1";
          enabledCollectors = ["zfs"];
        };
      };
      scrapeConfigs = [
        {
          job_name = "zfs";
          scrape_interval = "60s";
          static_configs = [{targets = ["127.0.0.1:${toString config.services.prometheus.exporters.zfs.port}"];}];
        }
        {
          job_name = "zfs-vdev";
          static_configs = [{targets = ["127.0.0.1:${toString config.services.prometheus.exporters.zfs-siebenmann.port}"];}];
          metric_relabel_configs = [
            {
              source_labels = ["__name__"];
              regex = "zfs_(pool_(errors|scan_.*)|vdev_(state|errors|ops|bytes|space_(allocated|capacity)_bytes|zio_latency_total_(bucket|sum|count)|queue_(active|pending)_length))";
              action = "keep";
            }
            {
              source_labels = ["zpool"];
              target_label = "pool";
            }
            {
              regex = "zpool";
              action = "labeldrop";
            }
          ];
        }
        {
          job_name = "zfs-arc";
          params."collect[]" = ["zfs"];
          static_configs = [{targets = ["127.0.0.1:${toString config.services.prometheus.exporters.node.port}"];}];
          metric_relabel_configs = [
            {
              source_labels = ["__name__"];
              regex = "node_zfs_arc_(size|c|demand_(data|metadata)_(hits|misses))|node_scrape_collector_success";
              action = "keep";
            }
          ];
        }
      ];
    };

    services.grafana.provision.dashboards.settings.providers = [
      {
        name = "zfs-overview";
        options.path = pkgs.writeTextDir "zfs-overview.json" (builtins.toJSON (grafanaDashboard.build {
          source = import ./dashboard.nix;
          variables = [
            (grafanaDashboard.queryVariable {
              name = "pool";
              label = "Pools";
              query = ''label_values(zfs_pool_health{job="zfs"}, pool)'';
            })
            (grafanaDashboard.queryVariable {
              name = "dataset";
              label = "Datasets";
              query = ''label_values(zfs_dataset_used_bytes{job="zfs",pool=~"$pool"}, name)'';
            })
          ];
        }));
      }
    ];
  };
}

{
  config,
  pkgs,
  ...
}: let
  ipmiExporterConfig = (pkgs.formats.yaml {}).generate "ipmi-exporter.yaml" {
    modules.default.collectors = ["ipmi"];
  };
in {
  services.prometheus = {
    exporters = {
      ipmi = {
        enable = true;
        listenAddress = "127.0.0.1";
        configFile = ipmiExporterConfig;
      };
      smartctl = {
        enable = true;
        listenAddress = "127.0.0.1";
        extraFlags = ["--smartctl.scan-device-type=by-id"];
      };
    };
    scrapeConfigs = [
      {
        job_name = "ipmi";
        metric_relabel_configs = [
          {
            source_labels = ["__name__"];
            regex = "ipmi_sensor_value";
            action = "drop";
          }
          {
            source_labels = ["__name__"];
            regex = "ipmi_.*";
            action = "keep";
          }
        ];
        scrape_interval = "60s";
        scrape_timeout = "30s";
        static_configs = [
          {targets = ["127.0.0.1:${toString config.services.prometheus.exporters.ipmi.port}"];}
        ];
      }
      {
        job_name = "smartctl";
        scrape_interval = "60s";
        static_configs = [
          {targets = ["127.0.0.1:${toString config.services.prometheus.exporters.smartctl.port}"];}
        ];
      }
    ];
  };
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="ipmi", KERNEL=="ipmi0", GROUP="ipmi-exporter-access", MODE="0660"
  '';
  systemd.services.prometheus-ipmi-exporter.serviceConfig = {
    DeviceAllow = ["/dev/ipmi0 rw"];
    PrivateDevices = false;
    SupplementaryGroups = ["ipmi-exporter-access"];
  };

  users.groups.ipmi-exporter-access = {};
}

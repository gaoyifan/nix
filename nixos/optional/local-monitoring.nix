{
  config,
  lib,
  pkgs,
  ...
}: {
  options.services.localMonitoring.enable = lib.mkEnableOption "local Prometheus and Grafana";

  config = lib.mkIf config.services.localMonitoring.enable {
    services.prometheus = {
      enable = true;
      listenAddress = "127.0.0.1";
      retentionTime = lib.mkDefault "90d";
      globalConfig.scrape_interval = "15s";
    };

    services.grafana = {
      enable = true;
      settings = {
        server.http_addr = lib.mkDefault "127.0.0.1";
        server.http_port = lib.mkDefault 3001;
        auth.disable_login_form = true;
        "auth.anonymous".enabled = true;
        "auth.basic".enabled = false;
        security.secret_key = lib.mkDefault "$__file{${config.services.grafana.dataDir}/secret_key}";
      };
      provision = {
        enable = true;
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            # Keep the UID used by existing provisioned and saved dashboards.
            uid = "home-router-prometheus";
            type = "prometheus";
            url = "http://127.0.0.1:${toString config.services.prometheus.port}";
          }
        ];
      };
    };

    systemd.services.grafana.preStart = lib.mkBefore ''
      if [ ! -s ${config.services.grafana.dataDir}/secret_key ]; then
        (umask 077; ${lib.getExe pkgs.openssl} rand -hex 32 > ${config.services.grafana.dataDir}/secret_key)
      fi
    '';
  };
}

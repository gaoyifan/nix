{
  config,
  lib,
  ...
}: let
  cfg = config.services.codex-api;
  weeklyLimitOverrides = import (config.services.secrets.filesDir + "/nixos/somo-minisforum/codex-api-weekly-limits.nix");
  certDir = "${config.services.acmeCertificates.directory}/yfgao";
  port = "3002";
in {
  imports = [../../optional/codex-api.nix];

  config = lib.mkIf cfg.enable {
    age.secrets.somo-minisforum-codex-api-auth = {
      file = config.services.secrets.filesDir + "/nixos/somo-minisforum/codex-api-auth.age";
      owner = cfg.user;
      group = cfg.group;
    };

    services.acmeCertificates.restartServices = ["tailscale-serve"];
    services.tailscale.serve = {
      enable = true;
      services.codex-api = {
        certificate = {
          certFile = "${certDir}/fullchain.pem";
          keyFile = "${certDir}/privkey.pem";
        };
        tlsEndpoints."tcp:443" = "http://127.0.0.1:${port}";
      };
    };

    services.codex-api = {
      weeklyLimitOverrides = weeklyLimitOverrides;
      settings = {
        server.listen = "0.0.0.0:${port}";
        upstream.auth_file = config.age.secrets.somo-minisforum-codex-api-auth.path;
        model_prices = {
          "gpt-6-astra".max_reasoning_effort = "medium";
          "gpt-5.6-sol".max_reasoning_effort = "high";
        };
      };
    };
  };
}

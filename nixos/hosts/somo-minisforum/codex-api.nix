{
  config,
  lib,
  username,
  ...
}: let
  hermesUsers = builtins.attrNames config.services.hermes-nspawn.containers;
  apiKeyIds = ["honcho" "immersive-translation" "library"] ++ map (user: "hermes-${user}") hermesUsers;
  weeklyLimitOverrides = import (config.services.secrets.filesDir + "/nixos/somo-minisforum/codex-api-weekly-limits.nix");
  certDir = "${config.services.acmeCertificates.directory}/yfgao";
in {
  imports = [../../optional/codex-api.nix];

  config = lib.mkIf config.services.secrets.hasRealFiles {
    age.secrets =
      {
        somo-minisforum-codex-api-auth = {
          file = config.services.secrets.filesDir + "/nixos/somo-minisforum/codex-api-auth.age";
          owner = "codex-api";
          group = "codex-api";
        };
      }
      // builtins.listToAttrs (
        map (id: {
          name = "new-api-tokens/${id}";
          value = {
            group = "codex-api";
            mode = "0440";
          };
        })
        apiKeyIds
      );

    services.acmeCertificates.restartServices = ["tailscale-serve"];
    services.tailscale.serve = {
      enable = true;
      services.codex-api = {
        certificate = {
          certFile = "${certDir}/fullchain.pem";
          keyFile = "${certDir}/privkey.pem";
        };
        tlsEndpoints."tcp:443" = "http://127.0.0.1:3002";
      };
    };

    services.codex-api.settings = {
      server.listen = "0.0.0.0:3002";
      state.path = "/var/lib/codex-api/state.sqlite3";
      state.file_mode = "0640";
      upstream.auth_file = config.age.secrets.somo-minisforum-codex-api-auth.path;
      model_prices = {
        "gpt-6-astra".max_reasoning_effort = "medium";
        "gpt-5.6-sol".max_reasoning_effort = "high";
      };
      api_keys =
        map (id: {
          inherit id;
          secret_file = config.age.secrets."new-api-tokens/${id}".path;
          weekly_limit_usd = weeklyLimitOverrides.${id} or "500.00";
        })
        apiKeyIds;
    };

    users.users.${username}.extraGroups = ["codex-api"];

    systemd.services.codex-api.serviceConfig = {
      StateDirectory = "codex-api";
      StateDirectoryMode = "0750";
      UMask = lib.mkForce "0027";
    };
  };
}

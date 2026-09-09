{
  config,
  inputs,
  lib,
  username,
  ...
}: let
  hermesUsers = builtins.attrNames config.services.hermes-nspawn.containers;
  apiKeyIds = ["honcho" "immersive-translation"] ++ map (user: "hermes-${user}") hermesUsers;
  weeklyLimitOverrides = import (config.services.secrets.filesDir + "/nixos/somo-minisforum/codex-api-weekly-limits.nix");
in {
  imports = [inputs.codex-api.nixosModules.default];

  config = lib.mkMerge [
    {
      # Keep the package in the CI-built host closure when secrets are unavailable.
      system.extraDependencies = [config.services.codex-api.package];
    }
    (lib.mkIf config.services.secrets.hasRealFiles {
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

      services.codex-api = {
        enable = true;
        settings = {
          server.listen = "0.0.0.0:3002";
          state.path = "/var/lib/codex-api/state.sqlite3";
          state.file_mode = "0640";
          upstream.auth_file = config.age.secrets.somo-minisforum-codex-api-auth.path;
          upstream.supports_websockets = true;
          server.enable_websockets = true;
          model_prices = {
            "gpt-6-astra" = {
              input_usd_per_million = "10.00";
              cached_input_usd_per_million = "1.00";
              output_usd_per_million = "50.00";
              max_reasoning_effort = "medium";
            };
            "gpt-5.6-sol" = {
              input_usd_per_million = "4.00";
              cached_input_usd_per_million = "0.40";
              output_usd_per_million = "20.00";
              max_reasoning_effort = "high";
            };
            "gpt-5.6-terra" = {
              input_usd_per_million = "2.00";
              cached_input_usd_per_million = "0.20";
              output_usd_per_million = "12.00";
            };
            "gpt-5.6-luna" = {
              input_usd_per_million = "0.20";
              cached_input_usd_per_million = "0.02";
              output_usd_per_million = "1.20";
            };
          };
          api_keys =
            map (id: {
              inherit id;
              secret_file = config.age.secrets."new-api-tokens/${id}".path;
              weekly_limit_usd = weeklyLimitOverrides.${id} or "500.00";
            })
            apiKeyIds;
        };
      };

      users.users.${username}.extraGroups = ["codex-api"];

      systemd.services.codex-api.serviceConfig = {
        StateDirectory = "codex-api";
        StateDirectoryMode = "0750";
        UMask = lib.mkForce "0027";
      };
    })
  ];
}

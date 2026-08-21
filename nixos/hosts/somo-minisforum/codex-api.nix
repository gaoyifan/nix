{
  config,
  inputs,
  lib,
  ...
}: let
  hermesUsers = builtins.attrNames config.services.hermes-nspawn.containers;
  apiKeyIds = ["honcho" "immersive-translation"] ++ map (user: "hermes-${user}") hermesUsers;
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
          server.listen = "198.18.255.254:3002";
          state.path = "/var/lib/codex-api/state.sqlite3";
          upstream.auth_file = config.age.secrets.somo-minisforum-codex-api-auth.path;
          api_keys =
            map (id: {
              inherit id;
              secret_file = config.age.secrets."new-api-tokens/${id}".path;
              weekly_limit_usd = "500.00";
            })
            apiKeyIds;
        };
      };

      systemd.services.codex-api.serviceConfig.StateDirectory = "codex-api";
    })
  ];
}

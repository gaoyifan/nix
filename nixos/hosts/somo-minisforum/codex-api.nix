{
  config,
  inputs,
  lib,
  ...
}: let
  hermesUsers = builtins.attrNames config.services.hermes-nspawn.containers;
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
          map (user: {
            name = "new-api-tokens/hermes-${user}";
            value = {
              group = "codex-api";
              mode = "0440";
            };
          })
          hermesUsers
        );

      services.codex-api = {
        enable = true;
        settings = {
          server.listen = "198.18.255.254:3002";
          state.path = "/var/lib/codex-api/state.sqlite3";
          upstream.auth_file = config.age.secrets.somo-minisforum-codex-api-auth.path;
          api_keys =
            map (user: {
              id = "hermes-${user}";
              secret_file = config.age.secrets."new-api-tokens/hermes-${user}".path;
              weekly_limit_usd = "500.00";
            })
            hermesUsers;
        };
      };

      systemd.services.codex-api.serviceConfig.StateDirectory = "codex-api";
    })
  ];
}

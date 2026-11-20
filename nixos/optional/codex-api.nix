{
  config,
  inputs,
  lib,
  username,
  ...
}: let
  cfg = config.services.codex-api;
  defaultStateDirectory = "/var/lib/codex-api";
in {
  imports = [inputs.codex-api.nixosModules.default];

  options.services.codex-api.ageApiKeys = lib.mkOption {
    default = [];
    description = "API keys loaded from named agenix secrets.";
    type = lib.types.listOf (lib.types.submodule {
      options = {
        id = lib.mkOption {
          type = lib.types.str;
          description = "ID used in request logs and usage accounting.";
        };
        secretName = lib.mkOption {
          type = lib.types.str;
          description = "Name of the agenix secret that holds the API key.";
        };
        weeklyLimitUsd = lib.mkOption {
          type = lib.types.str;
          default = "500.00";
          description = "Weekly spend threshold in USD before switching to the fallback model.";
        };
      };
    });
  };

  config = lib.mkMerge [
    {services.codex-api.enable = lib.mkDefault config.services.secrets.hasRealFiles;}

    # The upstream module puts the package in the closure when enabled.
    (lib.mkIf (!cfg.enable) {system.extraDependencies = [cfg.package];})

    (lib.mkIf cfg.enable {
      services.codex-api.settings = {
        fallback_model = "gpt-6.1-terra";
        upstream.supports_websockets = true;
        server.enable_websockets = true;
        state = {
          path = lib.mkDefault "${defaultStateDirectory}/state.sqlite3";
          file_mode = "0640";
        };
        api_keys =
          map (key: {
            inherit (key) id;
            secret_file = config.age.secrets.${key.secretName}.path;
            weekly_limit_usd = key.weeklyLimitUsd;
          })
          cfg.ageApiKeys;
      };

      age.secrets = lib.genAttrs (map (key: key.secretName) cfg.ageApiKeys) (_: {
        group = cfg.group;
        mode = "0440";
      });

      users.users.${username}.extraGroups = [cfg.group];
      systemd.services.codex-api.serviceConfig =
        {UMask = lib.mkForce "0027";}
        // lib.optionalAttrs (builtins.dirOf cfg.settings.state.path == defaultStateDirectory) {
          StateDirectory = "codex-api";
          StateDirectoryMode = "0750";
        };
    })
  ];
}

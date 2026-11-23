{
  config,
  inputs,
  lib,
  username,
  ...
}: let
  cfg = config.services.codex-api;
  defaultStateDirectory = "/var/lib/codex-api";
  tokenDirectory = config.services.secrets.filesDir + "/nixos/somo-minisforum/new-api-tokens";
  tokenFiles =
    if config.services.secrets.hasRealFiles
    then
      lib.mapAttrs' (name: _: lib.nameValuePair (lib.removeSuffix ".age" name) (tokenDirectory + "/${name}"))
      (lib.filterAttrs (name: _: lib.hasSuffix ".age" name) (builtins.readDir tokenDirectory))
    else {};
in {
  imports = [inputs.codex-api.nixosModules.default];

  options.services.codex-api.sharedTokenFiles = lib.mkOption {
    type = lib.types.attrsOf lib.types.path;
    readOnly = true;
    internal = true;
    default = tokenFiles;
    description = "Shared Codex API token files used by every relay instance.";
  };

  options.services.codex-api.weeklyLimitOverrides = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = {};
    description = "Per-user weekly spend limits in USD.";
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
        api_keys = map (id: {
          inherit id;
          secret_file = config.age.secrets."new-api-tokens/${id}".path;
          weekly_limit_usd = lib.attrByPath [id] "500.00" cfg.weeklyLimitOverrides;
        }) (lib.attrNames cfg.sharedTokenFiles);
      };

      age.secrets = lib.mapAttrs' (id: file:
        lib.nameValuePair "new-api-tokens/${id}" {
          inherit file;
          group = cfg.group;
          mode = "0440";
        })
      cfg.sharedTokenFiles;

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

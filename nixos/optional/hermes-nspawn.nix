{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hermes-nspawn;
  hostPkgs = pkgs;
  newApiBaseUrl = "http://somo-minisforum.ts.gaof.net:3000/v1";
  secretDirectory = containerName: "/run/${containerName}-secrets";
  telegramBotApi = cfg.telegramBotApi;
in {
  imports = [./hermes-nspawn/telegram-bot-api.nix];

  options.services.hermes-nspawn = {
    enable = lib.mkEnableOption "Hermes nspawn containers";
    containers = lib.mkOption {
      type = lib.types.attrs;
      description = "Hermes nspawn container definitions.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services = lib.mkMerge (
      lib.mapAttrsToList (containerName: container: let
        dependencies =
          ["${containerName}-secrets.service"]
          ++ lib.optionals telegramBotApi.enable [
            "nginx.service"
            "telegram-bot-api.service"
          ];
      in {
        "${containerName}-secrets" = {
          description = "Prepare secrets for ${containerName}";
          before = ["container@${containerName}.service"];
          path = [
            pkgs.coreutils
            pkgs.openssl
          ];
          serviceConfig = {
            Type = "oneshot";
            UMask = "0077";
          };
          script = ''
            set -euo pipefail

            newapi_token="$(tr -d '\r\n' < ${container.newApiTokenFile})"
            exa_api_key="$(tr -d '\r\n' < /var/lib/hermes/exa_api_key)"
            lark_app_id="$(tr -d '\r\n' < /var/lib/hermes/lark_app_id)"
            lark_app_secret="$(tr -d '\r\n' < /var/lib/hermes/lark_app_secret)"

            if [[ -z "$newapi_token" ]]; then
              echo "${containerName}: New API token is empty" >&2
              exit 1
            fi
            if [[ -z "$exa_api_key" || -z "$lark_app_id" || -z "$lark_app_secret" ]]; then
              echo "${containerName}: Exa or Lark credentials are empty" >&2
              exit 1
            fi

            install -d -o root -g root -m 0700 /var/lib/hermes/dashboard
            if [[ ! -s /var/lib/hermes/dashboard/${containerName}.pass ]]; then
              openssl rand -base64 24 > /var/lib/hermes/dashboard/${containerName}.pass
              chmod 0600 /var/lib/hermes/dashboard/${containerName}.pass
            fi
            if [[ ! -s /var/lib/hermes/dashboard/${containerName}.secret ]]; then
              openssl rand -hex 32 > /var/lib/hermes/dashboard/${containerName}.secret
              chmod 0600 /var/lib/hermes/dashboard/${containerName}.secret
            fi

            dashboard_password="$(tr -d '\r\n' < /var/lib/hermes/dashboard/${containerName}.pass)"
            dashboard_secret="$(tr -d '\r\n' < /var/lib/hermes/dashboard/${containerName}.secret)"

            secrets_dir=${secretDirectory containerName}
            env_tmp="$secrets_dir/.env.tmp"
            install -d -o root -g 1000 -m 0750 "$secrets_dir"
            trap 'rm -f "$env_tmp"' EXIT

            install -o root -g 1000 -m 0640 /dev/null "$env_tmp"
            printf '%s\n' \
              'NEWAPI_BASE_URL=${newApiBaseUrl}' \
              "NEWAPI_API_KEY=$newapi_token" \
              "EXA_API_KEY=$exa_api_key" \
              'HERMES_DASHBOARD_BASIC_AUTH_USERNAME=agent' \
              "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=$dashboard_password" \
              "HERMES_DASHBOARD_BASIC_AUTH_SECRET=$dashboard_secret" \
              "LARK_APP_ID=$lark_app_id" \
              "LARK_APP_SECRET=$lark_app_secret" \
              > "$env_tmp"
            mv -f "$env_tmp" "$secrets_dir/.env"
          '';
        };
        "container@${containerName}" = {
          requires = dependencies;
          after = dependencies;
          restartTriggers = [container.newApiTokenFile];
        };
      })
      cfg.containers
    );

    containers =
      lib.mapAttrs (containerName: container: {
        autoStart = true;
        privateNetwork = true;
        hostBridge = container.bridge;
        localMacAddress = container.macAddress;
        timeoutStartSec = "15min";
        allowedDevices = [
          {
            node = "/dev/kvm";
            modifier = "rwm";
          }
        ];
        bindMounts = {
          "/dev/kvm" = {
            hostPath = "/dev/kvm";
            isReadOnly = false;
          };
          "/etc/hermes" = {
            hostPath = secretDirectory containerName;
            isReadOnly = true;
          };
        };
        specialArgs = {
          inherit containerName hostPkgs inputs newApiBaseUrl telegramBotApi;
        };
        config = ./hermes-nspawn/guest.nix;
      })
      cfg.containers;
  };
}

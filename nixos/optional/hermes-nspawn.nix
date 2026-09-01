{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hermes-nspawn;
  homeRouter = config.networking.homeRouter;
  coreBridge = homeRouter.switch.name;
  containerLanName = container:
    if container ? lan
    then container.lan
    else cfg.defaultLan;
  containerLan = container: homeRouter.lans.${containerLanName container};
  hostPkgs = pkgs;
  listenAddress = homeRouter.serviceAddresses.ipv4;
  codexApiBaseUrl = "http://${listenAddress}:3002/v1";
  newApiBaseUrl = "http://${listenAddress}:3000/v1";
  containerNameFor = userName: "hermes-nix-${userName}";
  newApiTokenFile = userName: "${cfg.newApiTokenDirectory}/hermes-${userName}";
  secretDirectory = containerName: "/run/${containerName}-secrets";
  honcho = cfg.honcho;
  honchoBaseUrl = "http://${listenAddress}:${toString honcho.apiPort}";
  jsonFormat = pkgs.formats.json {};
  honchoConfigTemplate = userName: let
    containerName = containerNameFor userName;
  in
    jsonFormat.generate "honcho-${userName}.json" {
      baseUrl = honchoBaseUrl;
      hosts.hermes = {
        enabled = true;
        workspace = containerName;
        peerName = userName;
        aiPeer = containerName;
        pinUserPeer = true;
        dialecticReasoningLevel = "high";
      };
    };
  telegramBotApi = cfg.telegramBotApi;
  telegramBotApiBaseUrl = "http://${listenAddress}";
  staticLeases =
    lib.mapAttrsToList (userName: container: "${container.macAddress},${container.staticLease},${containerNameFor userName}")
    cfg.containers;
in {
  imports = [
    ./hermes-nspawn/honcho.nix
    ./hermes-nspawn/telegram-bot-api.nix
  ];

  options.services.hermes-nspawn = {
    enable = lib.mkEnableOption "Hermes nspawn containers";
    containers = lib.mkOption {
      type = lib.types.attrs;
      description = "Hermes nspawn container definitions keyed by user name.";
    };
    defaultLan = lib.mkOption {
      type = lib.types.str;
      description = "homeRouter LAN used by containers that do not select one explicitly.";
    };
    newApiTokenDirectory = lib.mkOption {
      type = lib.types.path;
      description = "Directory containing New API tokens named hermes-<user>.";
    };
    newApiTokenRestartTriggers = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {};
      description = "Encrypted New API token files used as service restart triggers.";
    };
    dashboardDomain = lib.mkOption {
      type = lib.types.str;
      description = "Base domain for per-user Hermes dashboard public URLs.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services = lib.mkMerge (
      lib.mapAttrsToList (userName: _: let
        containerName = containerNameFor userName;
        dashboardCredentialName = "hermes-${userName}";
        secretsService = "${containerName}-secrets.service";
        serviceDependencies =
          ["podman-honcho-api.service"]
          ++ lib.optionals telegramBotApi.enable [
            "nginx.service"
            "telegram-bot-api.service"
          ];
      in {
        "${containerName}-secrets" = {
          description = "Prepare secrets for ${containerName}";
          after = ["honcho-runtime-env.service"];
          wants = ["honcho-runtime-env.service"];
          path = [
            pkgs.coreutils
            pkgs.jq
            pkgs.openssl
          ];
          serviceConfig = {
            Type = "oneshot";
            UMask = "0077";
          };
          script = ''
            set -euo pipefail

            newapi_token="$(tr -d '\r\n' < ${newApiTokenFile userName})"
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
            if [[ ! -s /var/lib/hermes/dashboard/${dashboardCredentialName}.pass ]]; then
              openssl rand -base64 24 > /var/lib/hermes/dashboard/${dashboardCredentialName}.pass
              chmod 0600 /var/lib/hermes/dashboard/${dashboardCredentialName}.pass
            fi
            if [[ ! -s /var/lib/hermes/dashboard/${dashboardCredentialName}.secret ]]; then
              openssl rand -hex 32 > /var/lib/hermes/dashboard/${dashboardCredentialName}.secret
              chmod 0600 /var/lib/hermes/dashboard/${dashboardCredentialName}.secret
            fi

            dashboard_password="$(tr -d '\r\n' < /var/lib/hermes/dashboard/${dashboardCredentialName}.pass)"
            dashboard_secret="$(tr -d '\r\n' < /var/lib/hermes/dashboard/${dashboardCredentialName}.secret)"
            honcho_api_key="$(tr -d '\r\n' < /var/lib/honcho/jwt-secret | ${lib.getExe pkgs.jwt-cli} encode \
              --secret @/dev/stdin \
              --no-iat \
              --payload t= \
              --payload w=${lib.escapeShellArg containerName})"

            secrets_dir=${secretDirectory containerName}
            env_tmp="$secrets_dir/.env.tmp"
            honcho_config_tmp="$secrets_dir/honcho.json.tmp"
            install -d -o root -g 1000 -m 0750 "$secrets_dir"
            trap 'rm -f "$env_tmp" "$honcho_config_tmp"' EXIT

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

            install -o root -g 1000 -m 0640 /dev/null "$honcho_config_tmp"
            jq \
              --arg apiKey "$honcho_api_key" \
              '.hosts.hermes.apiKey = $apiKey' \
              ${honchoConfigTemplate userName} \
              > "$honcho_config_tmp"

            mv -f "$env_tmp" "$secrets_dir/.env"
            mv -f "$honcho_config_tmp" "$secrets_dir/honcho.json"
          '';
        };
        "container@${containerName}" = {
          requires = [secretsService];
          wants = serviceDependencies;
          after = [secretsService] ++ serviceDependencies;
          restartTriggers = lib.optional (cfg.newApiTokenRestartTriggers ? "hermes-${userName}") cfg.newApiTokenRestartTriggers."hermes-${userName}";
          # Give systemd-nspawn time to release its veth pair before retrying
          # after a failed stop/start. A 100 ms retry can hit "File exists".
          serviceConfig.RestartSec = "5s";
        };
      })
      cfg.containers
    );

    containers = lib.mapAttrs' (userName: container: let
      containerName = containerNameFor userName;
      dashboardPublicUrl = "https://${userName}.${cfg.dashboardDomain}";
    in
      lib.nameValuePair containerName {
        autoStart = true;
        privateNetwork = true;
        hostBridge = coreBridge;
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
          inherit codexApiBaseUrl containerName dashboardPublicUrl hostPkgs inputs newApiBaseUrl telegramBotApi telegramBotApiBaseUrl;
          aptProxyAddress = listenAddress;
        };
        config =
          if container.canary or false
          then ./hermes-nspawn/guest-canary.nix
          else ./hermes-nspawn/guest.nix;
      })
    cfg.containers;

    # Every Hermes container uses the same terminal image. Expose one copy as
    # a host build output so CI can build it before the full host closure.
    system.build.hermesTerminalImage =
      config.containers.${containerNameFor (builtins.head (builtins.attrNames cfg.containers))}.config.system.build.hermesTerminalImage;

    systemd.network.networks = lib.mapAttrs' (userName: container: let
      containerName = containerNameFor userName;
    in
      lib.nameValuePair "50-${containerName}" {
        # systemd-nspawn names bridged host veths vb-*. Long names are hashed,
        # but the full vb-${containerName} is retained as an alternative name.
        matchConfig.Name = "vb-${containerName}";
        networkConfig.Bridge = coreBridge;
        bridgeVLANs = [
          {
            PVID = (containerLan container).vlan;
            EgressUntagged = (containerLan container).vlan;
          }
        ];
        linkConfig.RequiredForOnline = "no";
      })
    cfg.containers;

    networking.homeRouter.internalDhcpHosts = lib.mkAfter staticLeases;
  };
}

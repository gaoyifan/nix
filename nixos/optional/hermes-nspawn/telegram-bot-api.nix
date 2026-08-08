{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hermes-nspawn;
  telegramBotApi = cfg.telegramBotApi;
  allowedInterfaces = ["lo"] ++ config.networking.homeRouter.internalInterfaces;
in {
  options.services.hermes-nspawn.telegramBotApi = {
    enable = lib.mkEnableOption "local Telegram Bot API server";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.telegram-bot-api;
      description = "Telegram Bot API package to run.";
    };

    apiId = lib.mkOption {
      type = lib.types.int;
      description = "Telegram API application ID.";
    };

    apiHashEnvironmentFile = lib.mkOption {
      type = lib.types.path;
      description = "Runtime EnvironmentFile containing TELEGRAM_API_HASH.";
    };

    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 8081;
      description = "Telegram Bot API HTTP port.";
    };

    filePort = lib.mkOption {
      type = lib.types.port;
      default = 8082;
      description = "Telegram file server HTTP port.";
    };
  };

  config = lib.mkIf (cfg.enable && telegramBotApi.enable) {
    users.groups.telegram-bot-api = {};
    users.users.telegram-bot-api = {
      isSystemUser = true;
      group = "telegram-bot-api";
    };

    systemd.services.telegram-bot-api = {
      description = "Telegram Bot API server";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];
      environment = {
        TELEGRAM_API_ID = toString telegramBotApi.apiId;
      };
      serviceConfig = {
        User = "telegram-bot-api";
        Group = "telegram-bot-api";
        StateDirectory = "telegram-bot-api";
        StateDirectoryMode = "0750";
        RuntimeDirectory = "telegram-bot-api";
        RuntimeDirectoryMode = "0700";
        EnvironmentFile = telegramBotApi.apiHashEnvironmentFile;
        ExecStart = lib.escapeShellArgs [
          (lib.getExe telegramBotApi.package)
          "--http-ip-address=${cfg.listenAddress}"
          "--http-port=${toString telegramBotApi.apiPort}"
          "--dir=/var/lib/telegram-bot-api"
          "--temp-dir=/run/telegram-bot-api"
        ];
        Restart = "on-failure";
        RestartSec = 5;
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
      };
    };

    services.nginx = {
      enable = true;
      user = "telegram-bot-api";
      group = "telegram-bot-api";
      virtualHosts.telegram-bot-api-files = {
        default = true;
        listen = [
          {
            addr = cfg.listenAddress;
            port = telegramBotApi.filePort;
          }
        ];
        extraConfig = "access_log off;";
        locations = {
          "~ ^/file/bot([^/]+)/(.+/.+)$".alias = "/var/lib/telegram-bot-api/$1/$2";
          "/".return = "404";
        };
      };
    };

    # The conventional NixOS firewall is disabled by the homeRouter module.
    networking.nftables.tables.telegram-bot-api = {
      family = "inet";
      content = ''
        chain input {
          type filter hook input priority filter;
          iifname { ${lib.concatMapStringsSep ", " (interface: ''"${interface}"'') allowedInterfaces} } tcp dport { ${toString telegramBotApi.apiPort}, ${toString telegramBotApi.filePort} } accept
          tcp dport { ${toString telegramBotApi.apiPort}, ${toString telegramBotApi.filePort} } reject with tcp reset
        }
      '';
    };
  };
}

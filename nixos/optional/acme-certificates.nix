{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.acmeCertificates;
  stateDirectory = "/var/lib/acme-certificates";
  repositoryDirectory = "${stateDirectory}/repo";
  runtimeKey = "/run/acme-certificates/id_ed25519";
  serviceUnits = map (name: "${name}.service") cfg.restartServices;
  updateScript = pkgs.writeShellScript "update-acme-certificates" ''
    set -euo pipefail

    export GIT_SSH_COMMAND="${lib.getExe' pkgs.openssh "ssh"} -i ${runtimeKey} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=${stateDirectory}/known_hosts"

    if [[ ! -d ${repositoryDirectory}/.git ]]; then
      ${lib.getExe pkgs.git} clone --branch cert --single-branch git@github.com:gaoyifan/acme.git ${repositoryDirectory}
      exit 0
    fi

    ${lib.getExe pkgs.git} -C ${repositoryDirectory} fetch --quiet origin cert
    current="$(${lib.getExe pkgs.git} -C ${repositoryDirectory} rev-parse HEAD)"
    upstream="$(${lib.getExe pkgs.git} -C ${repositoryDirectory} rev-parse origin/cert)"
    [[ "$current" = "$upstream" ]] && exit 0

    ${lib.getExe pkgs.git} -C ${repositoryDirectory} reset --quiet --hard "$upstream"
    ${lib.optionalString (serviceUnits != []) "${lib.getExe' pkgs.systemd "systemctl"} try-restart --no-block ${lib.escapeShellArgs serviceUnits}"}
  '';
in {
  options.services.acmeCertificates = {
    enable = lib.mkEnableOption "periodic pull of the shared ACME certificate repository";

    directory = lib.mkOption {
      type = lib.types.str;
      default = repositoryDirectory;
      readOnly = true;
      description = "Runtime checkout of the ACME certificate repository.";
    };

    restartServices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Services restarted after the certificate repository advances.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services =
      {
        acme-certificates-update = {
          description = "Update shared ACME certificates";
          wantedBy = ["multi-user.target"];
          after = ["network-online.target"];
          wants = ["network-online.target"];
          serviceConfig = {
            Type = "oneshot";
            StateDirectory = "acme-certificates";
            RuntimeDirectory = "acme-certificates";
            UMask = "0077";
            ExecStartPre = "${lib.getExe' pkgs.coreutils "install"} -m 0600 ${config.services.secrets.nixos.acmeCertificates.sshPrivateKeyFile} ${runtimeKey}";
            ExecStart = updateScript;
          };
        };
      }
      // lib.genAttrs cfg.restartServices (_: {
        after = ["acme-certificates-update.service"];
        requires = ["acme-certificates-update.service"];
      });

    systemd.timers.acme-certificates-update = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*-*-* 06:23:00";
        Persistent = true;
      };
    };
  };
}

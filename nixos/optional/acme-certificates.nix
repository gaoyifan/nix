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

    changed=
    if [[ ! -d ${repositoryDirectory}/.git ]]; then
      ${lib.getExe pkgs.git} clone --branch cert --single-branch git@github.com:gaoyifan/acme.git ${repositoryDirectory}
      changed=1
    else
      ${lib.getExe pkgs.git} -C ${repositoryDirectory} fetch --quiet origin cert
      current="$(${lib.getExe pkgs.git} -C ${repositoryDirectory} rev-parse HEAD)"
      upstream="$(${lib.getExe pkgs.git} -C ${repositoryDirectory} rev-parse origin/cert)"

      if [[ "$current" != "$upstream" ]]; then
        ${lib.getExe pkgs.git} -C ${repositoryDirectory} reset --quiet --hard "$upstream"
        changed=1
      fi
    fi

    ${lib.optionalString (serviceUnits != []) ''
      if [[ -n "$changed" ]]; then
        for unit in ${lib.escapeShellArgs serviceUnits}; do
          if ${lib.getExe' pkgs.systemd "systemctl"} is-failed --quiet "$unit"; then
            ${lib.getExe' pkgs.systemd "systemctl"} start --no-block "$unit"
          else
            ${lib.getExe' pkgs.systemd "systemctl"} try-restart --no-block "$unit"
          fi
        done
      fi
    ''}
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
      description = "Services refreshed after the certificate repository changes; active units are restarted and failed units are started.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.resolved = {
      enable = true;
      dnsDelegates.acmeGithub.Delegate = {
        DNS = [
          "223.5.5.5"
          "223.6.6.6"
        ];
        Domains = ["github.com"];
      };
    };

    systemd.services =
      {
        acme-certificates-update = {
          description = "Update shared ACME certificates";
          after = [
            "network-online.target"
            "systemd-resolved.service"
          ];
          wants = ["network-online.target"];
          requires = ["systemd-resolved.service"];
          serviceConfig = {
            Type = "oneshot";
            StateDirectory = "acme-certificates";
            RuntimeDirectory = "acme-certificates";
            UMask = "0077";
            ExecStartPre = "${lib.getExe' pkgs.coreutils "install"} -m 0600 /run/agenix/acme-repository-pull-key ${runtimeKey}";
            ExecStart = updateScript;
            Restart = "on-failure";
            RestartSec = "1min";
          };
        };
      }
      // lib.genAttrs cfg.restartServices (_: {
        after = ["acme-certificates-update.service"];
        wants = ["acme-certificates-update.service"];
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

{
  config,
  inputs,
  lib,
  username,
  ...
}: let
  stateDirectory = "github-backup-tailscale";
  socket = "/run/${stateDirectory}/tailscaled.sock";
in {
  imports = [inputs.github-backup.nixosModules.default];

  config = lib.mkIf config.services.secrets.hasRealFiles {
    age.secrets = {
      oracle2-github-backup-token = {
        file = config.services.secrets.filesDir + "/nixos/oracle2/github-backup-token.age";
        owner = username;
      };
      oracle2-github-backup-ssh-key = {
        file = config.services.secrets.filesDir + "/nixos/oracle2/github-backup-ssh-key.age";
        owner = username;
      };
      oracle2-github-backup-webhook-secret = {
        file = config.services.secrets.filesDir + "/nixos/oracle2/github-backup-webhook-secret.age";
        owner = username;
      };
    };

    services.github-backup = {
      enable = true;
      user = username;
      group = "users";
      settings = {
        tokenFile = config.age.secrets.oracle2-github-backup-token.path;
        webhookSecretFile = config.age.secrets.oracle2-github-backup-webhook-secret.path;
        sshKeyFile = config.age.secrets.oracle2-github-backup-ssh-key.path;
        ignoreRepos = ["gaoyifan/genshin_impact-daily"];
      };
    };

    systemd.services.github-backup-tailscaled = {
      description = "Dedicated Tailscale node for the GitHub backup webhook";
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];
      after = ["network-online.target"];
      serviceConfig = {
        Type = "notify";
        StateDirectory = stateDirectory;
        StateDirectoryMode = "0700";
        RuntimeDirectory = stateDirectory;
        RuntimeDirectoryMode = "0755";
        ExecStart = lib.escapeShellArgs [
          "${config.services.tailscale.package}/bin/tailscaled"
          "--statedir=/var/lib/${stateDirectory}"
          "--socket=${socket}"
          "--tun=userspace-networking"
          "--port=41642"
          "--no-logs-no-support"
        ];
        ExecStartPost = [
          (lib.escapeShellArgs [
            "${config.services.tailscale.package}/bin/tailscale"
            "--socket=${socket}"
            "wait"
            "--timeout=30s"
          ])
          (lib.escapeShellArgs [
            "${config.services.tailscale.package}/bin/tailscale"
            "--socket=${socket}"
            "funnel"
            "--bg"
            "--https=443"
            "--yes"
            (toString config.services.github-backup.settings.listenPort)
          ])
        ];
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}

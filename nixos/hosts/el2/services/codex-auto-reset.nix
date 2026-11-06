{
  config,
  pkgs,
  ...
}: {
  systemd.services.codex-auto-reset = {
    description = "Redeem Codex reset credits one hour before expiry";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    wants = ["network-online.target"];
    path = [pkgs.codex];
    environment.CODEX_HOME = "${config.users.users.yifan.home}/.syncd-dotfiles/.codex";
    serviceConfig = {
      User = "yifan";
      ExecStart = "${pkgs.python3}/bin/python3 -u ${./codex-auto-reset.py} --apply";
      Restart = "on-failure";
      RestartSec = "5min";
    };
  };
}

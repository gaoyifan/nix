{
  inputs,
  pkgs,
  username,
  ...
}: {
  imports = [inputs.paseo.nixosModules.paseo];

  services.paseo = {
    enable = true;
    package = pkgs.paseo;
    user = username;
    group = "users";
    dataDir = "/var/lib/paseo";
    hostnames = ["paseo.ts.gaof.net"];
    relay.enable = false;
    inheritUserEnvironment = false;
    environment.CODEX_HOME = "/home/${username}/.syncd-dotfiles/.codex";
  };

  services.tailscale.serve.services.paseo.endpoints."tcp:6767" = "tcp://127.0.0.1:6767";

  systemd.services.paseo = {
    # Keep agent sessions running across NixOS switches; upgrade on manual restart.
    restartIfChanged = false;
    path = [pkgs.codex pkgs.git pkgs.openssh pkgs.bash pkgs.procps];
    serviceConfig.UMask = "0077";
  };
}

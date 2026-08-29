{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.tailscale;
in {
  options.services.tailscale = {
    interfaceName = lib.mkOption {
      type = lib.types.str;
      default = "tailscale0";
      description = "Tailscale tunnel interface name, or userspace-networking to avoid using TUN.";
    };
  };

  config = {
    environment.systemPackages = [pkgs.tailscale];
    systemd.packages = [pkgs.tailscale];

    # Debian sudo's secure_path does not include /run/system-manager/sw/bin.
    systemd.tmpfiles.rules = [
      "L+ /usr/local/bin/tailscale - - - - ${pkgs.tailscale}/bin/tailscale"
    ];

    systemd.services.tailscaled = {
      wantedBy = ["multi-user.target"];
      stopIfChanged = false;
      path = [
        (lib.dirOf config.security.wrapperDir)
        pkgs.procps
        pkgs.getent
        pkgs.kmod
      ];
      serviceConfig.Environment = [
        "PORT=6627"
        ''"FLAGS=--tun ${lib.escapeShellArg cfg.interfaceName} --no-logs-no-support"''
      ];
      serviceConfig.EnvironmentFile = "-/etc/default/tailscaled";
    };
  };
}

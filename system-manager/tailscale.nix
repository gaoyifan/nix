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

    port = lib.mkOption {
      type = lib.types.port;
      default = 6627;
      description = "UDP port used for Tailscale tunnel traffic.";
    };

    extraDaemonFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["--no-logs-no-support"];
      description = "Additional flags passed to tailscaled.";
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
        "PORT=${toString cfg.port}"
        ''"FLAGS=--tun ${lib.escapeShellArg cfg.interfaceName} ${lib.concatStringsSep " " cfg.extraDaemonFlags}"''
      ];
    };
  };
}

# Darwin system configuration
{
  config,
  lib,
  pkgs,
  username,
  ...
}: let
  cacheSettings = import ../nix-cache.nix;
  defaultHomebrew = import ./homebrew/default.nix;
in {
  # User configuration - required for home-manager
  users.users.${username}.home = "/Users/${username}";

  # Determinate manages nix.conf and includes this declarative custom file.
  nix.enable = false;
  environment.etc."nix/nix.custom.conf".text = ''
    extra-substituters = ${lib.concatStringsSep " " cacheSettings.extra-substituters}
    extra-trusted-public-keys = ${lib.concatStringsSep " " cacheSettings.extra-trusted-public-keys}
    extra-trusted-users = ${username}
  '';

  # Add homebrew bins to PATH for global tools
  environment.systemPath = [
    "/opt/homebrew/opt/node/bin"
    "/Users/${username}/.lmstudio/bin"
  ];
  environment.systemPackages = with pkgs; [
    just # Command runner
    nil # Nix language server
    bun # Fast JavaScript package manager
    tsshd # UDP-based SSH server with roaming support
  ];

  system = {
    # Used for backwards compatibility
    stateVersion = 6;

    # Primary user for nix-darwin (required for homebrew, etc.)
    primaryUser = username;

    # Disable startup chime
    startup.chime = false;
  };

  # Shorten rBBR's initial RTT probe, which otherwise limits downloads for a second.
  launchd.daemons.tcp-rbbr = {
    serviceConfig = {
      ProgramArguments = [
        "/usr/sbin/sysctl"
        "-w"
        "net.inet.tcp.rbbr_rtt_probe_min_duration=200"
      ];
      RunAtLoad = true;
    };
  };

  # Enable Touch ID authentication for sudo
  security.pam.services.sudo_local = {
    reattach = true;
    touchIdAuth = true;
  };

  homebrew =
    {
      enable = true;
      onActivation = {
        autoUpdate = true;
        cleanup = "uninstall";
      };
    }
    // (
      if config.networking.hostName == "yifans-mac-studio"
      then import ./homebrew/yifans-mac-studio.nix
      else defaultHomebrew
    );
}

{...}: {
  imports = [
    ../../optional/tailscale-gnet-vm-exit.nix
    ../../optional/vm-oracle-cloud.nix
    ./disk-config.nix
    ./github-backup.nix
    ./services.nix
  ];

  networking = {
    hostName = "oracle2";
    firewall.enable = false;
  };

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    kernelParams = ["console=ttyAMA0,115200"];
  };

  zramSwap = {
    enable = true;
    algorithm = "lz4";
    memoryPercent = 50;
  };

  services.resticBackup.extraExcludes = [
    "/srv/docker/bitmagnet-postgres"
    "/srv/github"
  ];

  system.stateVersion = "26.05";
}

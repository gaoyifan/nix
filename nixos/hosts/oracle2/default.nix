{config, ...}: {
  imports = [
    ../../optional/edge-firewall.nix
    ../../optional/tailscale-gnet-vm-exit.nix
    ../../optional/vm-oracle-cloud.nix
    ./auramont-runner.nix
    ./bees.nix
    ./disk-config.nix
    ./github-backup.nix
    ./services.nix
  ];

  networking = {
    hostName = "oracle2";
    edgeFirewall = {
      enable = true;
      extraPublicUdpPorts = [
        (toString config.services.bitmagnet.settings.dht_server.port)
        "41642" # Dedicated Tailscale node for GitHub backup.
      ];
    };
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

  services.resticBackup = {
    extraPaths = ["/var/lib/github-backup-tailscale"];
    extraExcludes = [
      "/srv/docker/bitmagnet-postgres"
      "/srv/github"
    ];
  };

  system.stateVersion = "26.05";
}

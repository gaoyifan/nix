{
  config,
  pkgs,
  username,
  ...
}: let
  userHome = config.users.users.${username}.home;
  composeService = description: directory: {
    inherit description;
    wants = ["docker.service" "network-online.target"];
    after = ["docker.service" "network-online.target"];
    wantedBy = ["multi-user.target"];
    environment.DOCKER_BUILDKIT = "1";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = directory;
      ExecStart = "${pkgs.docker}/bin/docker compose up -d --build";
      ExecStop = "${pkgs.docker}/bin/docker compose stop";
    };
  };
in {
  imports = [
    ../../optional/qemu-guest.nix
    ../../optional/tailscale-gnet-vm-exit.nix
    ./codex-capacity-proxy.nix
    ./disk-config.nix
    ./github-backup.nix
  ];

  networking = {
    hostName = "oracle2";
    useDHCP = false;
    useNetworkd = true;
    firewall.enable = false;
  };

  systemd.network.networks."10-wan" = {
    matchConfig.Type = "ether";
    networkConfig = {
      DHCP = "yes";
      IPv6AcceptRA = true;
    };
    linkConfig.RequiredForOnline = "routable";
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

  users.users.${username} = {
    uid = 1000;
    extraGroups = ["docker"];
  };

  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      iptables = false;
      ip6tables = false;
      bridge = "none";
    };
  };

  services.resticBackup.extraExcludes = [
    "/srv/docker/bitmagnet-postgres"
    "/srv/github"
  ];

  systemd.services = {
    bitmagnet-oracle2 = composeService "Bitmagnet Compose project" "${userHome}/docker-run-scripts/bitmagnet-oracle2";
  };

  time.timeZone = "UTC";
  system.stateVersion = "26.05";
}

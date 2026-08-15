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
    ../../optional/nylon.nix
    ../../optional/qemu-guest.nix
    ./disk-config.nix
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

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";
    extraSetFlags = [
      "--accept-dns=false"
      "--accept-routes"
      "--netfilter-mode=off"
      "--snat-subnet-routes=false"
    ];
  };

  services.nylon = {
    enable = true;
    cloudflareWarp = {
      enable = true;
      label = 101;
      ipv6Address = "2606:4700:110:85d7:5c0:159f:4a50:99";
      reserved = "0xdeeca8";
    };
    overlay = {
      ipv4Subnet = "10.250.10.0/24";
      ipv6Subnet = "fd10:250:10::/64";
      nat.enable = false;
    };
    routeBatch.enable = false;
    exits.oracle.label = 100;
  };

  systemd.services = {
    bitmagnet-oracle2 = composeService "Bitmagnet Compose project" "${userHome}/docker-run-scripts/bitmagnet-oracle2";
    github-backup = composeService "GitHub backup Compose project" "${userHome}/github-backup";
  };

  time.timeZone = "UTC";
  system.stateVersion = "26.05";
}

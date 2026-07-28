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
    ../../optional/nylon.nix
    ./disk-config.nix
  ];

  networking = {
    hostName = "oracle2";
    useDHCP = false;
    useNetworkd = true;
    firewall.enable = false;
    nftables = {
      enable = true;
      tables.warp = {
        family = "inet";
        content = ''
          set warpep4 {
            type ipv4_addr
            elements = { 162.159.192.1, 162.159.192.2, 162.159.192.3, 162.159.192.4, 162.159.192.5, 162.159.193.1, 162.159.193.2, 162.159.193.3, 162.159.193.4, 162.159.193.5 }
          }
          set warpep6 {
            type ipv6_addr
            elements = { 2606:4700:d0::a29f:c001, 2606:4700:d0::a29f:c002, 2606:4700:d0::a29f:c003, 2606:4700:d0::a29f:c004, 2606:4700:d0::a29f:c005 }
          }
          set warpport {
            type inet_service
            elements = { 500, 1701, 2408, 4500 }
          }
          chain warp-in {
            type filter hook input priority -150; policy accept;
            ip saddr @warpep4 udp sport @warpport @th,72,24 set 0x0
            ip6 saddr @warpep6 udp sport @warpport @th,72,24 set 0x0
          }
          chain warp-out {
            type filter hook output priority -150; policy accept;
            ip daddr @warpep4 udp dport @warpport @th,72,24 set 0xdeeca8
            ip6 daddr @warpep6 udp dport @warpport @th,72,24 set 0xdeeca8
          }
        '';
      };
    };
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

  networking.wg-quick.interfaces.wg-cloudflare.configFile = "/etc/wireguard/wg-cloudflare.conf";

  services.nylon = {
    enable = true;
    overlay = {
      ipv4Subnet = "10.250.10.0/24";
      ipv6Subnet = "fd10:250:10::/64";
      nat.enable = false;
    };
    routeBatch.enable = false;
    exits = {
      oracle.label = 100;
      warp = {
        label = 101;
        interface = "wg-cloudflare";
      };
    };
  };

  systemd.services = {
    bitmagnet-oracle2 = composeService "Bitmagnet Compose project" "${userHome}/docker-run-scripts/bitmagnet-oracle2";
    github-backup = composeService "GitHub backup Compose project" "${userHome}/github-backup";
  };

  time.timeZone = "UTC";
  system.stateVersion = "26.05";
}

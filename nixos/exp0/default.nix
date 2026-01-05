# exp0 - NixOS router configuration
{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../modules/router
    ../../secrets
  ];

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "exp0";

  # Router configuration
  router = {
    lan = {
      ifname = "enp26s0";
      address = "192.168.10.1";
      prefixLength = 24;
      dhcpRange = {
        start = "192.168.10.100";
        end = "192.168.10.200";
      };
      domain = "lan";
    };

    wan = {
      ifname = "enp2s0";
      managementAddress = "100.65.1.104/24";
      managementGateway = "100.65.1.254";
    };

    pppoe = {
      enable = true;
      user = "test";
    };

    wgWan = {
      enable = true;
      address = "100.64.110.22/24";
      mtu = 1392;
      fwMark = 51820;
      peer = {
        publicKey = "hfIT0ALpVJ8g+cwwPjLIRNHQI8xcYsNIFvg+xDdNPwI=";
        endpoint = "wg.gaof.net:2197";
        allowedIPs = ["0.0.0.0/0"];
      };
    };

    tailscale = {
      enable = true;
      advertiseRoutes = ["192.168.10.0/24"];
    };

    policyRouting = {
      wgMark = 2;
      wgDestinations = [
        "1.1.1.1"
        "8.8.8.0/24"
        "9.9.9.9"
      ];
    };

    adguard = {
      enable = true;
      webPort = 3000;
      upstreamDns = ["1.1.1.1" "8.8.8.8" "9.9.9.9"];
      bootstrapDns = ["1.1.1.1" "8.8.8.8"];
    };
  };

  # Enable secrets for this host
  services.secrets.nixos.exp0 = {};

  time.timeZone = "Asia/Shanghai";

  users.users.yifan = {
    isNormalUser = true;
    description = "Yifan";
    extraGroups = ["networkmanager" "wheel"];
  };

  security.sudo.wheelNeedsPassword = false;

  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "25.11";
}

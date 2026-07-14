# nix-cache - VMware guest migrated from the gateway cluster.
{
  lib,
  username,
  ...
}: {
  networking = {
    hostName = "nix-cache";
    useDHCP = false;
    useNetworkd = true;
    nameservers = ["100.64.1.254"];
    firewall.enable = false;
  };

  systemd.network.networks."10-static-uplink" = {
    matchConfig = {
      Driver = "vmxnet3";
      Type = "ether";
    };
    address = ["100.64.1.25/24"];
    routes = [{Gateway = "100.64.1.254";}];
    networkConfig.IPv6AcceptRA = false;
    linkConfig.RequiredForOnline = "routable";
  };

  boot = {
    initrd.availableKernelModules = [
      "vmw_pvscsi"
      "vmxnet3"
    ];
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-partlabel/disk-system-root";
      fsType = "btrfs";
      options = [
        "subvol=root"
        "compress=zstd"
        "noatime"
      ];
    };
    "/nix" = {
      device = "/dev/disk/by-partlabel/disk-system-root";
      fsType = "btrfs";
      options = [
        "subvol=nix"
        "compress=zstd"
        "noatime"
      ];
    };
    "/boot" = {
      device = "/dev/disk/by-partlabel/disk-system-ESP";
      fsType = "vfat";
      options = ["umask=0077"];
    };
  };

  swapDevices = [];
  virtualisation.vmware.guest.enable = true;
  home-manager.users.${username}.services.mutagen.dotfileSync.enable = false;

  nix.settings.substituters = lib.mkForce [
    "https://mirrors.ustc.edu.cn/nix-channels/store"
    "https://cache.nixos.org/"
  ];

  services.ncps = {
    enable = true;
    analytics.reporting.enable = false;
    cache = {
      hostName = "ncps";
      maxSize = "45G";
      lru = {
        schedule = "0 11 * * *";
      };
      signNarinfo = false;
      upstream = {
        urls = ["https://cache.nixos.org"];
        publicKeys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        ];
      };
    };
  };

  system.stateVersion = "26.05";
}

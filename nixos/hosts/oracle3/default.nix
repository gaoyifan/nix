{username, ...}: {
  imports = [
    ../../optional/qemu-guest.nix
    ./disk-config.nix
  ];

  networking = {
    hostName = "oracle3";
    nameservers = ["169.254.169.254"];
    useDHCP = false;
    useNetworkd = true;
    firewall.enable = false;
  };

  systemd.network = {
    links."10-wan" = {
      matchConfig.Path = "pci-0000:00:03.0";
      linkConfig.Name = "ens3";
    };
    networks."10-wan" = {
      matchConfig.Name = "ens3";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
      dhcpV4Config.UseDNS = false;
      dhcpV6Config.UseDNS = false;
      ipv6AcceptRAConfig.UseDNS = false;
      linkConfig.RequiredForOnline = "routable";
    };
  };

  boot = {
    loader.grub = {
      enable = true;
      device = "nodev";
      efiInstallAsRemovable = true;
      efiSupport = true;
    };
    kernelParams = [
      "console=tty0"
      "console=ttyS0,115200n8"
    ];
    zswap.enable = true;
  };

  users.users.${username}.uid = 1000;

  services.journald.extraConfig = "SystemMaxUse=256M";

  time.timeZone = "UTC";
  system.stateVersion = "26.05";
}

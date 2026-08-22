{pkgs, ...}: {
  imports = [
    ../../optional/bare-metal.nix
    ./hardware-configuration.nix
    ./networking.nix
    ./storage.nix
    ./tailscale.nix
  ];

  networking = {
    hostName = "nfs";
    domain = "el.gaof.net";
    hostId = "007f0101";
  };

  boot = {
    kernelParams = ["mitigations=off"];
    loader.grub.device = "/dev/disk/by-id/usb-HP_iLO_Internal_SD-CARD_000002660A01-0:0";
    zfs = {
      forceImportRoot = false;
      requestEncryptionCredentials = false;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIKB07e9NGMc9k4soiOCpRdiRySfiUqu1BaRYb1wtBMu root@nfs2"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICvHyQJ4IcT/2+yIOkogklx/qCd3HfRcwN2RLgjzlXmq root@nfs3"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKy9koomKIJUK+x2SN8gZkurFngrjHLZnRroG00EyTv4 root@el2"
  ];

  environment.systemPackages = [pkgs.mbuffer];

  system.stateVersion = "26.05";
}

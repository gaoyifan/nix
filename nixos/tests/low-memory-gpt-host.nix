{
  modulesPath,
  pkgs,
  ...
}: let
  inherit
    (import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs)
    snakeOilEd25519PublicKey
    ;
in {
  imports = [(modulesPath + "/profiles/minimal.nix")];

  boot = {
    initrd.availableKernelModules = ["virtio_blk" "virtio_pci"];
    loader.grub = {
      devices = [];
      efiInstallAsRemovable = true;
      efiSupport = true;
      enable = true;
    };
    supportedFilesystems = ["btrfs" "vfat"];
  };

  disko.devices.disk.system = {
    type = "disk";
    device = "/dev/vda";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = ["umask=0077"];
          };
        };
        swap = {
          size = "1G";
          content.type = "swap";
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "btrfs";
            mountpoint = "/";
            mountOptions = ["compress=zstd:3" "noatime"];
          };
        };
      };
    };
  };

  environment.systemPackages = [pkgs.util-linux];
  networking = {
    hostName = "gpt-btrfs";
    useDHCP = false;
    useNetworkd = true;
  };
  services.openssh.enable = true;
  system.stateVersion = "26.05";
  systemd.network.networks."10-ethernet" = {
    matchConfig.Type = "ether";
    networkConfig.DHCP = "yes";
  };
  users.users.root.openssh.authorizedKeys.keys = [snakeOilEd25519PublicKey];
}

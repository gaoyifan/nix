# Network configuration for somo-minisforum.
#
# CMCC WAN: enp3s0. USB tethering WANs: iOS ipheth or RNDIS interfaces.
# LAN switching: enp4s0 carries native VLAN 652 plus tagged VLANs 653 and 654.
{
  config,
  lib,
  ...
}: {
  imports = [
    ../../optional/oob-ssh.nix
    ../../optional/somo-router.nix
  ];

  networking.hostName = "somo-minisforum";
  networking.homeRouter.wgIplc = {
    ip = "11.13.112.80/24";
    privateKeyFile = config.services.secrets.filesDir + "/nixos/somo-minisforum/wg-iplc-private-key.age";
  };

  services.oobSsh = {
    enable = true;
    parentInterface = "enp3s0";
    address = "198.18.233.233/24";
  };

  networking.somoRouter = {
    enable = true;
    wanDevice = "enp3s0";
    lanPort = "enp4s0";
    nativeVlan = 652;
    lanSubnetBase = 2;
  };

  networking.homeRouter.switch.ports.wlp6s0.untagged = 652;
  systemd.network.networks."10-wan-cmcc".linkConfig.RequiredFamilyForOnline = "both";
  systemd.network.networks."11-usb-wan".linkConfig.RequiredForOnline = "no";
}

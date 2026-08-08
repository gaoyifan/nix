# Network configuration for somo-minisforum.
#
# CMCC WAN: enp3s0. USB tethering WANs: iOS ipheth or RNDIS interfaces.
# LAN switching: enp4s0 carries native VLAN 652 plus tagged VLANs 653 and 654.
{
  config,
  lib,
  ...
}: {
  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    wlt-server-key.file = config.services.secrets.filesDir + "/nixos/wlt-server-key.pem.age";
    wlt-ssh-host-key.file = config.services.secrets.filesDir + "/nixos/wlt-ssh-host-key.age";
  };

  imports = [../../optional/somo-router.nix];

  networking.hostName = "somo-minisforum";
  networking.somoRouter = {
    enable = true;
    wanDevice = "enp3s0";
    lanPort = "enp4s0";
    nativeVlan = 652;
    lanSubnetBase = 2;
  };

  networking.homeRouter.switch.ports.wlp6s0.untagged = 652;
  systemd.network.networks."11-usb-wan".linkConfig.RequiredForOnline = "no";
}

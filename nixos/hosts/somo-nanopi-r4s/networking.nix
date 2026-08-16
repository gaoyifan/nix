# Network configuration for somo-nanopi-r4s.
#
# WAN: end0 (CPU internal GMAC). USB tethering WANs: iOS ipheth or RNDIS.
# LAN switching: enp1s0 carries native VLAN 653 plus tagged VLANs 652 and 654.
{
  config,
  lib,
  ...
}: {
  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    wlt-server-key.file = config.services.secrets.filesDir + "/nixos/wlt-server-key.pem.age";
    wlt-ssh-host-key.file = config.services.secrets.filesDir + "/nixos/wlt-ssh-host-key.age";
  };

  imports = [
    ../../optional/oob-ssh.nix
    ../../optional/somo-router.nix
  ];

  networking.hostName = "somo-nanopi-r4s";
  networking.homeRouter.wgIplc = {
    ip = "11.13.112.79/24";
    privateKeyFile = config.services.secrets.filesDir + "/nixos/somo-nanopi-r4s/wg-iplc-private-key.age";
  };

  services.oobSsh = {
    enable = true;
    parentInterface = "end0";
    address = "198.18.233.234/24";
  };

  networking.somoRouter = {
    enable = true;
    wanDevice = "end0";
    lanPort = "enp1s0";
    nativeVlan = 653;
    lanSubnetBase = 12;
  };

  systemd.network.wait-online.anyInterface = true;
  systemd.network.networks."11-usb-wan".linkConfig.RequiredForOnline = "routable";
  services.resolved.settings.Resolve.DNS = lib.mkAfter ["223.5.5.5"];
}

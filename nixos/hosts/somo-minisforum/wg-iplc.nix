{
  config,
  lib,
  ...
}: let
  filesDir = config.services.secrets.filesDir;
  wg = import (filesDir + "/nixos/somo-minisforum/wg-iplc.nix");
in {
  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    somo-minisforum-wg-iplc-private-key.file = filesDir + "/nixos/somo-minisforum/wg-iplc-private-key.age";
  };

  networking.wireguard.interfaces.${wg.interfaceName} = {
    ips = wg.ips;
    privateKeyFile = "/run/agenix/somo-minisforum-wg-iplc-private-key";
    mtu = wg.mtu;
    table = wg.routeTable;
    fwMark = wg.socketMark;
    peers = [wg.peer];
  };
}

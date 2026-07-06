{config, ...}: let
  wg = config.services.secrets.nixos."somo-minisforum".wgEl2;
in {
  networking.wireguard.interfaces.${wg.interfaceName} = {
    ips = wg.ips;
    privateKeyFile = wg.privateKeyFile;
    mtu = wg.mtu;
    table = wg.routeTable;
    fwMark = wg.socketMark;
    peers = [wg.peer];
  };
}

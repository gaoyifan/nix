{
  config,
  lib,
  ...
}: let
  filesDir = config.services.secrets.filesDir;
  wg = import (filesDir + "/nixos/somo-nanopi-r4s/wg-iplc.nix");
in {
  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    somo-nanopi-r4s-wg-iplc-private-key.file = filesDir + "/nixos/somo-nanopi-r4s/wg-iplc-private-key.age";
  };

  networking.wireguard.interfaces.wg-iplc = {
    ips = wg.ips;
    privateKeyFile = "/run/agenix/somo-nanopi-r4s-wg-iplc-private-key";
    mtu = wg.mtu;
    peers = [wg.peer];
  };
}

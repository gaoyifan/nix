{
  config,
  lib,
  ...
}: {
  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    cjia-wg-iplc-private-key.file = config.services.secrets.filesDir + "/nixos/cjia/wg-iplc-private-key.age";
  };

  networking.wireguard.interfaces.wg-iplc = {
    ips = ["11.13.112.43/24"];
    privateKeyFile = "/run/agenix/cjia-wg-iplc-private-key";
    mtu = 1412;
    peers = [
      {
        publicKey = "AfdrmhJVEoehssQxblgVRsdCn/ly4hOQjL04T+YxPCY=";
        endpoint = "61.172.164.76:51820";
        allowedIPs = ["0.0.0.0/0"];
        persistentKeepalive = 25;
      }
    ];
  };
}

{...}: {
  networking.wireguard.interfaces.wg-iplc = {
    ips = ["11.13.112.77/24"];
    privateKeyFile = "/var/lib/wireguard/wg-iplc-private-key";
    mtu = 1392;
    table = "5110";
    fwMark = "0x90000";
    peers = [
      {
        publicKey = "AfdrmhJVEoehssQxblgVRsdCn/ly4hOQjL04T+YxPCY=";
        endpoint = "wg.int.automesh.org:51820";
        allowedIPs = ["0.0.0.0/0"];
        persistentKeepalive = 60;
      }
    ];
  };
}

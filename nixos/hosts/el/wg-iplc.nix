{...}: {
  networking.wireguard.interfaces.wg-iplc = {
    ips = ["11.13.112.74/24"];
    privateKeyFile = "/var/lib/wireguard/wg-iplc-private-key";
    mtu = 1392;
    peers = [
      {
        publicKey = "AfdrmhJVEoehssQxblgVRsdCn/ly4hOQjL04T+YxPCY=";
        endpoint = "wg.int.automesh.org:51820";
        allowedIPs = ["0.0.0.0/0"];
        persistentKeepalive = 60;
      }
    ];
  };

  systemd.tmpfiles.rules = ["d /var/lib/wireguard 0700 root root -"];
}

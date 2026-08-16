{
  ips = ["192.0.2.80/24"];
  mtu = 1392;
  peer = {
    publicKey = "example";
    endpoint = "203.0.113.1:51820";
    allowedIPs = ["0.0.0.0/0"];
    persistentKeepalive = 60;
  };
}

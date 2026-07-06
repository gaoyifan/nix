{
  interfaceName = "wg-el2";
  ips = ["100.64.110.58/32"];
  mtu = 1392;
  routeTable = "5110";
  mark = "0x100";
  socketMark = "0x90000";
  peer = {
    publicKey = "example";
    endpoint = "203.0.113.1:51820";
    allowedIPs = ["0.0.0.0/0"];
    persistentKeepalive = 25;
  };
}

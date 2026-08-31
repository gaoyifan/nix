{
  defaults = {
    port = 6622;
    mtu = 1400;
    interfaceName = "nylon0";
    tcpObfuscation = true;
    udpCost = "5ms";
    transitCost = "3ms";
    selector = {
      enable = false;
      ipv6 = true;
    };
  };

  overlay = {
    ipv4Prefix = "10.250.10";
    ipv6Prefix = "fd10:250:10::";
  };

  topology.kind = "full-mesh";

  dns = {
    zone = "ny.gaof.net.";
    ttl = 300;
    controller = "el2";
    apiUrl = "http://pdns-ui.ts.gaof.net/api/v1/servers/localhost/zones/ny.gaof.net";
  };

  # 21 belonged to the resource-constrained google node, 22 to the retired
  # hetzner0 node, and 27 to los6. Keep all retired identities reserved.
  reservedNumericIds = [
    21
    22
    27
  ];

  expected = {
    nodeCount = 16;
    exitCount = 24;
    selectorCount = 5;
  };
}

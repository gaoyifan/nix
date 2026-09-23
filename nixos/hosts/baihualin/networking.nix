{
  imports = [../../optional/home-router];

  networking.homeRouter = {
    enable = true;
    monitoring.enable = true;

    switch.ports.lan1.untagged = 661;
    lans.baihualin = {
      vlan = 661;
      addresses = ["100.66.1.254/24"];
      dhcpServer.range = "100.66.1.100,100.66.1.200,24h";
      ipv6.enable = false;
    };

    wans.wan = {
      device = "wan0";
      dhcp = true;
    };

    dnsmasq.domain = "baihualin.gaof.net";
    wlt.dns.entryInterfaces = ["tailscale0"];
  };
}

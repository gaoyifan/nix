{
  numericId = 35;
  publicKey = "uTBhjBt3kLFII48WrHPEBjHq4OyDrcgMG1JFgdVh6XI=";

  selector.enable = true;

  underlays.chinanet = {
    interface = "wan0";
    bind = true;
    lanDiscovery = true;
    exit = {
      label = 100;
      families = {
        ipv4 = true;
        ipv6 = false;
      };
      presentation = {
        location = "CN,伊宁";
        operator = "中国电信";
      };
    };
  };
}

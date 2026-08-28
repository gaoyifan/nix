{
  numericId = 17;
  publicKey = "crKcgKHOSmkL+UyFyqu5sQ0Di/QieWUaLCQeSuQD8XU=";
  transitCost = "200ms";

  selector = {
    enable = true;
    ipv6 = false;
  };

  underlays.ppp = {
    interface = "ppp0";
    bind = true;
    exit = {
      label = 100;
      families = {
        ipv4 = true;
        ipv6 = false;
      };
      presentation = {
        location = "CN,杭州";
        operator = "中国电信";
      };
    };
  };
}

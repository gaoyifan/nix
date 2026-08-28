{
  numericId = 20;
  publicKey = "FObi7NlRrBGfLQTyz4OEf5JXefx+703iD3/PQmg9fGI=";

  selector = {
    enable = true;
  };

  underlays = {
    cernet = {
      interface = "br-core.931";
      endpoint = {
        ipv4 = "202.38.93.98";
        ipv6 = "2001:da8:d800:931::98";
      };
      bindSource = true;
      exit = {
        label = 100;
        gateway4 = "202.38.93.254";
        ipv4Address = "202.38.93.98";
        ipv6Address = "2001:da8:d800:931::98";
        families = {
          ipv4 = true;
          ipv6 = true;
        };
        presentation = {
          location = "CN,合肥";
          operator = "教育网";
        };
      };
    };

    chinanet = {
      interface = "br-core.22";
      endpoint.ipv4 = "202.141.162.72";
      bindSource = true;
      exit = {
        label = 101;
        gateway4 = "202.141.162.126";
        ipv4Address = "202.141.162.72";
        families = {
          ipv4 = true;
          ipv6 = false;
        };
        presentation = {
          location = "CN,合肥";
          operator = "中国电信";
        };
      };
    };

    cmcc = {
      interface = "br-core.22";
      endpoint.ipv4 = "202.141.178.7";
      bindSource = true;
      exit = {
        label = 102;
        gateway4 = "202.141.178.126";
        ipv4Address = "202.141.178.7";
        families = {
          ipv4 = true;
          ipv6 = false;
        };
        presentation = {
          location = "CN,合肥";
          operator = "中国移动";
        };
      };
    };
  };
}

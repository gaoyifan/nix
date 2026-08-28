{
  numericId = 19;
  publicKey = "xm+vs+haHAj+9DuBbCue/m2+hb9/SgvVlBVkjp4xlxw=";

  selector = {
    enable = true;
  };

  underlays = {
    cernet = {
      interface = "br-core.931";
      endpoint = {
        ipv4 = "202.38.93.152";
        ipv6 = "2001:da8:d800:931::152";
      };
      bindSource = true;
      exit = {
        label = 100;
        gateway4 = "202.38.93.254";
        ipv4Address = "202.38.93.152";
        ipv6Address = "2001:da8:d800:931::152";
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
      endpoint.ipv4 = "202.141.162.122";
      bindSource = true;
      exit = {
        label = 101;
        gateway4 = "202.141.162.126";
        ipv4Address = "202.141.162.122";
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
      endpoint.ipv4 = "202.141.178.12";
      bindSource = true;
      exit = {
        label = 102;
        gateway4 = "202.141.178.126";
        ipv4Address = "202.141.178.12";
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

{
  numericId = 18;
  publicKey = "Tjw/WB59GdfvGDZADC2P47LiUDwkvIa84Q1j8AL9G1o=";

  underlays = {
    public = {
      interface = "eth0";
      endpoint = {
        ipv4 = "8.219.248.49";
        ipv6 = "240b:4000:28:b900::1";
      };
      exit = {
        label = 100;
        useDefaultRoute = true;
        families = {
          ipv4 = true;
          ipv6 = true;
        };
        presentation = {
          location = "SG,Singapore";
          operator = "Alibaba Cloud";
        };
      };
    };

    warp = {
      interface = "wg-cloudflare";
      cloudflareWarp = {
        ipv6Address = "2606:4700:110:8e8b:797f:40b6:888f:acfb";
        reserved = "0x1b0ed6";
      };
      exit = {
        label = 101;
        families = {
          ipv4 = true;
          ipv6 = true;
        };
        presentation = {
          location = "SG,Singapore";
          operator = "Cloudflare WARP";
        };
      };
    };
  };
}

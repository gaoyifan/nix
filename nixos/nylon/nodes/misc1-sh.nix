{
  numericId = 24;
  publicKey = "El8uYwftbl3EJ3nDlEKNxHrfg9g8JA9MwcBb3N+Bk04=";

  underlays = {
    alvidi = {
      interface = "eth0";
      endpoint.ipv4 = "103.90.137.101";
      bindSource = true;
      exit = {
        label = 100;
        useDefaultRoute = true;
        families = {
          ipv4 = true;
          ipv6 = false;
        };
        presentation = {
          location = "JP,Tokyo";
          operator = "ALVIDI";
        };
      };
    };

    shanghai = {
      interface = "eth1";
      endpoint.ipv4 = "61.172.164.79";
      bindSource = true;
      exit = {
        label = 101;
        gateway4 = "61.172.164.1";
        families = {
          ipv4 = true;
          ipv6 = false;
        };
        presentation = {
          location = "CN,上海";
          operator = "中国电信";
        };
      };
    };

    warp = {
      interface = "wg-cloudflare";
      cloudflareWarp = {
        ipv6Address = "2606:4700:110:8eab:cfbe:2c01:5062:8c3c";
        reserved = "0x3e781e";
      };
      exit = {
        label = 102;
        families = {
          ipv4 = true;
          ipv6 = true;
        };
        presentation = {
          location = "JP,Tokyo";
          operator = "Cloudflare WARP";
        };
      };
    };
  };
}

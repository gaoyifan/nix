{
  numericId = 34;
  publicKey = "usOXyUA1h7RPQiXx9qhBS2OFV/zXQjmpw271zkPTO1o=";

  underlays = {
    public = {
      interface = "ens3";
      endpoint = {
        ipv4 = "103.27.187.241";
        ipv6 = "2403:ad80:89:4c00:15:0:8c0:6b7c";
      };
      exit = {
        label = 100;
        useDefaultRoute = true;
        families = {
          ipv4 = true;
          ipv6 = true;
        };
        presentation = {
          location = "JP,Tokyo";
          operator = "HHost";
        };
      };
    };

    warp = {
      interface = "wg-cloudflare";
      cloudflareWarp = {
        ipv6Address = "2606:4700:110:8403:9532:a7dd:f93c:2074";
        reserved = "0xa15a28";
      };
      exit = {
        label = 101;
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

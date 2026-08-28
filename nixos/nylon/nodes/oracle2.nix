{
  numericId = 26;
  publicKey = "zCQkKE3NIgUcEOtt9mYeuJn0tR/TtA+EGigpIOKHgBI=";

  underlays = {
    public = {
      interface = "enp0s6";
      endpoint = {
        ipv4 = "159.54.183.16";
        ipv6 = "2603:c024:c01d:1600::ff";
      };
      exit = {
        label = 100;
        useDefaultRoute = true;
        families = {
          ipv4 = true;
          ipv6 = true;
        };
        presentation = {
          location = "US,San Jose";
          operator = "Oracle";
        };
      };
    };

    warp = {
      interface = "wg-cloudflare";
      cloudflareWarp = {
        ipv6Address = "2606:4700:110:85d7:5c0:159f:4a50:99";
        reserved = "0xdeeca8";
      };
      exit = {
        label = 101;
        families = {
          ipv4 = true;
          ipv6 = true;
        };
        presentation = {
          location = "US,San Jose";
          operator = "Cloudflare WARP";
        };
      };
    };
  };
}

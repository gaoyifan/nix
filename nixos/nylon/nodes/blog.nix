{
  numericId = 16;
  publicKey = "G2+YXXO8fZducMyCDqrG617QMYwIVAPP6/T/OdrKumI=";
  transitCost = "200ms";

  underlays.public = {
    interface = "ens5";
    endpoint = {
      ipv4 = "47.99.220.147";
      ipv6 = "2408:4005:34e:d00::1";
    };
    exit = {
      label = 100;
      useDefaultRoute = true;
      families = {
        ipv4 = true;
        ipv6 = true;
      };
      presentation = {
        location = "CN,杭州";
        operator = "阿里云";
      };
    };
  };
}

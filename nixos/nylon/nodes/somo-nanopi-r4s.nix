{
  numericId = 32;
  publicKey = "DS4MeFp/AzE3/j9e3KprMTY4gLMoBTo9Edu4HsvilRY=";

  selector = {
    enable = true;
  };

  underlays.cmcc = {
    interface = "end0";
    bind = true;
    lanDiscovery = true;
    exit = {
      label = 100;
      families = {
        ipv4 = true;
        ipv6 = false;
      };
      presentation = {
        location = "CN,杭州";
        operator = "中国移动";
      };
    };
  };
}

{
  numericId = 28;
  publicKey = "mE/qgQ1wsaDUlg4ioXKKQoc4kNGJVnyEFPw5GedUHHI=";

  selector = {
    enable = true;
  };

  underlays.cmcc = {
    interface = "enp3s0";
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

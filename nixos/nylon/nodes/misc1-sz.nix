{
  numericId = 23;
  # misc1-sz retained misc0-sz's Nylon identity during the host migration.
  publicKey = "rJkbnEB4gSGtuJLo1H+lwDkW5rOudXgbaVTAPhV4bgo=";

  underlays = {
    alvidi = {
      interface = "eth0";
      endpoint.ipv4 = "58.84.55.69";
      bindSource = true;
      exit = {
        label = 100;
        useDefaultRoute = true;
        families = {
          ipv4 = true;
          ipv6 = false;
        };
        presentation = {
          location = "HK,香港";
          operator = "ALVIDI";
        };
      };
    };

    shenzhen = {
      interface = "eth1";
      endpoint.ipv4 = "14.215.130.15";
      bindSource = true;
      exit = {
        label = 101;
        gateway4 = "14.215.130.1";
        families = {
          ipv4 = true;
          ipv6 = false;
        };
        presentation = {
          location = "CN,深圳";
          operator = "中国电信";
        };
      };
    };
  };
}

{
  config,
  lib,
  ...
}: let
  lanInterface = config.networking.homeRouter.lans.cjia.interface;
in {
  imports = [
    ../../optional/diverge.nix
    ../../optional/nylon.nix
  ];

  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    cjia-godns-password.file = config.services.secrets.filesDir + "/nixos/cjia/godns-password.age";
  };

  services.diverge.enable = true;

  services.nylon = {
    enable = true;
    policyRouting.enable = true;
    overlay = {
      ipv4Subnet = "10.250.10.0/24";
      ipv6Subnet = "fd10:250:10::/64";
    };
    exits.ppp = {
      label = 100;
      interface = "ppp0";
    };
  };

  services.godns = {
    enable = true;
    settings = {
      provider = "HE";
      password_file = "$CREDENTIALS_DIRECTORY/password";
      domains = [
        {
          domain_name = "ddns.gaof.net";
          sub_domains = ["cjia"];
        }
      ];
      ip_type = "IPv4";
      ip_interface = "ppp0";
      interval = 300;
      resolver = "8.8.8.8";
      use_proxy = false;
    };
    loadCredential = ["password:/run/agenix/cjia-godns-password"];
  };
  systemd.services.godns = {
    wants = ["pppd-isp.service"];
    after = ["pppd-isp.service"];
  };

  services.homebridge = {
    enable = true;
    settings.bridge = {
      name = "Homebridge";
      port = 51826;
      bind = [lanInterface];
      advertiser = "avahi";
    };
    uiSettings.port = 8581;
  };

  services.resolved.settings.Resolve = {
    DNS = [config.networking.homeRouter.serviceAddresses.ipv4];
    Domains = ["~."];
  };
}

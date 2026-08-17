{
  config,
  lib,
  ...
}: {
  imports = [
    ../../optional/nylon.nix
  ];

  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    cjia-godns-password.file = config.services.secrets.filesDir + "/nixos/cjia/godns-password.age";
  };

  services.fail2ban.enable = true;

  services.nylon = {
    enable = true;
    policyRouting.enable = true;
    exits.ppp = {
      label = 100;
      interface = "ppp0";
    };
  };
  systemd.services.nylon = {
    requires = ["pppd-isp.service"];
    after = ["pppd-isp.service"];
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
}

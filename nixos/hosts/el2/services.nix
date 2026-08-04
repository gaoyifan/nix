{...}: {
  imports = [../../optional/diverge.nix];

  services.openssh.settings.MaxStartups = 100;
  services.fail2ban.enable = true;
  services.diverge.enable = true;

  services.resolved.settings.Resolve = {
    DNS = [
      "1.1.1.1"
      "1.0.0.1"
    ];
    Domains = ["~."];
  };
  services.resolved.dnsDelegates = {
    cjia.Delegate = {
      DNS = ["100.65.1.254"];
      Domains = ["cjia.gaof.net"];
    };
    wgIplcEndpoint.Delegate = {
      DNS = [
        "223.5.5.5"
        "223.6.6.6"
      ];
      Domains = ["int.automesh.org"];
    };
  };
}

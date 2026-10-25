{pkgs, ...}: {
  imports = [
    (import ./guest-base.nix {
      name = "el2";
      user = "yifan";
    })
  ];
  networking = {
    hostName = "github-runner-el2";
    resolvconf.enable = false;
  };
  nix.settings = {
    http-connections = 64;
    max-substitution-jobs = 64;
    max-free = 6 * 1024 * 1024 * 1024;
  };
  systemd.tmpfiles.rules = ["d /var/lib/github-runner-work 0755 yifan users -"];
  services.github-runners.el2 = {
    url = "https://github.com/gaoyifan/nix";
    name = "el2-nspawn";
    extraLabels = ["el2" "nix"];
    replace = true;
    extraPackages = [pkgs.curl pkgs.jq pkgs.xz];
    serviceOverrides.ReadWritePaths = ["/home/yifan"];
  };
}

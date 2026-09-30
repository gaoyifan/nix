{pkgs, ...}: let
  cache = import ../../../../../nix-cache.nix;
in {
  boot.isContainer = true;
  networking = {
    hostName = "github-runner-el2";
    useDHCP = false;
    useHostResolvConf = false;
    resolvconf.enable = false;
    firewall.enable = false;
  };
  nix = {
    channel.enable = false;
    settings = {
      experimental-features = ["nix-command" "flakes"];
      trusted-users = ["yifan"];
      substituters = cache.extra-substituters ++ [cache.official-substituter];
      trusted-public-keys = cache.extra-trusted-public-keys ++ [cache.official-public-key];
      http-connections = 64;
      max-jobs = 8;
      max-substitution-jobs = 64;
      keep-env-derivations = true;
      min-free = 2 * 1024 * 1024 * 1024;
      max-free = 6 * 1024 * 1024 * 1024;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };
  users.users.yifan = {
    isNormalUser = true;
    uid = 1000;
    linger = true;
  };
  systemd.tmpfiles.rules = ["d /var/lib/github-runner-work 0755 yifan users -"];
  # A fully visible procfs mount lets Nix create procfs in its nested
  # user/PID namespaces while nspawn keeps the main /proc masked.
  systemd.mounts = [
    {
      what = "proc";
      where = "/run/nixproc";
      type = "proc";
      options = "nosuid,nodev,noexec";
    }
  ];
  systemd.services.nix-daemon = {
    requires = ["run-nixproc.mount"];
    after = ["run-nixproc.mount"];
  };
  services.github-runners.el2 = {
    enable = true;
    url = "https://github.com/gaoyifan/nix";
    name = "el2-nspawn";
    extraLabels = ["el2" "nix"];
    tokenFile = "/run/github-runner-token";
    tokenType = "registration";
    replace = true;
    user = "yifan";
    workDir = "/var/lib/github-runner-work";
    extraEnvironment = {
      HOME = "/home/yifan";
      XDG_RUNTIME_DIR = "/run/user/1000";
    };
    extraPackages = [pkgs.curl pkgs.jq pkgs.xz];
    serviceOverrides = {
      PrivateUsers = false;
      ProtectHome = false;
      ReadWritePaths = ["/home/yifan"];
      UMask = "0022";
    };
  };
  system.stateVersion = "26.05";
}

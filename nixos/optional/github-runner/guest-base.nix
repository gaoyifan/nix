{
  name,
  user,
}: {lib, ...}: let
  cache = import ../../../nix-cache.nix;
in {
  boot.isContainer = true;
  networking = {
    useDHCP = false;
    useHostResolvConf = false;
    firewall.enable = false;
  };
  nix = {
    channel.enable = false;
    settings = {
      experimental-features = ["nix-command" "flakes"];
      trusted-users = [user];
      substituters = cache.extra-substituters ++ [cache.official-substituter];
      trusted-public-keys = cache.extra-trusted-public-keys ++ [cache.official-public-key];
      max-jobs = lib.mkDefault 8;
      keep-env-derivations = true;
      keep-outputs = true;
      min-free = lib.mkDefault (2 * 1024 * 1024 * 1024);
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };
  users.users.${user} = {
    isNormalUser = true;
    uid = 1000;
    linger = true;
  };
  # A fully visible procfs lets Nix create its nested user/PID namespaces.
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
  services.github-runners.${name} = {
    enable = true;
    inherit user;
    tokenFile = "/run/github-runner-token";
    tokenType = "registration";
    workDir = "/var/lib/github-runner-work";
    extraEnvironment = {
      HOME = "/home/${user}";
      XDG_RUNTIME_DIR = "/run/user/1000";
    };
    serviceOverrides = {
      PrivateUsers = false;
      ProtectHome = false;
      UMask = "0022";
    };
  };
  system.stateVersion = "26.05";
}

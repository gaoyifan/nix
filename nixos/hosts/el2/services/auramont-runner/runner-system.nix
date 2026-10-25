{pkgs, ...}: let
  cache = import ../../../../../nix-cache.nix;
  ownershipImage = pkgs.dockerTools.buildLayeredImage {
    name = "auramont-ci-cleanup";
    tag = "1";
    contents = [pkgs.coreutils];
    config.Entrypoint = ["${pkgs.coreutils}/bin/chown" "--recursive" "--no-dereference" "1000" "/workspace"];
  };
  cleanup = pkgs.writeShellScript "auramont-ci-cleanup.sh" ''
    ${builtins.readFile ./cleanup.sh}
    docker load --input ${ownershipImage} >/dev/null
    docker run --rm --network none --read-only \
      --mount type=bind,src=/var/lib/github-runner-work,dst=/workspace auramont-ci-cleanup:1
  '';
  tools = with pkgs; [curl git gh jq gnused gnugrep gawk findutils util-linux xz zip unzip python3 rsync openssh nodejs_24 docker docker-compose];
in {
  boot.isContainer = true;
  networking = {
    hostName = "auramont-ci";
    useDHCP = false;
    useHostResolvConf = false;
    useNetworkd = true;
    nameservers = ["100.64.2.254"];
    firewall.enable = false;
  };
  systemd.network.networks."10-host0" = {
    matchConfig.Name = "host0";
    address = ["100.64.2.82/24"];
    routes = [{Gateway = "100.64.2.254";}];
  };
  nix = {
    channel.enable = false;
    settings = {
      experimental-features = ["nix-command" "flakes"];
      trusted-users = ["runner"];
      substituters = cache.extra-substituters ++ [cache.official-substituter];
      trusted-public-keys = cache.extra-trusted-public-keys ++ [cache.official-public-key];
      max-jobs = 8;
      keep-env-derivations = true;
      keep-outputs = true;
      min-free = 2 * 1024 * 1024 * 1024;
      max-free = 10 * 1024 * 1024 * 1024;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };
  virtualisation.docker.enable = true;
  # uv-managed Python is a generic Linux binary, as used by existing CI.
  programs.nix-ld.enable = true;
  environment.systemPackages = tools;
  users.users.runner = {
    isNormalUser = true;
    uid = 1000;
    linger = true;
    extraGroups = ["docker"];
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/github-runner-work 0755 runner users -"
    "d /var/lib/github-runner-toolcache 0755 runner users -"
  ];
  # Match the existing Nix runner's nested PID/user namespace support.
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
  services.github-runners.auramont = {
    enable = true;
    url = "https://github.com/cardio-angel/auramont-mono";
    name = "el2-auramont";
    extraLabels = ["el2" "auramont"];
    tokenFile = "/run/github-runner-token";
    tokenType = "registration";
    user = "runner";
    workDir = "/var/lib/github-runner-work";
    extraPackages = tools;
    extraEnvironment = {
      HOME = "/home/runner";
      TZ = "UTC";
      XDG_RUNTIME_DIR = "/run/user/1000";
      RUNNER_TOOL_CACHE = "/var/lib/github-runner-toolcache";
      ACTIONS_RUNNER_HOOK_JOB_STARTED = "${cleanup}";
      ACTIONS_RUNNER_HOOK_JOB_COMPLETED = "${cleanup}";
    };
    serviceOverrides = {
      PrivateUsers = false;
      ProtectHome = false;
      ReadWritePaths = ["/home/runner" "/var/lib/github-runner-toolcache"];
      UMask = "0022";
    };
  };
  systemd.services.github-runner-auramont = {
    requires = ["docker.service"];
    after = ["docker.service" "network-online.target"];
  };
  system.stateVersion = "26.05";
}

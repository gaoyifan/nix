{pkgs, ...}: let
  tools = (import ../../optional/github-runner/auramont-tools.nix {inherit pkgs;}) ++ [pkgs.nodejs_22];
  cleanup = pkgs.writeShellScript "auramont-ci-cleanup.sh" ''
    set -eu
    rm -rf "$HOME/.ssh"
  '';
in {
  imports = [
    (import ../../optional/github-runner/guest-base.nix {
      name = "auramont";
      user = "runner";
    })
  ];

  networking = {
    hostName = "auramont-ci";
    useNetworkd = true;
    nameservers = ["1.1.1.1" "1.0.0.1"];
  };
  systemd.network.networks."10-host0" = {
    matchConfig.Name = "host0";
    address = ["192.168.247.2/30"];
    routes = [{Gateway = "192.168.247.1";}];
  };
  nix.settings = {
    max-jobs = 1;
    cores = 3;
    min-free = 10 * 1024 * 1024 * 1024;
    max-free = 20 * 1024 * 1024 * 1024;
  };
  environment.systemPackages = tools;
  systemd.tmpfiles.rules = ["d /var/lib/github-runner-work 0755 runner users -"];
  services.github-runners.auramont = {
    url = "https://github.com/cardio-angel/auramont-mono";
    name = "oracle2-auramont";
    extraLabels = ["oracle2" "auramont"];
    extraPackages = tools;
    extraEnvironment = {
      TZ = "UTC";
      ACTIONS_RUNNER_HOOK_JOB_STARTED = "${cleanup}";
      ACTIONS_RUNNER_HOOK_JOB_COMPLETED = "${cleanup}";
    };
    serviceOverrides.ReadWritePaths = ["/home/runner"];
  };
}

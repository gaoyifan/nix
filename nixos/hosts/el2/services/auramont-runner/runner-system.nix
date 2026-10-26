{
  machine,
  address,
  runnerName,
}: {pkgs, ...}: let
  ownershipImage = pkgs.dockerTools.buildLayeredImage {
    name = "auramont-ci-cleanup";
    tag = "1";
    contents = [pkgs.coreutils];
    config.Entrypoint = ["${pkgs.coreutils}/bin/chown" "--recursive" "--no-dereference" "1000" "/workspace"];
  };
  cleanup =
    pkgs.writeShellScript "auramont-ci-cleanup.sh"
    (builtins.replaceStrings ["@ownershipImage@"] ["${ownershipImage}"] (builtins.readFile ./cleanup.sh));
  tools = with pkgs; [curl git gh jq gnused gnugrep gawk findutils util-linux xz zip unzip python3 rsync openssh nodejs_24 docker docker-compose];
in {
  imports = [
    (import ../github-runner/guest-base.nix {
      name = "auramont";
      user = "runner";
    })
  ];
  networking = {
    hostName = machine;
    useNetworkd = true;
    nameservers = ["100.64.2.254"];
  };
  systemd.network.networks."10-host0" = {
    matchConfig.Name = "host0";
    address = [address];
    routes = [{Gateway = "100.64.2.254";}];
  };
  nix.settings.max-free = 10 * 1024 * 1024 * 1024;
  virtualisation.docker.enable = true;
  # uv-managed Python is a generic Linux binary, as used by existing CI.
  programs.nix-ld.enable = true;
  environment.systemPackages = tools;
  users.users.runner.extraGroups = ["docker"];
  systemd.tmpfiles.rules = [
    "d /var/lib/github-runner-work 0755 runner users -"
    "d /var/lib/github-runner-toolcache 0755 runner users -"
  ];
  services.github-runners.auramont = {
    url = "https://github.com/cardio-angel/auramont-mono";
    name = runnerName;
    extraLabels = ["el2" "auramont"];
    extraPackages = tools;
    extraEnvironment = {
      TZ = "UTC";
      RUNNER_TOOL_CACHE = "/var/lib/github-runner-toolcache";
      ACTIONS_RUNNER_HOOK_JOB_STARTED = "${cleanup}";
      ACTIONS_RUNNER_HOOK_JOB_COMPLETED = "${cleanup}";
    };
    serviceOverrides.ReadWritePaths = ["/home/runner" "/var/lib/github-runner-toolcache"];
  };
  systemd.services.github-runner-auramont = {
    requires = ["docker.service"];
    after = ["docker.service" "network-online.target"];
  };
}

{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  root = "/pool1/services/github-runner/root";
  tokenFile = "/var/lib/github-runner-el2/token";
  runnerToplevel =
    (inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [./github-runner/runner-system.nix];
    }).config.system.build.toplevel;
in {
  # NixOS containers normally mount the host store and daemon. Seed a separate
  # root instead so workflow builds and garbage collection stay in the guest.
  systemd.services.github-runner-el2 = {
    description = "GitHub Actions runner in a persistent systemd-nspawn container";
    wantedBy = ["el2-services.target"];
    requires = ["zfs-unlock-mount.service"];
    after = ["zfs-unlock-mount.service" "network-online.target"];
    wants = ["network-online.target"];
    unitConfig.ConditionPathExists = tokenFile;
    path = [config.nix.package pkgs.coreutils];
    preStart = ''
      install -d -m 0755 ${root}
      nix copy --no-check-sigs --to 'local?root=${root}' ${runnerToplevel}
      install -d -m 0755 ${root}/nix/var/nix/profiles
      ln -sfn ${runnerToplevel} ${root}/nix/var/nix/profiles/system
      install -d -m 0755 ${root}/etc ${root}/usr
      if [[ ! -e ${root}/etc/os-release && ! -L ${root}/etc/os-release ]]; then
        touch ${root}/etc/os-release
      fi
    '';
    serviceConfig = {
      Type = "notify";
      NotifyAccess = "all";
      Delegate = true;
      KillMode = "mixed";
      Restart = "on-failure";
      RestartSec = "10s";
      TimeoutStartSec = "15min";
      TimeoutStopSec = "5min";
      MemoryHigh = "48G";
      MemoryMax = "64G";
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.systemd}/bin/systemd-nspawn"
        "--keep-unit --settings=no --machine=github-runner-el2"
        "--directory=${root} --notify-ready=yes --kill-signal=SIGRTMIN+3"
        "--resolv-conf=bind-host --link-journal=try-guest"
        "--bind-ro=${tokenFile}:/run/github-runner-token"
        "${runnerToplevel}/init"
      ];
    };
  };
}

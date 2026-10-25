{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  root = "/pool1/services/auramont-runner/root";
  tokenFile = "/var/lib/github-runner-auramont/token";
  guest =
    (inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [./auramont-runner/runner-system.nix];
    }).config.system.build.toplevel;
in {
  # Join the existing internal LAN through a private network namespace. Docker
  # bridges, routes and firewall rules then belong only to this container.
  networking.homeRouter.switch.ports.vb-auramont-ci.untagged = 642;

  systemd.services.github-runner-auramont = {
    description = "Auramont GitHub Actions runner in an isolated nspawn container";
    wantedBy = ["el2-services.target"];
    requires = ["zfs-unlock-mount.service"];
    after = ["zfs-unlock-mount.service" "network-online.target"];
    wants = ["network-online.target"];
    unitConfig.ConditionPathExists = tokenFile;
    path = [config.nix.package pkgs.coreutils];
    preStart = ''
      install -d -m 0755 ${root}
      nix copy --no-check-sigs --to 'local?root=${root}' ${guest}
      install -d -m 0755 ${root}/nix/var/nix/profiles ${root}/etc ${root}/usr
      ln -sfn ${guest} ${root}/nix/var/nix/profiles/system
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
      MemoryHigh = "24G";
      MemoryMax = "32G";
      CPUQuota = "1200%";
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.systemd}/bin/systemd-nspawn"
        "--keep-unit --settings=no --machine=auramont-ci"
        "--directory=${root} --notify-ready=yes --kill-signal=SIGRTMIN+3"
        "--network-bridge=br-core --resolv-conf=off --link-journal=try-guest"
        "--capability=CAP_NET_ADMIN"
        # runc installs cgroup-v2 device rules through BPF.
        "--system-call-filter=bpf"
        "--bind-ro=${tokenFile}:/run/github-runner-token"
        "${guest}/init"
      ];
    };
  };
}

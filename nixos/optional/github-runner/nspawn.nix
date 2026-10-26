{
  name,
  machine ? name,
  root,
  tokenFile,
  guestModule,
  nspawnArgs,
  wantedBy ? ["multi-user.target"],
  requires ? [],
}: {
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  runnerToplevel =
    (inputs.nixpkgs.lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [guestModule];
    }).config.system.build.toplevel;
in {
  # Keep workflow builds and garbage collection in an independent guest store.
  systemd.services.${name} = {
    inherit wantedBy requires;
    after = requires ++ ["network-online.target"];
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
      ExecStart = lib.concatStringsSep " " (
        [
          "${pkgs.systemd}/bin/systemd-nspawn"
          "--keep-unit --settings=no --machine=${machine}"
          "--directory=${root} --notify-ready=yes --kill-signal=SIGRTMIN+3"
        ]
        ++ nspawnArgs
        ++ [
          "--bind-ro=${tokenFile}:/run/github-runner-token"
          "${runnerToplevel}/init"
        ]
      );
    };
  };
}

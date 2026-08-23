{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.zfsUnlock;
  systemctl = lib.getExe' pkgs.systemd "systemctl";
  zfs = lib.getExe' pkgs.zfs "zfs";
in {
  options.programs.zfsUnlock = {
    datasets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Encrypted ZFS datasets unlocked by unlock-pool0.";
    };
  };

  config.environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "unlock-pool0";
      text = ''
        if (( EUID != 0 )); then
          echo "Run this command with sudo." >&2
          exit 1
        fi

        read -r -s -p "Passphrase for encrypted datasets: " passphrase
        echo
        trap 'unset passphrase' EXIT

        for dataset in ${lib.escapeShellArgs cfg.datasets}; do
          if [[ "$(${zfs} get -H -o value keystatus "$dataset")" == unavailable ]]; then
            printf '%s\n' "$passphrase" | ${zfs} load-key "$dataset"
          fi
        done

        unset passphrase
        trap - EXIT

        ${systemctl} --no-ask-password restart zfs-unlock-mount.service
      '';
    })
  ];

  config.systemd.services.zfs-unlock-mount = {
    description = "Mount manually unlocked ZFS datasets";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for dataset in ${lib.escapeShellArgs cfg.datasets}; do
        if [[ "$(${zfs} get -H -o value mounted "$dataset")" == no ]]; then
          ${zfs} mount "$dataset"
        fi
      done
    '';
  };
}

{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.znapzend;
  enabledFeatures = lib.attrNames (lib.filterAttrs (_: enabled: enabled) cfg.features);
in {
  imports = [../../../optional/znapzend-mail.nix];

  services.znapzend = {
    enable = true;
    logLevel = "warning";
    features = {
      sendRaw = true;
      zfsGetType = true;
    };
    zetup.icloud-photos = {
      dataset = "pool0/footage2";
      plan = "2w=>6h,3m=>1d,1y=>1m";
      presnap = "${pkgs.systemd}/bin/systemctl start icloud-photos-backup.service";
    };
    zetup.services = {
      dataset = "pool1/services";
      plan = "1d=>1h,2w=>1d,8w=>1w,1y=>1m";
      destinations."0" = {
        host = "root@nfs.ts.gaof.net";
        dataset = "pool0/el2/services";
        plan = "1d=>1h,2w=>1d,8w=>1w,1y=>1m";
      };
    };
    zetup.kingdee = {
      dataset = "pool1/incus/virtual-machines/kingdee.block";
      plan = "1hours=>10minutes,1days=>8hours,30days=>7days";
      destinations."0" = {
        host = "root@nfs.ts.gaof.net";
        dataset = "pool0/pve-backup/vm-200-disk-0";
        plan = "1hours=>10minutes,1days=>8hours,30days=>7days";
      };
    };
  };

  services.resolved.dnsDelegates.znapzendNfs.Delegate = {
    DNS = [
      "223.5.5.5"
      "119.29.29.29"
    ];
    Domains = ["nfs.ts.gaof.net"];
  };

  systemd.services.znapzend = {
    wantedBy = lib.mkForce ["el2-services.target"];
    after = [
      "zfs-import-pool1.service"
      "zfs-unlock-mount.service"
    ];
    requires = [
      "zfs-import-pool1.service"
      "zfs-unlock-mount.service"
    ];
    # Nixpkgs exposes no extraArgs for znapzend. Preserve its generated arguments
    # while preventing incomplete photo exports from producing a success snapshot.
    serviceConfig.ExecStart = lib.mkForce (lib.concatStringsSep " " ([
        "${pkgs.znapzend}/bin/znapzend"
        "--logto=${cfg.logTo}"
        "--loglevel=${cfg.logLevel}"
        "--skipOnPreSnapCmdFail"
      ]
      ++ lib.optional cfg.noDestroy "--nodestroy"
      ++ lib.optional cfg.autoCreation "--autoCreation"
      ++ lib.optional (cfg.mailErrorSummaryTo != "") "--mailErrorSummaryTo=${cfg.mailErrorSummaryTo}"
      ++ lib.optional (enabledFeatures != []) "--features=${lib.concatStringsSep "," enabledFeatures}"));
    preStart = lib.mkBefore ''
      zfs set org.znapzend:enabled=off pool0/backup pool0/footage
    '';
  };
}

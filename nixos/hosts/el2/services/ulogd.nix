{
  lib,
  pkgs,
  ...
}: let
  database = "/var/lib/ulogd/flows.sqlite";
  archiveDirectory = "/pool0/log";
  archivePython = pkgs.python3.withPackages (pythonPackages: [pythonPackages.pyarrow]);
  schema = pkgs.writeText "ulogd-flows.sql" ''
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS flows (
      flow_start_sec INTEGER,
      flow_start_usec INTEGER,
      flow_end_sec INTEGER,
      flow_end_usec INTEGER,
      oob_family INTEGER,
      orig_ip_saddr_str TEXT,
      orig_ip_daddr_str TEXT,
      orig_ip_protocol INTEGER,
      orig_l4_sport INTEGER,
      orig_l4_dport INTEGER,
      reply_ip_saddr_str TEXT,
      reply_ip_daddr_str TEXT,
      reply_ip_protocol INTEGER,
      reply_l4_sport INTEGER,
      reply_l4_dport INTEGER,
      orig_raw_pktlen INTEGER,
      orig_raw_pktcount INTEGER,
      reply_raw_pktlen INTEGER,
      reply_raw_pktcount INTEGER,
      icmp_type INTEGER,
      icmp_code INTEGER,
      icmpv6_type INTEGER,
      icmpv6_code INTEGER,
      ct_mark INTEGER,
      ct_event INTEGER
    );
    CREATE INDEX IF NOT EXISTS flows_end ON flows(flow_end_sec);
  '';
in {
  boot.kernelModules = ["nf_conntrack_netlink"];
  boot.kernel.sysctl = {
    "net.netfilter.nf_conntrack_acct" = 1;
    "net.netfilter.nf_conntrack_timestamp" = 1;
    "net.netfilter.nf_conntrack_events" = 1;
  };

  environment.systemPackages = [pkgs.conntrack-tools];

  services.ulogd = {
    enable = true;
    settings = {
      global = {
        logfile = "syslog";
        stack = ["ct1:NFCT,ip2str1:IP2STR,sqlite1:SQLITE3"];
      };
      ct1 = {
        # One row per DESTROY event. Kernel timestamps survive daemon restarts;
        # active connections remain available through `conntrack -L`.
        event_mask = 4;
        hash_enable = 0;
        netlink_socket_buffer_size = 16777216;
        netlink_socket_buffer_maxsize = 67108864;
      };
      sqlite1 = {
        db = database;
        table = "flows";
      };
    };
  };

  systemd.services.ulogd = {
    after = ["systemd-sysctl.service"];
    preStart = ''
      ${lib.getExe pkgs.sqlite} -bail ${database} < ${schema}
    '';
    serviceConfig = {
      UMask = "0077";
      StateDirectory = "ulogd";
      StateDirectoryMode = "0700";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  systemd.services.ulogd-archive = {
    description = "Archive completed ulogd days as zstd Parquet";
    startAt = "*-*-* 09:10:00";
    after = ["ulogd.service" "zfs-mount.service"];
    unitConfig.RequiresMountsFor = archiveDirectory;
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
    };
    script = ''
      ${archivePython}/bin/python3 ${./ulogd-archive.py} ${database} ${archiveDirectory}
    '';
  };
  systemd.timers.ulogd-archive.timerConfig.Persistent = true;
}

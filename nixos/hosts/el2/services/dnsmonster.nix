{pkgs, ...}: {
  systemd.services.dnsmonster = {
    description = "Record DNS traffic as JSON Lines";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = ''
        ${pkgs.dnsmonster}/bin/dnsmonster \
          --devname=any --useafpacket --noetherframe --nopromiscuous \
          --filter="port 53 or (ip and (ip[6:2] & 0x1fff != 0)) or (ip6 and ip6[6] == 44)" \
          --fileoutputtype=1 \
          --fileoutputpath=/var/log/dnsmonster \
          --fileoutputrotatecount=0
      '';
      DynamicUser = true;
      LogsDirectory = "dnsmonster";
      LogsDirectoryMode = "0700";
      UMask = "0077";
      AmbientCapabilities = ["CAP_NET_RAW"];
      CapabilityBoundingSet = ["CAP_NET_RAW"];
      KillSignal = "SIGINT";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # Keep archives by age rather than file count, including across downtime.
  systemd.services.dnsmonster-prune = {
    description = "Delete DNS archives older than 90 days";
    startAt = "daily";
    unitConfig.ConditionPathIsDirectory = "/var/log/dnsmonster";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''${pkgs.findutils}/bin/find /var/log/dnsmonster/ -maxdepth 1 -type f -name "dnsmonster.log.gz.*" -mmin +129600 -delete'';
    };
  };
  systemd.timers.dnsmonster-prune.timerConfig.Persistent = true;
}

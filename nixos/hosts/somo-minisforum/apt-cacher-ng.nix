# Caching HTTP proxy for Debian/Ubuntu package downloads from Incus guests.
{
  config,
  lib,
  pkgs,
  ...
}: let
  hermesNspawn = config.services.hermes-nspawn;
  inherit (hermesNspawn) allowedInterfaces aptProxyAddress;
  configDir = pkgs.writeTextDir "apt-cacher-ng/acng.conf" ''
    CacheDir: /var/cache/apt-cacher-ng
    LogDir: /var/log/apt-cacher-ng
    BindAddress: ${aptProxyAddress}
    ForeGround: 1
    ReportPage: acng-report.html

    # Let APT follow mirror load-balancer redirects so each response is cached
    # under its final mirror hostname instead of the original volatile URL.
    RedirMax: 0

    # Skip weekly expiration until another 500 MiB has been cached.
    ExStartTradeOff: 500m
  '';
in {
  systemd.services.apt-cacher-ng = {
    description = "Caching proxy for Debian package downloads";
    documentation = ["man:apt-cacher-ng(8)"];
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = ["network-online.target"];

    serviceConfig = {
      ExecStart = "${pkgs.apt-cacher-ng}/bin/apt-cacher-ng -c ${configDir}/apt-cacher-ng";
      Restart = "on-failure";
      RestartSec = "5s";

      DynamicUser = true;
      PrivateDevices = true;
      RuntimeDirectory = "apt-cacher-ng";
      CacheDirectory = "apt-cacher-ng";
      LogsDirectory = "apt-cacher-ng";
      UMask = "0027";

      RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
    };
  };

  systemd.services.apt-cacher-ng-expire = {
    description = "Expire stale apt-cacher-ng objects";
    requires = ["apt-cacher-ng.service"];
    after = ["apt-cacher-ng.service"];
    startAt = "weekly";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.apt-cacher-ng}/lib/apt-cacher-ng/acngtool maint -c ${configDir}/apt-cacher-ng";
      Environment = "ACNGIP=${aptProxyAddress}";
      DynamicUser = true;
      PrivateDevices = true;
      RestrictAddressFamilies = ["AF_INET" "AF_UNIX"];
    };
  };

  # home-router.nix disables the conventional NixOS firewall, so restrict the
  # proxy at the nftables input hook. In particular, do not expose it through
  # the WAN or Tailscale even if those peers route a LAN address via this host.
  networking.nftables.tables.apt-cacher-ng = {
    family = "inet";
    content = ''
      chain input {
        type filter hook input priority filter;
        iifname { ${lib.concatMapStringsSep ", " (interface: ''"${interface}"'') allowedInterfaces} } tcp dport 3142 accept
        tcp dport 3142 reject with tcp reset
      }
    '';
  };
}

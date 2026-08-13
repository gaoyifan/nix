{
  config,
  lib,
  pkgs,
  ...
}: let
  pppIpUp = pkgs.writeShellScript "cjia-ppp-ip-up" ''
    ${lib.getExe' pkgs.systemd "systemctl"} try-restart nylon.service
  '';
in {
  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    cjia-ppp-peer.file = config.services.secrets.filesDir + "/nixos/cjia/ppp-peer.age";
    cjia-ppp-pap-secrets.file = config.services.secrets.filesDir + "/nixos/cjia/pap-secrets.age";
  };

  environment.etc = lib.mkIf config.services.secrets.hasRealFiles {
    "ppp/pap-secrets".source = config.age.secrets.cjia-ppp-pap-secrets.path;
  };

  services.pppd = {
    enable = true;
    peers.isp.config = ''
      file /run/agenix/cjia-ppp-peer
      noipdefault
      defaultroute
      replacedefaultroute
      hide-password
      lcp-echo-interval 30
      lcp-echo-failure 4
      noauth
      persist
      maxfail 0
      holdoff 20
      plugin pppoe.so
      nic-end0
      ip-up-script ${pppIpUp}
      +ipv6
    '';
  };

  systemd.network.networks."09-pppoe-carrier" = {
    matchConfig.Name = "end0";
    address = ["192.168.125.254/24"];
    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
      LinkLocalAddressing = false;
    };
    linkConfig.RequiredForOnline = "carrier";
  };
}

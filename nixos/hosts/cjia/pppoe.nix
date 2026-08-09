{
  config,
  lib,
  ...
}: {
  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    cjia-ppp-peer.file = config.services.secrets.filesDir + "/nixos/cjia/ppp-peer.age";
    cjia-ppp-chap-secrets.file = config.services.secrets.filesDir + "/nixos/cjia/chap-secrets.age";
    cjia-ppp-pap-secrets.file = config.services.secrets.filesDir + "/nixos/cjia/pap-secrets.age";
  };

  environment.etc = lib.mkIf config.services.secrets.hasRealFiles {
    "ppp/chap-secrets".source = config.age.secrets.cjia-ppp-chap-secrets.path;
    "ppp/pap-secrets".source = config.age.secrets.cjia-ppp-pap-secrets.path;
  };

  services.pppd = {
    enable = true;
    peers.isp.config = "file /run/agenix/cjia-ppp-peer";
  };

  systemd.network.networks."09-pppoe-carrier" = {
    matchConfig.Name = "enp1s0";
    address = ["192.168.125.254/24"];
    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
      LinkLocalAddressing = false;
    };
    linkConfig.RequiredForOnline = "carrier";
  };
}

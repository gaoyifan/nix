{
  config,
  lib,
  pkgs,
  utils,
  ...
}: let
  pppIpUp = pkgs.writeShellScript "cjia-ppp-ip-up" ''
    ${lib.getExe' pkgs.systemd "systemctl"} restart nylon.service
  '';
  carrier = "br-core.650";
  carrierDevice = "sys-subsystem-net-devices-${utils.escapeSystemdPath carrier}.device";
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
      nic-${carrier}
      ip-up-script ${pppIpUp}
      +ipv6
    '';
  };

  systemd.services.pppd-isp = {
    requires = [carrierDevice];
    after = [carrierDevice];
  };

  networking.homeRouter.switch.ports.lan1.tagged = [650];

  systemd.network.netdevs."25-vlan650" = {
    netdevConfig = {
      Kind = "vlan";
      Name = carrier;
    };
    vlanConfig.Id = 650;
  };

  systemd.network.networks."40-br-core" = {
    vlan = [carrier];
    bridgeVLANs = [{VLAN = 650;}];
  };

  systemd.network.networks."09-pppoe-carrier" = {
    matchConfig.Name = carrier;
    address = ["192.168.125.254/24"];
    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
      LinkLocalAddressing = false;
    };
    linkConfig.RequiredForOnline = "no";
  };

  systemd.network.networks."09-unused-wan" = {
    matchConfig.Name = "wan0";
    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
      LinkLocalAddressing = false;
      KeepConfiguration = false;
    };
    linkConfig.RequiredForOnline = "no";
  };
}

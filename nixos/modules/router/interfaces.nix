# Network interface configuration using systemd-networkd
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.router;
in {
  systemd.network.enable = true;
  networking.useNetworkd = true;
  networking.useDHCP = false;
  networking.networkmanager.enable = false;

  # LAN Interface
  systemd.network.networks."10-lan" = {
    matchConfig.Name = cfg.lan.ifname;
    address = ["${cfg.lan.address}/${toString cfg.lan.prefixLength}"];
    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
    };
    linkConfig = {
      RequiredForOnline = "no";
      ActivationPolicy = "always-up";
    };
  };

  # WAN Interface (carrier for PPPoE, optional management IP)
  systemd.network.networks."20-wan" = {
    matchConfig.Name = cfg.wan.ifname;
    address = lib.optional (cfg.wan.managementAddress != null) cfg.wan.managementAddress;
    gateway = lib.optional (cfg.wan.managementGateway != null) cfg.wan.managementGateway;
    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
    };
    linkConfig = {
      RequiredForOnline = "no";
      ActivationPolicy = "always-up";
    };
  };

  # PPP Interface (created dynamically by pppd)
  systemd.network.networks."30-ppp" = {
    matchConfig.Name = cfg.pppoe.ifname;
    networkConfig.DHCP = "no";
    linkConfig.RequiredForOnline = "no";
  };

  # Don't block boot waiting for network
  systemd.services."systemd-networkd-wait-online".enable = lib.mkForce false;
}

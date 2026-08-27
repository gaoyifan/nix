# somo-gw - public gateway for SOMO services.
{
  config,
  lib,
  pkgs,
  ...
}: let
  filesDir = config.services.secrets.filesDir;
  hermesNspawn = import (filesDir + "/nixos/somo-minisforum/hermes-nspawn.nix");
  caddySecrets = import (filesDir + "/nixos/somo-gw/caddy.nix") {inherit hermesNspawn;};
in {
  imports = [
    ../../optional/edge-firewall.nix
    ../../optional/qemu-guest.nix
    ../../optional/tailscale-gnet-vm-exit.nix
    ./disk-config.nix
  ];

  networking.hostName = "somo-gw";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi = {
    canTouchEfiVariables = true;
    efiSysMountPoint = "/boot";
  };
  boot.kernelPackages = pkgs.linuxPackages_6_12;
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty0"
  ];
  fileSystems."/".device = lib.mkForce "/dev/disk/by-label/nixos-root";

  # Alibaba Cloud x86_64 VM with a small memory footprint. Keep rebuilds and
  # occasional Caddy/Tailscale spikes from exhausting RAM after installation.
  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };

  environment.systemPackages = with pkgs; [
    htop
  ];

  services.caddy = {
    enable = true;
    openFirewall = false;
    virtualHosts = caddySecrets.virtualHosts or {};
  };

  networking.edgeFirewall = {
    enable = true;
    extraPublicTcpPorts = [
      "80"
      "443"
    ];
    extraPublicUdpPorts = ["443"];
  };

  services.resolved = {
    enable = true;
    dnsDelegates = caddySecrets.dnsDelegates or {};
  };

  systemd.services.caddy = {
    wants = ["network-online.target" "systemd-resolved.service" "tailscaled.service"];
    after = ["network-online.target" "systemd-resolved.service" "tailscaled.service"];
    serviceConfig.Environment = [
      "XDG_DATA_HOME=/var/lib"
      "XDG_CONFIG_HOME=/var/lib/caddy/config"
    ];
  };

  system.stateVersion = "26.05";
}

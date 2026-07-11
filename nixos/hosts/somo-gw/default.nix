# somo-gw - public gateway for SOMO services.
{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}: let
  caddySecrets = config.services.secrets.nixos."somo-gw".caddy;
  publicInterface = "ens*";
in {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk-config.nix
  ];

  networking.hostName = "somo-gw";
  networking.useDHCP = lib.mkDefault true;

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
  boot.initrd.availableKernelModules = [
    "virtio_blk"
    "virtio_net"
    "virtio_pci"
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

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";
    openFirewall = false;
    extraSetFlags = [
      "--accept-dns=false"
      "--accept-routes"
      "--advertise-exit-node"
      "--netfilter-mode=off"
    ];
  };

  services.caddy = {
    enable = true;
    openFirewall = false;
    virtualHosts = caddySecrets.virtualHosts or {};
  };

  networking.firewall.enable = false;
  networking.nftables = {
    enable = true;
    tables.public-input = {
      family = "inet";
      content = ''
        chain input {
          type filter hook input priority filter; policy accept;
          iifname != "${publicInterface}" return

          # Existing connections and local diagnostics.
          ct state established,related accept
          iifname "lo" accept
          ip protocol icmp accept
          ip6 nexthdr icmpv6 accept

          # DHCP client renewals from the cloud network.
          udp sport 67 udp dport 68 accept
          udp sport 547 udp dport 546 accept

          # Public SSH management and Caddy HTTP/HTTPS.
          tcp dport { 22, 80, 443 } accept

          # Tailscale WireGuard and Caddy HTTP/3.
          udp dport { 41641, 443 } accept

          # tsshd UDP roaming sessions.
          udp dport 61001-61999 accept

          counter drop
        }
      '';
    };
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

  # nixos-anywhere restores migrated Caddy and Tailscale state as root-owned
  # files. Normalize ownership before the services start.
  systemd.tmpfiles.rules = [
    "Z /var/lib/caddy 0750 caddy caddy -"
    "Z /var/lib/tailscale 0700 root root -"
  ];

  system.stateVersion = "26.05";
}

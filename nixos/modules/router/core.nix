# Core router configuration
{
  config,
  lib,
  pkgs,
  ...
}: {
  nix.settings.experimental-features = ["nix-command" "flakes"];

  environment.systemPackages = with pkgs; [
    nftables
    iproute2
    wireguard-tools
    tcpdump
    ethtool
    bind.dnsutils
  ];

  # Disable NixOS firewall/NAT - we use nftables directly
  networking.firewall.enable = false;
  networking.nat.enable = false;

  # Use AdGuard Home for local DNS
  networking.nameservers = ["127.0.0.1"];
  services.resolved.enable = false;

  # SSH server
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # Kernel settings for routing
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    # Loose mode for policy routing
    "net.ipv4.conf.all.rp_filter" = 2;
    "net.ipv4.conf.default.rp_filter" = 2;
    # Security hardening
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    "net.ipv4.tcp_syncookies" = 1;
    # Connection tracking for router workload
    "net.netfilter.nf_conntrack_max" = 262144;
  };
}

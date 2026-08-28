{
  config,
  lib,
  ...
}: {
  imports = [
    ../../optional/edge-firewall.nix
    ../../optional/el2-derp-bootstrap.nix
    ../../optional/nylon-public-exit.nix
    ../../optional/qemu-guest.nix
    ../../optional/tailscale-gnet-vm-exit.nix
    ./disk-config.nix
    ./networking.nix
  ];

  age.secrets = lib.mkIf config.services.secrets.hasRealFiles {
    misc1-sh-wg-cloudflare-private-key = {
      file = config.services.secrets.filesDir + "/nixos/misc1-sh/wg-cloudflare-private-key.age";
      path = "/var/lib/wireguard/wg-cloudflare-private-key";
    };
  };

  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200n8"
  ];

  networking.edgeFirewall.enable = true;

  services.nylon = {
    cloudflareWarp = {
      enable = true;
      label = 102;
      ipv6Address = "2606:4700:110:8eab:cfbe:2c01:5062:8c3c";
      reserved = "0x3e781e";
    };
    exits.shanghai = {
      label = 101;
      interface = "eth1";
      gateway4 = "61.172.164.1";
    };
  };

  system.stateVersion = "26.05";
}

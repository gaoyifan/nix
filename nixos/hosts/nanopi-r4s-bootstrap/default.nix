{
  modulesPath,
  pkgs,
  ...
}: let
  inherit (import ../../common/ssh-keys.nix) sshKeys;
in {
  imports = [
    (modulesPath + "/profiles/minimal.nix")
    ../../optional/nanopi-r4s.nix
  ];

  networking = {
    hostName = "nanopi-r4s-bootstrap";
    useDHCP = false;
    useNetworkd = true;
  };

  systemd.network = {
    enable = true;
    wait-online.enable = false;
    networks = {
      "10-end0" = {
        matchConfig.Name = "end0";
        address = ["192.0.2.254/24"];
        networkConfig = {
          DHCP = "no";
          IPv6AcceptRA = false;
          LinkLocalAddressing = false;
        };
        linkConfig.RequiredForOnline = "no";
      };

      "10-enp1s0" = {
        matchConfig.Name = "enp1s0";
        address = ["198.51.100.254/24"];
        networkConfig = {
          DHCP = "no";
          IPv6AcceptRA = false;
          LinkLocalAddressing = false;
        };
        linkConfig.RequiredForOnline = "no";
      };
    };
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  users = {
    mutableUsers = false;
    users.root = {
      hashedPassword = "!";
      openssh.authorizedKeys.keys = sshKeys;
    };
  };

  environment.systemPackages = with pkgs; [
    btrfs-progs
    ethtool
    iproute2
    tcpdump
  ];

  system.stateVersion = "26.05";
}

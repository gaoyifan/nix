{
  modulesPath,
  pkgs,
  ...
}: let
  inherit (import ../../common/ssh-keys.nix) sshKeys;
in {
  imports = [
    (modulesPath + "/profiles/minimal.nix")
    ../../optional/nanopi-r5c.nix
  ];

  networking = {
    hostName = "nanopi-r5c-bootstrap";
    useDHCP = false;
    useNetworkd = true;
  };

  systemd.network = {
    enable = true;
    wait-online.enable = false;
    networks = {
      "10-wan0" = {
        matchConfig.Name = "wan0";
        networkConfig = {
          DHCP = "ipv4";
          IPv6AcceptRA = false;
          LinkLocalAddressing = false;
        };
        linkConfig.RequiredForOnline = "no";
      };
      "10-lan1" = {
        matchConfig.Name = "lan1";
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
      hashedPassword = "";
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

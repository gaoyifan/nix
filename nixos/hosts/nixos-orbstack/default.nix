{
  config,
  lib,
  modulesPath,
  username,
  ...
}: {
  imports = [
    "${modulesPath}/virtualisation/lxc-container.nix"
  ];

  networking = {
    hostName = "nixos-orbstack";
    firewall.enable = false;
    resolvconf.enable = false;
    useDHCP = false;
    useHostResolvConf = false;
    useNetworkd = true;
  };

  systemd.network = {
    networks."50-eth0" = {
      matchConfig.Name = "eth0";
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = true;
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };

  users = {
    groups.orbstack.gid = 67278;
    users = {
      root.initialHashedPassword = lib.mkForce null;
      ${username} = {
        uid = 501;
        isNormalUser = lib.mkForce false;
        isSystemUser = true;
        group = "users";
        createHome = true;
        home = "/home/${username}";
        homeMode = "700";
        extraGroups = [
          "orbstack"
          "audio"
        ];
      };
    };
  };

  # OrbStack guest integration. Keep this aligned with the generated
  # /etc/nixos/orbstack.nix after OrbStack upgrades.
  environment = {
    shellInit = ''
      . /opt/orbstack-guest/etc/profile-early
      . /opt/orbstack-guest/etc/profile-late
    '';
    etc."resolv.conf".source = "/opt/orbstack-guest/etc/resolv.conf";
  };

  documentation = {
    man.enable = true;
    doc.enable = true;
    info.enable = true;
  };

  services = {
    openssh.hostKeys = [
      {
        type = "rsa";
        bits = 3072;
        path = "/etc/ssh/ssh_host_rsa_key";
      }
      {
        type = "ecdsa";
        bits = 256;
        path = "/etc/ssh/ssh_host_ecdsa_key";
      }
      {
        type = "ed25519";
        path = "/etc/ssh/ssh_host_ed25519_key";
      }
    ];
    resolved.enable = false;
    tailscale.gnetMode = "client";
  };

  systemd.services = {
    systemd-oomd.serviceConfig.WatchdogSec = 0;
    systemd-userdbd.serviceConfig.WatchdogSec = 0;
    systemd-udevd.serviceConfig.WatchdogSec = 0;
    systemd-timesyncd.serviceConfig.WatchdogSec = 0;
    systemd-timedated.serviceConfig.WatchdogSec = 0;
    systemd-portabled.serviceConfig.WatchdogSec = 0;
    "systemd-nspawn@".serviceConfig.WatchdogSec = 0;
    systemd-machined.serviceConfig.WatchdogSec = 0;
    systemd-localed.serviceConfig.WatchdogSec = 0;
    systemd-logind.serviceConfig.WatchdogSec = 0;
    "systemd-journald@".serviceConfig.WatchdogSec = 0;
    systemd-journald.serviceConfig.WatchdogSec = 0;
    systemd-journal-remote.serviceConfig.WatchdogSec = 0;
    systemd-journal-upload.serviceConfig.WatchdogSec = 0;
    systemd-importd.serviceConfig.WatchdogSec = 0;
    systemd-hostnamed.serviceConfig.WatchdogSec = 0;
    systemd-homed.serviceConfig.WatchdogSec = 0;
    systemd-networkd.serviceConfig.WatchdogSec = lib.mkIf config.systemd.network.enable 0;
  };

  programs.ssh.extraConfig = ''
    Include /opt/orbstack-guest/etc/ssh_config
  '';

  nix.settings.extra-platforms = [
    "x86_64-linux"
    "i686-linux"
  ];

  # OrbStack development root CAs from the generated 26.05 machine config.
  security.pki.certificates = [
    ''
      -----BEGIN CERTIFICATE-----
      MIICDjCCAbOgAwIBAgIRAKjpKSX88D8B7jFU3kyNMF4wCgYIKoZIzj0EAwIwZjEd
      MBsGA1UEChMUT3JiU3RhY2sgRGV2ZWxvcG1lbnQxHjAcBgNVBAsMFUNvbnRhaW5l
      cnMgJiBTZXJ2aWNlczElMCMGA1UEAxMcT3JiU3RhY2sgRGV2ZWxvcG1lbnQgUm9v
      dCBDQTAeFw0yNTAyMDkxOTMyNDFaFw0zNTAyMDkxOTMyNDFaMGYxHTAbBgNVBAoT
      FE9yYlN0YWNrIERldmVsb3BtZW50MR4wHAYDVQQLDBVDb250YWluZXJzICYgU2Vy
      dmljZXMxJTAjBgNVBAMTHE9yYlN0YWNrIERldmVsb3BtZW50IFJvb3QgQ0EwWTAT
      BgcqhkjOPQIBBggqhkjOPQMBBwNCAAQ4MqcRMAHqIjmyc9rmpN5RXtTj8Db7+SMV
      Voin1shwAUmesqS7QMUOlwOmpUveU7N9sWt95Y86tweivYReHxcqo0IwQDAOBgNV
      HQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUjqOgKd/a+v2G
      kZlig+t0AVWYsoAwCgYIKoZIzj0EAwIDSQAwRgIhANJ6VgOQMKJCDjcAGL7UA/FU
      xHz0HTO7hiioL7SommUfAiEAmVjU7w6Dcy479SdrI4HlVmmvGf59Dh524UJ3V3Bb
      5Fk=
      -----END CERTIFICATE-----

      -----BEGIN CERTIFICATE-----
      MIICDDCCAbKgAwIBAgIQTACPDn8oPBrxaLqy0gCl/zAKBggqhkjOPQQDAjBmMR0w
      GwYDVQQKExRPcmJTdGFjayBEZXZlbG9wbWVudDEeMBwGA1UECwwVQ29udGFpbmVy
      cyAmIFNlcnZpY2VzMSUwIwYDVQQDExxPcmJTdGFjayBEZXZlbG9wbWVudCBSb290
      IENBMB4XDTI2MDYxNDE1MDkxOFoXDTM2MDYxNDE1MDkxOFowZjEdMBsGA1UEChMU
      T3JiU3RhY2sgRGV2ZWxvcG1lbnQxHjAcBgNVBAsMFUNvbnRhaW5lcnMgJiBTZXJ2
      aWNlczElMCMGA1UEAxMcT3JiU3RhY2sgRGV2ZWxvcG1lbnQgUm9vdCBDQTBZMBMG
      ByqGSM49AgEGCCqGSM49AwEHA0IABBMD3CIo98ca5/7/VbFLnxyrohhWeb/xopzU
      SExCDXRlJso3IXA2h8Dx3A7PhL5SRB1n+/mbhn24yj5ZRJyPkTujQjBAMA4GA1Ud
      DwEB/wQEAwIBBjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBRqv2VjhAIF/6lv
      VqKPk6F9h4vlIjAKBggqhkjOPQQDAgNIADBFAiEA4UIqkwG8vU4H9bIBFrpydyWf
      5XOGHl1ch87o22CHSlECIHZ9dR3p+tWetk0loUHz5jQjNRq74DsL+KCAhmxWwssj
      -----END CERTIFICATE-----
    ''
  ];

  system.stateVersion = "26.05";
}

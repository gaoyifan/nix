{pkgs}: let
  inherit
    (import (pkgs.path + "/nixos/tests/ssh-keys.nix") pkgs)
    snakeOilEd25519PrivateKey
    snakeOilEd25519PublicKey
    ;
  oobAddress = "192.168.1.200";
  changedOobAddress = "192.168.1.201";
  recoveredOobAddress = "192.168.1.202";
  sshOptions = "-i /etc/oob-test-key -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null";
in {
  name = "oob-ssh";

  nodes = {
    server = {
      imports = [../optional/oob-ssh.nix];

      virtualisation.vlans = [1];
      environment.systemPackages = [pkgs.nftables];
      networking.interfaces.eth1.ipv4.addresses = [
        {
          address = "192.168.1.10";
          prefixLength = 24;
        }
      ];

      services.oobSsh = {
        enable = true;
        parentInterface = "eth1";
        address = "${oobAddress}/24";
      };
      services.openssh = {
        enable = true;
        openFirewall = true;
        settings.PermitRootLogin = "prohibit-password";
      };

      users.users.root.openssh.authorizedKeys.keys = [snakeOilEd25519PublicKey];

      specialisation.changed.configuration.services.oobSsh.address =
        pkgs.lib.mkForce "${changedOobAddress}/24";
    };

    client = {
      virtualisation.vlans = [1];
      networking.interfaces.eth1.ipv4.addresses = [
        {
          address = "192.168.1.100";
          prefixLength = 24;
        }
      ];
      environment.systemPackages = [pkgs.openssh];
      environment.etc.oob-test-key = {
        source = snakeOilEd25519PrivateKey;
        mode = "0400";
      };
    };

    recovery = {
      imports = [../optional/oob-ssh.nix];

      virtualisation.vlans = [1];
      services.oobSsh = {
        enable = true;
        parentInterface = "eth1";
        address = "invalid";
      };
      users.users.root.openssh.authorizedKeys.keys = [snakeOilEd25519PublicKey];

      specialisation.repaired.configuration.services.oobSsh.address =
        pkgs.lib.mkForce "${recoveredOobAddress}/24";
    };

    derived = {
      imports = [../optional/oob-ssh.nix];

      virtualisation.vlans = [1];
      networking.vlans.oob-parent = {
        id = 100;
        interface = "eth1";
      };
      services.oobSsh = {
        enable = true;
        parentInterface = "oob-parent";
        address = "192.168.1.203/24";
      };
      systemd.services.oob-ssh.wantedBy = pkgs.lib.mkForce [];
    };
  };

  testScript = ''
    client.start()
    derived.start()
    recovery.start()
    server.start()

    with subtest("OOB rejects a derived parent interface"):
        derived.fail("systemctl start oob-ssh.service")

    with subtest("a failed setup can recover after configuration is repaired"):
        recovery.fail("systemctl restart oob-netns.service oob-ssh.service")
        recovery.succeed(
            "/run/current-system/specialisation/repaired/bin/switch-to-configuration switch"
        )
        recovery.succeed("systemctl restart oob-netns.service oob-ssh.service")
        client.wait_until_succeeds(
            "ssh ${sshOptions} root@${recoveredOobAddress} true",
            timeout=10,
        )

    with subtest("OOB SSH is isolated from the host firewall"):
        client.wait_until_succeeds("ssh ${sshOptions} root@192.168.1.10 true", timeout=10)
        client.wait_until_succeeds("ssh ${sshOptions} root@${oobAddress} true", timeout=10)
        server.succeed("nft add table inet disaster")
        server.succeed(
            "nft 'add chain inet disaster input "
            "{ type filter hook input priority -300; policy drop; }'"
        )
        client.fail("ssh ${sshOptions} root@192.168.1.10 true")
        client.succeed("ssh ${sshOptions} root@${oobAddress} true")
        server.succeed("nft delete table inet disaster")

    with subtest("switch keeps established and fresh OOB sessions alive"):
        client.succeed(
            "systemd-run --unit=oob-long-session -- "
            "ssh ${sshOptions} root@${oobAddress} sleep 300"
        )
        client.wait_until_succeeds(
            "ss -tn state established dst ${oobAddress}:22 | grep -q ${oobAddress}:22",
            timeout=10,
        )
        server.succeed(
            "/run/current-system/specialisation/changed/bin/switch-to-configuration switch"
        )
        client.succeed("systemctl is-active oob-long-session.service")
        client.succeed("ssh ${sshOptions} root@${oobAddress} true")
        client.fail("ssh ${sshOptions} root@${changedOobAddress} true")

    with subtest("planned restart applies the deferred OOB configuration"):
        server.succeed("systemctl restart oob-netns.service oob-ssh.service")
        client.wait_until_succeeds(
            "ssh ${sshOptions} root@${changedOobAddress} true",
            timeout=10,
        )
        client.fail("ssh ${sshOptions} root@${oobAddress} true")
        client.wait_until_fails("systemctl is-active oob-long-session.service", timeout=10)
  '';
}

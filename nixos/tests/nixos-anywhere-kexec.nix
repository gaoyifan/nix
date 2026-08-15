{
  inputs,
  kexecInstallerTarball,
  pkgs,
}: let
  sshKeyDir = "${inputs.nixos-images}/nix/kexec-installer/ssh-keys";
  installed =
    (pkgs.nixos [
      inputs.disko.nixosModules.disko
      (
        {modulesPath, ...}: {
          imports = [(modulesPath + "/profiles/minimal.nix")];

          boot.initrd.availableKernelModules = [
            "virtio_blk"
            "virtio_pci"
          ];
          boot.loader.grub.enable = true;

          disko.devices.disk.main = {
            device = "/dev/vda";
            type = "disk";
            content = {
              type = "gpt";
              partitions = {
                boot = {
                  size = "1M";
                  type = "EF02";
                };
                root = {
                  size = "100%";
                  content = {
                    type = "filesystem";
                    format = "btrfs";
                    mountpoint = "/";
                    mountOptions = ["compress=zstd:3"];
                  };
                };
              };
            };
          };

          networking.hostName = "installed";
          networking.useDHCP = false;
          networking.useNetworkd = true;
          systemd.network.networks."10-ethernet" = {
            matchConfig.Type = "ether";
            networkConfig.DHCP = "yes";
          };

          services.openssh = {
            enable = true;
            settings.PermitRootLogin = "prohibit-password";
          };
          users.users.root.openssh.authorizedKeys.keyFiles = ["${sshKeyDir}/id_ed25519.pub"];

          system.stateVersion = "26.05";
        }
      )
    ]).config;
in
  pkgs.testers.runNixOSTest {
    name = "nixos-anywhere-tiny-kexec";

    nodes.machine = {modulesPath, ...}: {
      imports = [(modulesPath + "/profiles/minimal.nix")];

      system.extraDependencies = [
        installed.system.build.diskoScript
        installed.system.build.toplevel
        kexecInstallerTarball
      ];
      virtualisation = {
        diskSize = 12 * 1024;
        forwardPorts = [
          {
            host.port = 2222;
            guest.port = 22;
          }
        ];
        memorySize = 1024;
        useBootLoader = true;
      };

      boot.loader.grub = {
        enable = true;
        devices = ["/dev/vda"];
      };
      boot.growPartition = true;
      networking.useDHCP = false;
      networking.useNetworkd = true;
      systemd.network.networks."10-ethernet" = {
        matchConfig.Type = "ether";
        networkConfig.DHCP = "yes";
      };
      services.openssh.enable = true;
      users.users.root.openssh.authorizedKeys.keyFiles = ["${sshKeyDir}/id_ed25519.pub"];

      system.stateVersion = "26.05";
    };

    testScript =
      /*
      python
      */
      ''
        import subprocess
        import time

        ssh_command = [
            "${pkgs.openssh}/bin/ssh",
            "-o", "ConnectTimeout=1",
            "-o", "ServerAliveInterval=1",
            "-o", "ServerAliveCountMax=1",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-i", "${sshKeyDir}/id_ed25519",
            "-p", "2222",
            "root@127.0.0.1",
            "--",
        ]
        def ssh(command, check=True):
            return subprocess.run(
                ssh_command + [command],
                check=check,
                text=True,
                stdout=subprocess.PIPE,
            )

        def wait_for_ssh(reachable):
            deadline = time.monotonic() + 180
            while (ssh("true", check=False).returncode == 0) != reachable:
                assert time.monotonic() < deadline, "timed out waiting for SSH state change"
                time.sleep(1)

        machine.start(allow_reboot=True)
        machine.wait_for_unit("multi-user.target")
        wait_for_ssh(True)

        machine.succeed("${pkgs.e2fsprogs}/bin/resize2fs /dev/vda1")
        machine.succeed(
            "tar -xf ${kexecInstallerTarball}/nixos-anywhere-tiny-kexec-x86_64-linux.tar.gz -C /root"
        )
        machine.succeed("/root/kexec/run")

        wait_for_ssh(False)
        wait_for_ssh(True)

        memory_kib = ssh(
            "while read key value unit; do "
            "[ \"$key\" = MemTotal: ] && echo \"$value\"; "
            "done </proc/meminfo; true"
        ).stdout
        assert int(memory_kib) < 1100000
        ssh("test -x /run/current-system/sw/bin/nix")
        ssh("test -x /run/current-system/sw/bin/nixos-install")
        ssh("test -x /run/current-system/sw/bin/rsync")
        ssh("systemctl is-active restore-network")

        ssh("mkdir -p /source && mount /dev/vda1 /source")
        ssh(
            "nix --extra-experimental-features nix-command copy "
            "--no-check-sigs "
            "--from 'local?root=/source' "
            "${installed.system.build.diskoScript} "
            "${installed.system.build.toplevel}"
        )
        ssh("umount /source")
        ssh("${installed.system.build.diskoScript}")
        assert ssh("findmnt -no FSTYPE /mnt").stdout.strip() == "btrfs"
        assert "compress=zstd:3" in ssh("findmnt -no OPTIONS /mnt").stdout

        ssh(
            "nix --extra-experimental-features nix-command copy "
            "--no-check-sigs --to 'local?root=/mnt' "
            "${installed.system.build.toplevel}"
        )
        ssh(
            "nixos-install --no-root-passwd --no-channel-copy "
            "--system ${installed.system.build.toplevel}"
        )
        ssh("reboot", check=False)

        wait_for_ssh(False)
        wait_for_ssh(True)
        assert ssh("hostnamectl --static").stdout.strip() == "installed"
        assert ssh("findmnt -no FSTYPE /").stdout.strip() == "btrfs"
        assert "compress=zstd:3" in ssh("findmnt -no OPTIONS /").stdout
        ssh("test -z \"$(systemctl --failed --no-legend)\"")

        machine.crash()
      '';
  }

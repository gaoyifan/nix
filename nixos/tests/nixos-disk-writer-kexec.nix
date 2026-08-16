{
  hostConfig,
  kexecInstallerTarball,
  mkNixosBootstrap,
  pkgs,
}: let
  inherit
    (import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs)
    snakeOilEd25519PrivateKey
    snakeOilEd25519PublicKey
    ;
  installedImage = mkNixosBootstrap {host = hostConfig;};
  rawImage = "${installedImage}/${hostConfig.config.networking.hostName}-bootstrap.raw";
  kexecArchive = "${kexecInstallerTarball}/nixos-disk-writer-kexec-x86_64-linux.tar.gz";
in
  pkgs.testers.runNixOSTest {
    name = "nixos-disk-writer-kexec";

    nodes.machine = {modulesPath, ...}: {
      imports = [(modulesPath + "/profiles/minimal.nix")];

      system.extraDependencies = [kexecInstallerTarball];
      virtualisation = {
        diskSize = 30 * 1024;
        forwardPorts = [
          {
            host.port = 2222;
            guest.port = 22;
          }
        ];
        memorySize = 1024;
        useBootLoader = true;
        useEFIBoot = true;
      };

      boot.loader.grub = {
        devices = [];
        efiInstallAsRemovable = true;
        efiSupport = true;
        enable = true;
      };
      boot.growPartition = true;
      networking = {
        hostName = "base-system";
        useDHCP = false;
        useNetworkd = true;
      };
      services.openssh.enable = true;
      systemd.network.networks."10-ethernet" = {
        matchConfig.Type = "ether";
        networkConfig.DHCP = "yes";
      };
      users.users.root.openssh.authorizedKeys.keys = [snakeOilEd25519PublicKey];

      system.stateVersion = "26.05";
    };

    testScript = ''
      import json
      import os
      import re
      import subprocess
      import tempfile
      import time

      ssh_options = [
          "-o", "ConnectTimeout=1",
          "-o", "LogLevel=ERROR",
          "-o", "ServerAliveInterval=1",
          "-o", "ServerAliveCountMax=1",
          "-o", "StrictHostKeyChecking=no",
          "-o", "UserKnownHostsFile=/dev/null",
          "-i", "${snakeOilEd25519PrivateKey}",
          "-p", "2222",
      ]
      ssh_command = [
          "${pkgs.openssh}/bin/ssh",
          *ssh_options,
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

      def wait_for_unit(unit):
          deadline = time.monotonic() + 180
          while ssh(f"systemctl is-active {unit}", check=False).returncode != 0:
              assert time.monotonic() < deadline, f"timed out waiting for {unit}"
              time.sleep(1)

      machine.start(allow_reboot=True)
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("growpart.service")
      root_device = machine.succeed("findmnt -n -o SOURCE /").strip()
      machine.succeed(f"${pkgs.e2fsprogs}/bin/resize2fs {root_device}")
      wait_for_ssh(True)
      assert ssh("hostnamectl --static").stdout.strip() == "base-system"

      machine.succeed("${pkgs.gnutar}/bin/tar -xf ${kexecArchive} -C /root")
      machine.succeed("/root/kexec/run")

      wait_for_ssh(False)
      wait_for_ssh(True)
      ssh("test -e /etc/nixos-disk-writer-kexec")
      assert ssh("test -x /run/current-system/sw/bin/rsync").returncode == 0
      ssh("! findmnt -rn -o SOURCE | grep -q '^/dev/vda'")
      ssh("test -b /dev/disk/by-id/virtio-root")
      target_device = ssh("readlink -f /dev/disk/by-id/virtio-root").stdout.strip()

      memory_kib = ssh(
          "while read key value unit; do "
          "[ \"$key\" = MemTotal: ] && echo \"$value\"; "
          "done </proc/meminfo; true"
      ).stdout
      assert int(memory_kib) < 1100000

      rsync_rsh = " ".join(["${pkgs.openssh}/bin/ssh", *ssh_options])
      rsync_command = [
          "${pkgs.rsync}/bin/rsync",
          "--ignore-times",
          "--no-whole-file",
          "--write-devices",
          "--fsync",
          "--compress-choice=zstd",
          "--compress-level=3",
          "--info=progress2",
          "-e", rsync_rsh,
      ]
      with tempfile.NamedTemporaryFile() as partial_image:
          subprocess.run(
              [
                  "${pkgs.coreutils}/bin/dd",
                  "if=${rawImage}",
                  f"of={partial_image.name}",
                  "bs=1M",
                  "count=64",
                  "status=none",
              ],
              check=True,
          )
          subprocess.run(
              [*rsync_command, partial_image.name, f"root@127.0.0.1:{target_device}"],
              check=True,
          )

      resumed = subprocess.run(
          [
              *rsync_command,
              "--stats",
              "${rawImage}",
              f"root@127.0.0.1:{target_device}",
          ],
          check=True,
          stdout=subprocess.PIPE,
          text=True,
      )
      literal_data = re.search(r"Literal data:\s+([0-9,]+) bytes", resumed.stdout)
      assert literal_data, resumed.stdout
      assert int(literal_data.group(1).replace(",", "")) < os.path.getsize("${rawImage}")

      reboot_started = time.monotonic()
      ssh("reboot", check=False)
      wait_for_ssh(False)
      wait_for_ssh(True)
      wait_for_unit("multi-user.target")
      installed_boot_seconds = time.monotonic() - reboot_started
      print("Installed image boot seconds:", installed_boot_seconds)
      assert installed_boot_seconds < 30
      wait_for_unit("growpart.service")
      wait_for_unit("systemd-growfs-root.service")

      assert ssh("hostnamectl --static").stdout.strip() == "${hostConfig.config.networking.hostName}"
      assert ssh("findmnt -no FSTYPE /").stdout.strip() == "btrfs"
      assert "compress=zstd:3" in ssh("findmnt -no OPTIONS /").stdout
      ssh("test -d /sys/firmware/efi")

      partition_table = json.loads(ssh("sfdisk --json /dev/vda").stdout)["partitiontable"]
      assert partition_table["label"] == "gpt"
      root_partition = partition_table["partitions"][2]
      assert root_partition["start"] + root_partition["size"] >= partition_table["lastlba"] - 2048
      filesystem_size = int(ssh("df --block-size=1 --output=size / | tail -n 1").stdout)
      assert filesystem_size > 25 * 1000**3

      machine.crash()
    '';
  }

{
  disko,
  hostConfig,
  mkNixosBootstrap,
  nixpkgs,
  pkgs,
}: let
  inherit
    (import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs)
    snakeOilEd25519PrivateKey
    snakeOilEd25519PublicKey
    ;
  gptImage = mkNixosBootstrap {host = hostConfig;};
  gptRawImage = "${gptImage}/${hostConfig.config.networking.hostName}-bootstrap.raw";
  mbrSystemModule = {
    lib,
    modulesPath,
    ...
  }: {
    imports = [(modulesPath + "/profiles/minimal.nix")];

    boot = {
      initrd.availableKernelModules = ["virtio_blk" "virtio_pci"];
      loader.grub = {
        enable = true;
        device = "/dev/vda";
      };
    };
    environment.systemPackages = [pkgs.util-linux];
    fileSystems."/" = {
      device = lib.mkDefault "/dev/vda1";
      fsType = "ext4";
    };
    networking = {
      hostName = "bios-mbr";
      useDHCP = false;
      useNetworkd = true;
    };
    services.openssh.enable = true;
    system.stateVersion = "26.05";
    systemd.network.networks."99-test" = {
      matchConfig.Type = "ether";
      networkConfig.DHCP = "yes";
    };
    users.users.root.openssh.authorizedKeys.keys = [snakeOilEd25519PublicKey];
  };
  mbrDiskModule = {
    disko.devices.disk.system = {
      type = "disk";
      device = "/dev/vda";
      content = {
        type = "table";
        format = "msdos";
        partitions = [
          {
            name = "root";
            start = "1M";
            end = "100%";
            bootable = true;
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          }
        ];
      };
    };
  };
  mbrHost = nixpkgs.lib.nixosSystem {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [disko.nixosModules.disko mbrSystemModule mbrDiskModule];
  };
  mbrImage = mkNixosBootstrap {host = mbrHost;};
  mbrRawImage = "${mbrImage}/bios-mbr-bootstrap.img";
  gptNode = {
    lib,
    modulesPath,
    ...
  }: {
    imports = [(modulesPath + "/profiles/minimal.nix")];

    boot = {
      growPartition = true;
      initrd.availableKernelModules = [
        "virtio_blk"
        "virtio_pci"
      ];
      loader.grub = {
        enable = true;
        devices = [];
        efiInstallAsRemovable = true;
        efiSupport = true;
      };
      supportedFilesystems = ["btrfs" "vfat"];
    };

    fileSystems = {
      "/" = {
        autoResize = true;
        device = "/dev/disk/by-partlabel/disk-system-root";
        fsType = "btrfs";
        options = ["compress=zstd:3" "noatime"];
      };
      "/boot" = {
        device = "/dev/disk/by-partlabel/disk-system-ESP";
        fsType = "vfat";
        options = ["umask=0077"];
      };
    };

    system.stateVersion = "26.05";

    virtualisation = {
      directBoot.enable = false;
      diskImage = gptRawImage;
      diskSize = 30 * 1024;
      forwardPorts = [
        {
          guest.port = 22;
          host.port = 2222;
        }
      ];
      graphics = false;
      installBootLoader = false;
      memorySize = 1024;
      mountHostNixStore = false;
      vlans = [];
      useBootLoader = true;
      useEFIBoot = true;
    };
    virtualisation.fileSystems = lib.mkForce {};
  };
  mbrNode = {lib, ...}: {
    imports = [mbrSystemModule];

    virtualisation = {
      directBoot.enable = false;
      fileSystems = lib.mkForce {};
      forwardPorts = [
        {
          guest.port = 22;
          host.port = 2222;
        }
      ];
      graphics = false;
      memorySize = 1024;
      mountHostNixStore = false;
      useBootLoader = true;
      useEFIBoot = false;
      vlans = [];
    };
  };
in
  pkgs.testers.runNixOSTest {
    name = "low-memory-disk-image";

    nodes = {
      gpt = gptNode;
      mbr = mbrNode;
    };

    testScript = {nodes, ...}: ''
      import json
      import os
      import subprocess
      import tempfile
      import time

      gpt_raw_image = "${gptRawImage}"
      mbr_raw_image = "${mbrRawImage}"
      cp = "${pkgs.coreutils}/bin/cp"
      qemu_img = "${pkgs.qemu-utils}/bin/qemu-img"
      sfdisk = "${pkgs.util-linux}/bin/sfdisk"

      ssh_command = [
          "${pkgs.openssh}/bin/ssh",
          "-o", "ConnectTimeout=1",
          "-o", "LogLevel=ERROR",
          "-o", "ServerAliveInterval=1",
          "-o", "ServerAliveCountMax=1",
          "-o", "StrictHostKeyChecking=no",
          "-o", "UserKnownHostsFile=/dev/null",
          "-i", "${snakeOilEd25519PrivateKey}",
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

      def wait_for_unit(unit):
          deadline = time.monotonic() + 180
          while ssh(f"systemctl is-active {unit}", check=False).returncode != 0:
              assert time.monotonic() < deadline, f"timed out waiting for {unit}"
              time.sleep(1)

      def copy_image(raw_image, prefix):
          fd, path = tempfile.mkstemp(prefix=prefix, suffix=".raw")
          os.close(fd)
          subprocess.run([cp, "--reflink=auto", "--sparse=always", raw_image, path], check=True)
          return path

      def partition_table(path):
          return json.loads(subprocess.check_output([sfdisk, "--json", path], text=True))[
              "partitiontable"
          ]

      def partition(table, number):
          return table["partitions"][number - 1]

      def boot_image(machine, path):
          os.environ["NIX_DISK_IMAGE"] = path
          machine.start(allow_reboot=True)
          started = time.monotonic()
          wait_for_ssh(True)
          wait_for_unit("multi-user.target")
          return time.monotonic() - started

      gpt_image = copy_image(gpt_raw_image, "gpt-btrfs-bootstrap-")
      gpt_before = partition_table(gpt_image)
      print("GPT image partition table before resize:", json.dumps(gpt_before, sort_keys=True))
      assert gpt_before["label"] == "gpt"
      subprocess.run([qemu_img, "resize", "-f", "raw", gpt_image, "30G"], check=True)
      gpt_boot_seconds = boot_image(gpt, gpt_image)
      print("GPT image first boot seconds:", gpt_boot_seconds)
      assert gpt_boot_seconds < 30
      wait_for_unit("growpart.service")
      wait_for_unit("systemd-growfs-root.service")

      gpt_after = json.loads(ssh("sfdisk --json /dev/vda").stdout)["partitiontable"]
      print("GPT image partition table after first boot:", json.dumps(gpt_after, sort_keys=True))
      assert gpt_after["label"] == "gpt"
      ssh("test -d /sys/firmware/efi")
      root_before = partition(gpt_before, 3)
      root_after = partition(gpt_after, 3)
      assert root_after["start"] == root_before["start"]
      assert root_after["size"] > root_before["size"]
      assert root_after["start"] + root_after["size"] >= gpt_after["lastlba"] - 2048
      gpt_growpart_log = ssh("journalctl --boot --no-pager --unit growpart.service").stdout
      print("GPT image growpart journal:\n" + gpt_growpart_log)
      assert "CHANGED" in gpt_growpart_log
      assert ssh("findmnt --noheadings --output FSTYPE /").stdout.strip() == "btrfs"
      gpt_filesystem_size = int(ssh("df --block-size=1 --output=size / | tail -n 1").stdout)
      assert gpt_filesystem_size > 25 * 1000**3

      gpt_reboot_started = time.monotonic()
      gpt.reboot()
      wait_for_ssh(False)
      wait_for_ssh(True)
      wait_for_unit("multi-user.target")
      gpt_second_boot_seconds = time.monotonic() - gpt_reboot_started
      print("GPT image second boot seconds:", gpt_second_boot_seconds)
      assert gpt_second_boot_seconds < 30
      wait_for_unit("growpart.service")
      wait_for_unit("systemd-growfs-root.service")
      gpt_after_reboot = json.loads(ssh("sfdisk --json /dev/vda").stdout)["partitiontable"]
      assert gpt_after_reboot == gpt_after
      assert "NOCHANGE" in ssh("journalctl --boot --no-pager --unit growpart.service").stdout
      gpt_second_size = int(ssh("df --block-size=1 --output=size / | tail -n 1").stdout)
      assert gpt_second_size == gpt_filesystem_size
      ssh("test -d /sys/firmware/efi")
      gpt.crash()

      mbr_image = copy_image(mbr_raw_image, "bios-mbr-bootstrap-")
      mbr_before = partition_table(mbr_image)
      print("MBR image partition table before resize:", json.dumps(mbr_before, sort_keys=True))
      assert mbr_before["label"] == "dos"
      assert len(mbr_before["partitions"]) == 1
      subprocess.run([qemu_img, "resize", "-f", "raw", mbr_image, "8G"], check=True)
      mbr_boot_seconds = boot_image(mbr, mbr_image)
      print("BIOS/MBR image first boot seconds:", mbr_boot_seconds)
      wait_for_unit("growpart.service")
      wait_for_unit("systemd-growfs-root.service")
      ssh("test ! -d /sys/firmware/efi")

      mbr_after = json.loads(ssh("sfdisk --json /dev/vda").stdout)["partitiontable"]
      print("MBR image partition table after first boot:", json.dumps(mbr_after, sort_keys=True))
      assert mbr_after["label"] == "dos"
      mbr_root_before = partition(mbr_before, 1)
      mbr_root_after = partition(mbr_after, 1)
      assert mbr_root_after["start"] == mbr_root_before["start"]
      assert mbr_root_after["size"] > mbr_root_before["size"]
      mbr_disk_sectors = int(ssh("blockdev --getsz /dev/vda").stdout)
      assert mbr_root_after["start"] + mbr_root_after["size"] >= mbr_disk_sectors - 2048
      assert "CHANGED" in ssh("journalctl --boot --no-pager --unit growpart.service").stdout
      assert ssh("findmnt --noheadings --output FSTYPE /").stdout.strip() == "ext4"
      mbr_filesystem_size = int(ssh("df --block-size=1 --output=size / | tail -n 1").stdout)
      assert mbr_filesystem_size > 7 * 1000**3

      mbr.reboot()
      wait_for_ssh(False)
      wait_for_ssh(True)
      wait_for_unit("multi-user.target")
      wait_for_unit("growpart.service")
      wait_for_unit("systemd-growfs-root.service")
      mbr_after_reboot = json.loads(ssh("sfdisk --json /dev/vda").stdout)["partitiontable"]
      assert mbr_after_reboot == mbr_after
      assert "NOCHANGE" in ssh("journalctl --boot --no-pager --unit growpart.service").stdout
      mbr_second_size = int(ssh("df --block-size=1 --output=size / | tail -n 1").stdout)
      assert mbr_second_size == mbr_filesystem_size
      ssh("test ! -d /sys/firmware/efi")
      mbr.crash()
    '';
  }

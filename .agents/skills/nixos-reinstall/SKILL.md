---
name: nixos-reinstall
description: Reinstall a remote Linux host as NixOS through SSH. Use for destructive reprovisioning with either a resumable raw disko image written from the repository's low-memory kexec system or upstream nixos-anywhere on hosts with enough memory, including target inventory, disk selection, runtime secrets, and post-boot verification.
---

# NixOS Reinstall

Keep inspection separate from the first destructive operation. Require explicit authorization to erase the target and confirm that provider console or rescue access exists.

## Inspect the target

Run the bundled inventory command:

```bash
scripts/preflight.sh root@<address>
```

Confirm the target address, architecture, boot mode, network configuration, and system disk. Use a stable `/dev/disk/by-id/...` path for the disk.

Create or update one pinned `nixosConfiguration` with the observed disk and boot mode, permanent public keys, network configuration, binary caches, and an explicit `system.stateVersion`. Add a disko configuration for the system disk.

## Choose the installation path

Use the raw-image path for hosts with about 1 GiB RAM or otherwise known to be too small for the upstream nixos-anywhere environment. Require exactly one disko-managed system disk and a root partition that is last on that disk; otherwise use nixos-anywhere. Build the installed system elsewhere, then enter the repository's `nixos-disk-writer-kexec` system. It only runs SSH, rsync, and disk tools.

Use nixos-anywhere when the target has enough memory for its upstream kexec image and Nix installer. A host affected by the known PVE/QEMU kexec placement failure can use either path with the compatibility flags below.

## Low-memory path: raw image and rsync

The repository exposes one package per NixOS host that has a disko disk configuration. Build the intended host image and the disk-writer kexec image for its architecture:

```bash
target_system=$(nix eval --raw \
  .#nixosConfigurations.<host>.pkgs.stdenv.hostPlatform.system)
image_dir=$(nix build --accept-flake-config --no-link --print-out-paths \
  ".#packages.${target_system}.nixos-bootstrap-image-<host>")
raw_image=$(find "$image_dir" -maxdepth 1 -type f \
  \( -name '*.raw' -o -name '*.img' \) -print -quit)
kexec_dir=$(nix build --accept-flake-config --no-link --print-out-paths \
  ".#packages.${target_system}.nixos-disk-writer-kexec")
kexec_archive="$kexec_dir/nixos-disk-writer-kexec-${target_system}.tar.gz"
```

Upload and enter the kexec system from the existing Linux installation:

```bash
scp "$kexec_archive" root@<address>:/root/
ssh root@<address> tar -xzf "/root/$(basename "$kexec_archive")" -C /root
ssh root@<address> /root/kexec/run
scripts/wait-for-ssh.sh --down root@<address>
scripts/wait-for-ssh.sh root@<address>
ssh root@<address> test -e /etc/nixos-disk-writer-kexec
```

The runner schedules kexec after returning, so always wait for SSH to go down and then come back. The new system restores the existing network configuration and SSH host keys. On the verified PVE 7.1 / QEMU 6.1 i440FX failure that places a large initrd above 4 GiB and reports `Initramfs unpacking failed` or a failed `/sysroot/nix/.ro-store` mount, run the final command as:

```bash
ssh root@<address> /root/kexec/run \
  --kexec-extra-flags "--kexec-syscall --mem-max=0xffffffff"
```

Confirm the destination with `lsblk`, then resolve the selected stable disk link because rsync would otherwise replace the symlink instead of writing its target:

```bash
target_device=$(ssh root@<address> \
  readlink -f /dev/disk/by-id/<system-disk>)
mountpoints=$(ssh root@<address> lsblk -no MOUNTPOINTS "$target_device")
test -z "$mountpoints"
rsync --ignore-times --no-whole-file --write-devices --fsync \
  --compress-choice=zstd --compress-level=3 --info=progress2 \
  "$raw_image" \
  "root@<address>:$target_device"
```

Only write an unmounted destination.

After a connection failure, rerun the same command. Rsync compares the image with the partially written device and transfers the differing blocks.

Reboot from disk after rsync succeeds. Wait for the old SSH service to stop before removing its host key, then accept the new system's key:

```bash
ssh root@<address> systemd-run --on-active=1s systemctl reboot
scripts/wait-for-ssh.sh --down root@<address>
ssh-keygen -R <address>
scripts/wait-for-ssh.sh root@<address>
```

The bootstrap configuration expands its final root partition and filesystem on first boot.

## Standard path: nixos-anywhere

Pin the nixos-anywhere revision used for the reinstall:

```bash
nixos_anywhere=github:nix-community/nixos-anywhere/91fc9b70fc295258c366cce8627efb6f185fd9fb
```

Choose `--build-on local` when the controller can build the target architecture and `--build-on remote` otherwise. Evaluate the target before mutation:

```bash
nix eval --raw \
  .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath
nix build --accept-flake-config --dry-run --no-link \
  .#nixosConfigurations.<host>.config.system.build.toplevel
```

Enter the upstream kexec environment as a separate, reversible phase:

```bash
nix run "$nixos_anywhere" -- \
  --flake .#<host> \
  --target-host root@<address> \
  --build-on <local-or-remote> \
  --phases kexec
```

For the verified PVE 7.1 / QEMU 6.1 i440FX initrd-placement failure, add this nixos-anywhere argument to the kexec phase:

```text
--kexec-extra-flags "--kexec-syscall --mem-max=0xffffffff"
```

When runtime secrets are required, configure services with runtime paths and prepare the filesystem tree copied by nixos-anywhere:

```bash
extra_files=$(mktemp -d)
install -d -m 700 "$extra_files/var/lib/nixos-secrets"
install -m 600 <local-secret-file> \
  "$extra_files/var/lib/nixos-secrets/<secret-name>"
```

Keep secret contents out of Nix expressions and command output.

Verify the address, route, SSH access, and selected disk in the installer. Then run the destructive and installation phases separately:

```bash
nix run "$nixos_anywhere" -- \
  --flake .#<host> --target-host root@<address> \
  --build-on <local-or-remote> --phases disko

nix run "$nixos_anywhere" -- \
  --flake .#<host> --target-host root@<address> \
  --build-on <local-or-remote> --extra-files "$extra_files" \
  --phases install

nix run "$nixos_anywhere" -- \
  --flake .#<host> --target-host root@<address> \
  --build-on <local-or-remote> --phases reboot

scripts/wait-for-ssh.sh --down root@<address>
ssh-keygen -R <address>
scripts/wait-for-ssh.sh root@<address>
```

Omit `--extra-files "$extra_files"` when the installation has no runtime secrets. Keep the temporary directory until post-boot verification succeeds, then remove it with `rm -r -- "$extra_files"`.

## Verify the installed system

Verify the hostname, OS, boot mode, root filesystem and mount options, partition size, network routes, failed units, and effective Nix substituters. For a raw-image install, confirm that the root partition and filesystem expanded to the disk. Restore runtime secrets through their normal deployment path.

---
name: nixos-anywhere-reinstall
description: Reinstall a remote Linux host as NixOS through SSH with nixos-anywhere and disko. Use for destructive Debian, Ubuntu, Fedora, or other Linux-to-NixOS reprovisioning when the agent runs outside the target, including inventory, Btrfs disk configuration, binary-cache checks, staged kexec, timed installation, runtime secret transfer, and post-reboot verification.
---

# NixOS Anywhere Reinstall

Reinstall remote Linux hosts in measured phases. Keep inspection and kexec separate from the first destructive phase, disko.

## Establish authority and recovery

Require explicit authorization to erase the target. Confirm that a provider console, serial console, or rescue mode exists. Stop if the target identity, disk, static network configuration, or recovery path is ambiguous.

Keep host-specific configuration and credentials outside this skill. Use an SSH agent when the controller already has an authorized identity; do not copy a private SSH key into the project.

Create a timing file and use it for every material stage:

```bash
timings="$(pwd)/nixos-anywhere-timings.tsv"
nixos_anywhere=github:nix-community/nixos-anywhere/91fc9b70fc295258c366cce8627efb6f185fd9fb
nixos_images=github:nix-community/nixos-images/27bfc9df981b35f4911b8ea3bc3ecf51164beaa2
```

Pin the nixos-anywhere revision and kexec image independently and record both. A stable CLI tag can still default to an obsolete installer image. `scripts/time-phase.sh` records UTC start time, wall-clock seconds, and exit status even when a phase fails.

## Inventory the target

```bash
scripts/time-phase.sh "$timings" preflight -- \
  scripts/preflight.sh root@<address>
```

Record:

- OS, architecture, virtualization, DMI model, CPU, RAM map, zram, and boot mode.
- Root device, every block device, stable `/dev/disk/by-id` names, mounts, and swap.
- Interfaces, addresses, routes, gateways, and DNS.
- Existing authorized-key and SSH host-key fingerprints.
- Whether kexec is available and physical RAM is at least 1.5 GiB.

Set the pinned image URL from the recorded target architecture:

```bash
target_arch=<x86_64-or-aarch64>
kexec_image="https://github.com/nix-community/nixos-images/releases/download/nixos-25.11/nixos-kexec-installer-noninteractive-${target_arch}-linux.tar.gz"
```

Use a current, independently pinned `nixos-images` build when the release image is too old for the target. Build it on an x86_64 Nix machine or on a NixOS target before kexec; the package is substitutable from the nix-community cache:

```bash
nix build --accept-flake-config \
  "$nixos_images#packages.x86_64-linux.kexec-installer-nixos-stable-noninteractive"
kexec_image=$(readlink -f result)/nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz
```

Passing a local file makes nixos-anywhere upload it. If the image already exists on the target, expose only its store directory over target-local loopback HTTP and pass that URL to avoid a target-controller-target copy.

Use `/dev/disk/by-id` in disko. Never select a disk from `/dev/sdX`, `/dev/vdX`, or `/dev/nvmeXnY` naming alone. Immediately before disko, resolve the selected by-id link again and compare its serial and size with the inventory.

## Build the declarative configuration

Create or update one pinned Flake `nixosConfiguration`. Include the requested hostname, permanent public keys, observed storage modules, static network configuration, matching BIOS or UEFI boot loader, shared binary caches, and an explicit `system.stateVersion`.

For a simple VM with one Ethernet interface, prefer `systemd-networkd` with `matchConfig.Type = "ether"`. Do not bind the configuration to a provider-generated MAC address or interface name unless that identity is contractually stable. Likewise, raw nftables rules can use `meta oiftype ether` instead of a transient output-interface name.

Use Btrfs for root unless the user requests another filesystem. Enable ZSTD in the disko mount options so compression applies while NixOS is first copied, not after installation:

```nix
content = {
  type = "filesystem";
  format = "btrfs";
  mountpoint = "/";
  mountOptions = [
    "compress=zstd:3"
    "noatime"
  ];
};
```

Keep the partition and subvolume layout simple unless encryption, RAID, snapshots, or persistence was requested. When disko manages a BIOS disk, let it populate `boot.loader.grub.devices`; do not also set `boot.loader.grub.device`.

## Keep installation secrets out of the store

Nix path values that reference a source-tree secret copy it into the world-readable Nix store. Configure services with a runtime path such as `/var/lib/nixos-secrets/tailscale-auth-key`, then stage the file for nixos-anywhere:

```bash
extra_files=$(mktemp -d)
install -d -m 700 "$extra_files/var/lib/nixos-secrets"
install -m 600 <local-secret-file> \
  "$extra_files/var/lib/nixos-secrets/tailscale-auth-key"
```

Pass the directory only to the install phase with `--extra-files "$extra_files"`. Remove the temporary directory after verification. Never print the secret or place its contents in a Nix expression, command-line argument, or timing log.

## Reuse and verify binary caches

The Flake's top-level `nixConfig` configures the controller; it is not automatically the installed daemon configuration. Keep project cache URLs and keys once in `nixConfig`, preferably as `extra-substituters` and `extra-trusted-public-keys`, and consume those lists from the shared NixOS module. Let Nix retain its official-cache defaults.

Inspect the target configuration:

```bash
nix eval --json \
  .#nixosConfigurations.<host>.config.nix.settings.substituters
nix eval --json \
  .#nixosConfigurations.<host>.config.nix.settings.trusted-public-keys
```

Nixos-anywhere copies these effective settings into its kexec installer. Do not use `--no-use-machine-substituters` when the install depends on a project cache.

## Validate before mutation

Add new Nix files to the Git index with intent-to-add, then time the repository's formatter, checks, target evaluation, and build or VM test. A full closure build may wait until the kexec installer when controller and target architectures differ.

```bash
scripts/time-phase.sh "$timings" checks -- just check
scripts/time-phase.sh "$timings" target-eval -- \
  nix eval --raw \
  .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath
```

Inspect the generated disko script and selected disk. Do not continue merely because unrelated repository configurations fail; isolate and report the failure, then require the target configuration to evaluate successfully.

Choose `--build-on local` when the controller can build the target architecture. Choose `--build-on remote` for an architecture mismatch. Do not allow Nix's `auto` mode to conceal this decision.

Run the cache dry-run against the controller store. Using a remote store with `--dry-run --eval-store auto` can return success with `don't know how to build`; making the entire evaluation store remote is needlessly slow.

```bash
scripts/time-phase.sh "$timings" cache-dry-run -- \
  nix build --accept-flake-config --dry-run --no-link \
  .#nixosConfigurations.<host>.config.system.build.toplevel
```

Review both lists. Host-specific text, unit, and activation derivations are expected to build and should be small. Kernels, compilers, language dependency graphs, and project packages must be fetched. If a heavy output would build, query it with `nix path-info --store <cache-url> <output-path>` and fix cache publication or daemon settings before kexec.

With `--build-on remote`, nixos-anywhere first copies the derivation graph to the installer. A line such as `copying 6000 paths` and transfers ending in `.drv`, patches, or source references are evaluation/build metadata, not 6000 local compilations. Judge cache coverage from `copying path ... from 'https://...'` and `building '...drv'` lines. A project-specific final system, generated `/etc`, systemd units, and Home Manager generation normally build locally unless that exact closure was published beforehand.

Prepare the pinned tool outside the kexec measurement:

```bash
scripts/time-phase.sh "$timings" tool-prepare -- \
  nix run "$nixos_anywhere" -- --help
```

## Enter kexec and verify installer caches

Time kexec separately; it is reversible from the provider console and does not format the disk:

Before using a `nixos-images` tarball, inspect its `run` script. If it enters
`$INITRD_TMP`, deletes that directory from an `EXIT` trap, and backgrounds the
delayed execute, change the delayed command to leave the temporary directory:

```sh
nohup sh -c "sleep 6 && cd / && '$SCRIPT_DIR/kexec' -e ${kexec_extra_flags}" &
```

Without `cd /`, the background shell inherits a deleted working directory and
may fail with `getcwd: No such file or directory` instead of entering the
installer. This is the failure reported in nixos-anywhere issues 93 and 289.

```bash
scripts/time-phase.sh "$timings" kexec -- \
  nix run "$nixos_anywhere" -- \
  --flake .#<host> \
  --target-host root@<address> \
  --build-on <local-or-remote> \
  --kexec "$kexec_image" \
  --phases kexec
```

On the verified PVE 7.1 / QEMU 6.1 i440FX failure mode, kexec placed a roughly 450 MiB initrd above 4 GiB and the guest reported `Initramfs unpacking failed: XZ-compressed data is corrupt`, followed by a failed `/sysroot/nix/.ro-store` SquashFS mount. When the preflight DMI and provider console match that failure, keep the VM's full CPU and RAM allocation and constrain only the kexec payload:

```bash
--kexec-extra-flags "--kexec-syscall --mem-max=0xffffffff"
```

This selects the compatibility syscall and places the initrd below 4 GiB. Do not reduce the VM permanently. Attach the serial console before kexec when the provider supports it; a black VNC framebuffer alone does not distinguish an early initrd failure from a running headless installer.

Nixos-anywhere waits for the installer to become reachable. Its kexec image normally carries the existing SSH host keys forward. Verify `/etc/os-release`, the address, default route, SSH agent access, selected disk, and effective installer caches; handle a key change only when it is expected and explained by the selected image.

If the host enters an initrd emergency shell, inspect failed mount units from the provider console. Do not wait indefinitely for SSH. In particular, a failed `/sysroot/nix/.ro-store` SquashFS mount means the kexec image did not reach stage 2; rebooting returns to the untouched disk because disko has not run.

```bash
ssh root@<address> nix config show substituters
ssh root@<address> nix config show trusted-public-keys
```

The installer settings and the controller dry-run must agree. This is the final cache checkpoint before disko.

## Format, install, and reboot as separate phases

Time each phase independently so evaluation/build time is not hidden inside a single reinstall duration:

```bash
scripts/time-phase.sh "$timings" disko -- \
  nix run "$nixos_anywhere" -- \
  --flake .#<host> --target-host root@<address> \
  --build-on <local-or-remote> --phases disko

ssh root@<address> \
  'findmnt -no SOURCE,FSTYPE,OPTIONS /mnt; lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS'

set -o pipefail
scripts/time-phase.sh "$timings" install -- \
  nix run "$nixos_anywhere" -- \
  --flake .#<host> --target-host root@<address> \
  --build-on <local-or-remote> --extra-files "$extra_files" \
  --phases install 2>&1 | tee nixos-anywhere-install.log

scripts/time-phase.sh "$timings" reboot -- \
  nix run "$nixos_anywhere" -- \
  --flake .#<host> --target-host root@<address> \
  --build-on <local-or-remote> --phases reboot
```

Do not start `install` until `/mnt` is the intended new root, its partition has the expected size, and its live mount options contain `compress=zstd:3`. The live mount proves that the first Nix store copy is compressed; checking only the future NixOS configuration is insufficient.

Summarize the install log before calling it a cache miss:

```bash
awk '
  /^building / { builds++ }
  /from '\''https:\/\// { substituted++ }
  /to '\''ssh-ng:\/\// { remote_graph++ }
  END {
    printf "actual builds: %d\nsubstituted outputs: %d\nremote graph paths: %d\n",
      builds, substituted, remote_graph
  }
' nixos-anywhere-install.log
```

Inspect the actual build names. If derivation-graph transfer is the bottleneck and a builder for the target architecture exists outside the machine being erased, use `--build-on local` or prebuild both store paths and pass `--store-paths`; do not reinterpret metadata transfer as missing binary-cache coverage.

Do not use `--copy-host-keys` unless preserving the old SSH identity is intended. After the expected reboot key change, replace the obsolete known-host entry and use `StrictHostKeyChecking=accept-new` once. Then measure reconnection:

```bash
scripts/time-phase.sh "$timings" reconnect -- \
  scripts/wait-for-ssh.sh root@<address>
```

## Verify and interpret timings

Verify the installed system:

```bash
hostname
cat /etc/os-release
findmnt -no SOURCE,FSTYPE,OPTIONS /
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS
swapon --show
ip address
ip route
systemctl --failed
```

Require `compress=zstd:3` in the live root mount and confirm the root partition consumes the intended disk space. Check the runtime secret's owner and mode without reading it, the effective Nix substituters and keys, Tailscale preferences/connectivity, and the active nftables ruleset.

If the project is meant to live on the target, restore it to `/home/<user>/nix` after the first boot. Clone with the forwarded SSH agent, synchronize the current worktree while excluding private secret submodules, and run one target-local switch:

```bash
nixos-rebuild switch --accept-flake-config \
  --flake path:/home/<user>/nix#<host>
```

Confirm that the project-level skill exists under that checkout. Do not install it into a global agent-skills directory.

Sort the timing rows by duration and calculate each phase's share of their total. Use the result to optimize the actual bottleneck:

```bash
awk -F '\t' '
  NR > 1 && $4 == 0 { seconds[$1] += $3; total += $3 }
  END { for (phase in seconds) printf "%s\t%d\t%.1f%%\n", phase, seconds[phase], 100 * seconds[phase] / total }
' "$timings" | sort -k2,2nr
```

- Long kexec: pin or locally mirror the kexec tarball near the target.
- Long cache dry-run or install builds: repair cache coverage; do not tune compilation concurrency first.
- Long install with substitutions complete: compare target cache throughput and closure copy/build placement.
- Long reconnect: inspect boot-critical units and the network-online path.

Report the Flake revision, disk ID, final partition layout, compression option, cache coverage, timing distribution, and failed units. Inspect Home Manager activation separately: network commands need finite timeouts, and private-service work must be ordered after the corresponding VPN autoconnect unit.

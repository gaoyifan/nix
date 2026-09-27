# Incus Hackintosh Operations

## Purpose and current state

`el2` runs the Incus VM `hackintosh` as the macOS computer `Hackintosh`,
synchronizing iCloud Photos and exporting a file archive to `pool0/footage2`.

| Item | Value |
| --- | --- |
| macOS | [Tahoe 26.6.2](https://support.apple.com/en-ca/100100) (`25G83`) |
| User | `yifan` (local administrator) |
| CPU and memory | 1 socket, 4 cores, 8 GiB |
| System disk | 128 GiB Incus volume, APFS |
| Data disk | 2 TiB `pool0` block volume, APFS `Photos`, mounted at `/Volumes/Photos` |
| Network | VLAN 642, `100.64.2.80`, `00:16:CB:64:02:80`, VMXNET3 |
| Boot | OpenCore 1.0.7 in the system disk EFI partition |
| Attached disks | System and Photos data disks; Recovery and external OpenCore are detached |
| Nix | Upstream multi-user Nix 2.35.2 |
| Guest repository | `/Users/yifan/nix` |

The VM automatically boots macOS and logs in as `yifan`; the export worker opens
Photos when it runs. FileVault is off for unattended login. SSH uses public-key
authentication.

## Boot-chain provenance

| Input | Revision or SHA-256 |
| --- | --- |
| `kholia/OSX-KVM` | `4c378a4b5e0b219783683012bec680325eb40719` |
| Source `OpenCore.qcow2` | `6ed36c0c2a4206ccc695f6b1a734a1cc6f94d288b0517c705d351c63cb92a6f3` |
| `acidanthera/OpenCorePkg` 1.0.7 | `6651fc36a8c3dca36a3231ba00679611100dbe85` |
| `OpenCore-1.0.7-RELEASE.zip` | `2ffab6ebf58c7aefb0bcb3a1a385d207746823d6dd87d44bd666e1286939943e` |
| Apple ID VM-attestation patch | `lucid-fabrics/osx-proxmox-next@e52af3eb920f962f2d6f4b1e27882dbde66e02bf` |
| `macOS-on-Incus/QEMU-Scriptlet` reference | `041550e8f2e25f085e984de8799deccae2304bc9` |
| `corpnewt/GenSMBIOS` | `573f5fc375cb52688ccac4312de8422ae263dcf2` |
| Apple Recovery product | `140-93589` |
| `BaseSystem.chunklist` | `06f7c498f856341f467ba1faedf2717fb2c172ae0aff4658a1467cbf46b711f9` |
| Apple `BaseSystem.dmg` | `edddd0d5869caaa12e29e6996a04f11590280580976a119dbd42c24fa62fe18e` |
| Converted `BaseSystem.img` | `4aec7443daa3851effb6ffbba97b34bf2896acf1a28ca152e0c3d0f073c3097e` |
| Recovery copy of personalized `OpenCore.raw` | `4d919698c8181efd1792681667f74e49a00f35422ae28133985923e180dbc6e2` |
| Installed OpenCore `config.plist` | `418652df3f1d8bce143a1dc83e84916946bbd847f8cc0c6c30aba8dc7124cf9f` |

`BaseSystem.img`, the recovery copy of `OpenCore.raw`, the official 1.0.7 archive,
the pre-upgrade OpenCore image, a pre-upgrade system EFI copy, and the private
SMBIOS record remain in `/var/lib/incus-macos`; no external disk is attached to
the running VM. The host backup includes the identity and EFI recovery material
and excludes the reproducible Recovery image. Never put the SMBIOS record in Git
or the Nix store, and never boot a clone with the same identity.

The persistent identity retains the original MacPro7,1 serial, MLB, and System
UUID. Its declared VMXNET3 MAC uses an Apple OUI, and OpenCore ROM is the same
six-byte address without separators. `macserial -s` confirms the effective
Model, Serial, MLB, System ID, and ROM; the MLB also passes OSX-KVM's Apple
Recovery validation. Generate a new complete identity before networking a clone.

The OSX-KVM configuration named `AppleMCEReporterDisabler.kext`, while the image
contains `MCEReporterDisabler.kext`; the installed configuration uses the real
path. Production boot arguments contain no verbose, debug, or serial flags. The
picker is hidden for unattended boot; hold Option, Escape, or Zero during
OpenCore initialization to show it. `macOS` is stored as the default entry in
persistent NVRAM. OpenCore 1.0.7 `ocvalidate` reports no configuration issues.
The installed configuration includes the complete two-way kernel sysctl-name
swap required for Apple Account attestation on Sequoia and Tahoe. After a normal
guest restart, `sysctl -n kern.hv_vmm_present` returns `0`; applying only the
`hibernatecount` half of this patch leaves the real VM-present OID visible and
does not fix sign-in. The detached recovery copy carries the same patch pair.

## Declarative deployment

The host definition is under `nixos/hosts/el2/virtualisation.nix`. Its QEMU
scriptlet replaces Incus's hot-plugged root disk with a static VirtIO device,
replaces the NIC with VMXNET3 while retaining the Incus tap and VLAN, and adds
AppleSMC, VMware SVGA, and USB input. Incus still owns storage, networking, QMP,
SPICE, firmware variables, and instance lifecycle.

Apply host changes with:

```bash
just fmt
just check
just nixos
```

The `nixos-hackintosh` profile sets `boot.autostart=true`. The module default for
other declarative VMs remains `last-state`. Do not reboot `el2` to validate or
maintain this workload; use guest-level restart or stop/start cycles only.

The `photos` device references the custom Incus block volume
`pool0/hackintosh-photos`. macOS owns its GPT and APFS layout and mounts the
`Photos` volume automatically at `/Volumes/Photos`. Because this is a custom
volume, instance snapshots do not include its contents; snapshot or back it up
separately. If encrypted pool0 is unavailable during Incus startup,
`start-pool0-dependent-vms.service` starts the VM after pool0 is unlocked.

## CPU compatibility fixes

The installed EFI includes two fixes validated on macOS `25G83` / Darwin
`25.6.0`, QEMU 10.2.4 and VirtualSMC 1.3.7 on 2026-09-26:

- A kernel patch makes the unused Bluetooth HCI controller's `start` method
  return false. It matches the verified 16-byte function entry and is limited
  to Darwin `25.6.0`. `bluetoothd` and `WirelessRadioManagerd` then remain near
  zero CPU, with no recurring Bluetooth daemon exits.
- An ACPI patch hides QEMU's SMC node from macOS while retaining its boot-time
  device. `vsmcgen=2` lets VirtualSMC provide the runtime AppleSMC service.
  The native probe enumerates 69 unique keys and ends with `0xb8`;
  `PerfPowerServices` remains near zero CPU and the former `0x82` errors stop.

The exact patch bytes, source references and measurements are in
[the CPU investigation](research/hackintosh-idle-cpu.md#实施记录2026-09-26).
The ACPI patch matches the verified DSDT's length and OEM table ID. Recheck it
after changes to QEMU or the VM hardware configuration; recheck the Bluetooth
patch after macOS updates. Remove the Bluetooth patch before adding Bluetooth
hardware to the guest.

Keep Photos processing and synchronization services enabled. Downloads,
conversion, and indexing are real workloads; assess idle CPU after they settle.

Private backups and validated configs are in
`/var/lib/incus-macos/cpu-fix-20260926/`. The instance and the separate Photos
volume each have a `pre-cpu-fix-20260926` snapshot. For a firmware rollback,
cleanly stop the guest and restore only the saved `config-before.plist` into the
system ESP; do not roll back the Photos volume as part of reverting EFI changes.
The detached `OpenCore.raw` retains the earlier boot configuration as recovery
media.

Incus hides stopped ZFS block volumes with `volmode=none`. For offline EFI
maintenance, verify the instance is stopped, temporarily set its system zvol
`pool1/incus/virtual-machines/hackintosh.block` to `volmode=dev`, and restore
`volmode=none` before starting the instance. Verify the GPT partition offset
before using it; the current system ESP begins at byte 20480. Never write to the
live VM's block device from the host.

## Remote administration

Use SSH at `yifan@100.64.2.80` for routine administration. The graphical
console is available to a standard VNC client at `100.64.2.254:5900`. This is
an address on `el2`, not the guest address.

The `hackintosh-vnc.service` unit runs a small display bridge:

```text
Incus SPICE socket -> spicy on Xvfb -> x11vnc -> VNC client
```

This exposes the same console that Incus owns, including boot and login screens,
and carries keyboard and pointer input back to the VM. It binds only the VLAN
642 host IPv4 address and requires classic VNC password authentication. Classic
VNC does not encrypt the session, so connect only through the private network or
a trusted VPN. The intermediate X display and its authentication cookie are
root-only on the host.

The root-only password file is `/var/lib/incus-macos/vnc.pass`. To rotate it:

```bash
sudo x11vnc -storepasswd /var/lib/incus-macos/vnc.pass
sudo systemctl restart hackintosh-vnc.service
```

Check the endpoint with:

```bash
systemctl status hackintosh-vnc.service
ss -ltn '( sport = :5900 )'
```

Guest Screen Sharing is disabled. On VMware SVGA, Tahoe accepted its VNC
authentication but could not obtain a pixel format or framebuffer and returned
black frames. The host bridge reads the already-working SPICE console instead
of depending on unavailable guest OpenGL or hardware video encoding.

## Initial installation and Nix bootstrap

Determinate Nix no longer publishes `x86_64-darwin` installers. Intel macOS must
therefore use the upstream multi-user installer. Nixpkgs 26.05 is the final
release supporting Intel Darwin; keep the guest on the repository's locked
revision and do not use an unpinned `nixpkgs#...` bootstrap.

Tahoe protects `/etc/fstab` from headless processes. Grant Terminal Full Disk
Access before running the upstream installer in Terminal:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://nixos.org/nix/install \
  | sh -s -- --daemon --yes
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

Place the implementation worktree at `/Users/yifan/nix`. The first activation
must also run from Terminal because Tahoe applies the same protection to
`/etc/pam.d`. `just darwin` handles upstream/Determinate daemon labels, migrates
the pre-nix-darwin shell files once, and uses the locked Hackintosh flake:

```bash
cd /Users/yifan/nix
just darwin
```

## Known limitations and recovery

- `system_profiler` reports one 8 GiB QEMU DIMM. MacPro7,1 consequently displays
  a cosmetic “Memory Modules Misconfigured” notification. Splitting the VM into
  four NUMA nodes solely to hide this warning would worsen the hardware model;
  no suppressor kext is installed.
- Both an Incus ACPI stop and `shutdown -h now` can reach the macOS shutdown
  sequence without causing QEMU to exit. Sync the guest first, wait up to two
  minutes, then use `incus stop hackintosh --force` if necessary. Normal
  `shutdown -r now` restart works.
- The VNC bridge can expose only frames produced by the Incus SPICE console. If
  that surface stops refreshing during a long GUI session, SSH remains the
  recovery path; restart the guest, then verify `hackintosh-vnc.service` is
  active.

To recover the boot chain, stop the VM, temporarily reattach
`/var/lib/incus-macos/OpenCore.raw`, boot macOS, mount the system and external EFI
partitions, copy the external `EFI` directory to the system ESP, and again set
`macOS` as the OpenCore default with Ctrl+Enter. Attach `BaseSystem.img` only when
Recovery is actually required.

## Maintenance and iCloud boundary

Install macOS updates manually during a maintenance window. Take a stopped Incus
snapshot first, confirm the target release still supports Intel, and re-run the
cold-boot, identity, Photos import/export, and SSH checks after the update.

Keep `/Volumes/Photos/Photos Library.photoslibrary` as the System Photo Library
with **Download Originals to this Mac** selected. A primary-original inventory
can still miss absent Live Photo components or edited renditions; use the export
report to assess completeness.

## Photo archive on pool0/footage2

The pipeline is Photos download → OSXPhotos export/cleanup → one rsync pull →
ZFS snapshot. `pool0/footage2` is an encrypted filesystem mounted at
`/pool0/footage2`, separate from the live APFS library. It permanently retains
files already archived, even after their deletion in iCloud. Edits and metadata
are updated in place; ZFS snapshots retain earlier versions for two weeks at
six-hour intervals, three months daily, and one year monthly.

The guest exports to `/Volumes/Photos/icloud-export` with
`--update --update-errors --download-missing --use-photokit --cleanup --not-hidden`.
UUID directories contain originals, edited versions, Live Photo image/video
pairs, RAW files, and XMP/full JSON sidecars.
Original media bytes are unchanged. The staging directory follows the current
library rather than retaining deleted media forever. Photos deleted before a
successful archive may never reach ZFS. Separate Shared Albums and hidden assets
are excluded; iCloud Shared Photo Library is included. The export is not a
complete `.photoslibrary` backup or a promise of round-trip Apple editing state.

`icloud-photos-backup.service` on el2 runs the guest's
`/Users/yifan/.local/bin/icloud-photos-export`, then pulls staging once without
`--delete`. A failed/partial export is still transferred, but the service fails
and the scheduled snapshot is skipped. Subsequent runs converge incrementally.
The guest wrapper validates the per-file report because OSXPhotos may return
zero despite missing files or export errors. It never downloads previews as
substitutes for originals. The APFS volume identity and ZFS mount are checked
before writing.

The SSH command launches the worker in Terminal's authorized GUI session and
waits for its actual exit status, relaying the log. Terminal has been granted
access to all Photos through the normal macOS permission dialog. Keep `yifan`
logged in; Terminal's authorization does not extend to a Python process run
directly over SSH. The worker explicitly opens the Photos library before
issuing export requests. The generated Terminal window closes after completion.

Two narrowly scoped workarounds are pinned to OSXPhotos 0.77.1:

- Missing original Live Photo resources use Photos' original AppleScript
  export, because the upstream PhotoKit Live exporter warns that an original
  request can return edited content. Other resources, including edited Live
  movies and missing burst members, use PhotoKit.
- For edited Live Photos, the current PhotoKit type determines whether an
  edited companion movie exists. Turning Live off produces a valid edited still,
  not a missing edited video. The original image/video pair is still preserved.

Both routes run inside one OSXPhotos export with one report and one cleanup,
followed by one rsync. Do not replace this worker with the bare CLI command or
upgrade OSXPhotos without retesting these original/edited cases. Offline-only
export can silently skip absent edited renditions.

Hidden photos are excluded by user choice. Photos' **Use Password** setting
remains enabled. Staging cleanup removes previously exported hidden assets;
rsync still does not delete files already archived on ZFS. Thus hiding a photo
stops future exports but does not erase earlier backups. Purging an already
archived item requires explicit deletion from ZFS and checking retained snapshots.

The znapzend `icloud-photos` source runs the service as its presnapshot command
every six hours. `--skipOnPreSnapCmdFail` prevents incomplete attempts from being
recorded as successful snapshots. The existing local Prometheus/Grafana stack
shows last successful archive age, failed attempts, missing/error counts, and
APFS usage; thresholds are 12 hours without success and 85% APFS usage.

### Initial setup and activation

Create the dataset once in an el2 terminal, using the same passphrase as the
existing `unlock-pool0` datasets. Do not put the passphrase in a shell argument,
the repository, or the Nix store:

```bash
sudo zfs create -o encryption=aes-256-gcm -o keyformat=passphrase \
  -o keylocation=prompt -o compression=zstd -o atime=off \
  -o mountpoint=/pool0/footage2 pool0/footage2
sudo chown yifan:users /pool0/footage2
sudo chmod 700 /pool0/footage2
```

The dataset must exist before activating the host configuration because it is
part of `unlock-pool0`. After host startup, run `sudo unlock-pool0` before backups
can proceed.

The guest's Python runtime and OSXPhotos 0.77.1 are built by
`pkgs/osxphotos.nix`. CPython 3.13 comes from the locked Nixpkgs input;
the `osxphotos-src` flake input pins the upstream source, including its
`pyproject.toml` and `uv.lock`. uv2nix builds the Intel macOS runtime dependencies
and OSXPhotos from that source inside the Nix store; development extras are not
enabled. Activation does not run uv or install Python packages.

```bash
cd /Users/yifan/nix
just darwin
```

Home Manager installs `icloud-photos-export` and `osxphotos` entrypoints backed
by the Nix store. To update, change the pinned `osxphotos-src` revision and run
`nix flake lock`, then revalidate the version-specific export workarounds. There
is no local Python dependency lock to regenerate. The build checks dependencies and
native Photos/Objective-C imports; sample export tests still require the user's
authorized GUI session.

`yifan` has declarative passwordless sudo through
`security.sudo.extraConfig` in `darwin/hackintosh.nix`. Run `just darwin` in
Terminal: Tahoe's protected user-default domains can reject activation over
SSH even when sudo succeeds. No account password is stored in Nix configuration.

The host's dedicated SSH private key is encrypted in the private secrets
submodule at `secrets/files/nixos/el2/icloud-photos-ssh-key.age`. NixOS activation
uses agenix to install it at `/run/agenix/icloud-photos-ssh-key` (root only).
Rebuilding requires the private submodule and el2's SSH host decryption identity;
after replacing that identity, an authorized operator must rekey the ciphertext
for the new host key. See [Secrets Management](secrets.md).
The backup public key is declared in `darwin/hackintosh.nix`, restricted to
connections from `100.64.2.254` without forwarding. Rotating the backup key
requires updating both the ciphertext and that public key, then reactivating
both configurations. Test access through the real SSH path;
Terminal permissions alone do not grant Remote Login access to protected files.
Use the macOS **Allow full disk access for remote users** setting if required.

On el2, apply configuration with `just fmt`, `just check`, and `just nixos`.
No host reboot is needed. For a manual archive run:

```bash
sudo systemctl start icloud-photos-backup.service
sudo journalctl -u icloud-photos-backup.service -n 50
sudo zfs list -t snapshot -r pool0/footage2
```

Manual service execution updates the archive but does not itself create a
snapshot; znapzend creates scheduled snapshots after its presnapshot service
succeeds. Do not launch a separate guest export while a host pull is running.
The archive includes `.osxphotos_export.db`, `.export-report.json`, and
`.backup-status.json` for audit and recovery. A snapshot can be browsed under
`/pool0/footage2/.zfs/snapshot/<name>/`; restore selected files into a separate
directory rather than rolling back the entire archive.

For incomplete exports, inspect `.export-report.json` and the service journal,
restore connectivity or GUI authorization as appropriate, and rerun the normal
service. It retries missing resources and earlier errors. Never use `--cleanup`
with a UUID-filtered diagnostic export into production staging: that would clean
staging down to the selected subset. Use an independent temporary directory for
such tests.

This archive shares pool0's hardware failure domain with the live photo disk.
There is no offsite replication of footage2 in this configuration. Existing
Kopia jobs for `pool0/footage` do not automatically back up `pool0/footage2`.

### Verify after changes

After tool or macOS updates, test JPEG/HEIC, video, RAW, Live Photos, edited Live
Photos (including Live disabled), and bursts in an independent export directory.
Check original hashes, edited renditions, metadata, incremental reruns, and hidden
asset exclusion. Use a disposable staging copy to verify that removal from
staging does not delete archived files, then restore a sample from a ZFS snapshot.

Build success alone is not backup acceptance. Require a fresh complete export
report, successful transfer, and a usable snapshot; missing media or failed
transfers must not advance the last-success timestamp. Check current status via
the service journal and monitoring rather than relying on past inventory counts.

# Incus Hackintosh Operations

## Purpose and current state

`el2` runs the Incus VM `hackintosh` as the macOS computer `Hackintosh`. It is
an Intel macOS host for a Photos library. Apple Account sign-in is under
validation; iCloud Photos is not yet enabled or accepted.

The accepted local configuration is:

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

The VM automatically boots macOS and logs in as `yifan`. Photos is opened
manually when needed. FileVault is off because it is incompatible with
unattended login. SSH accepts the shared public key and rejects password
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
| Installed OpenCore `config.plist` | `4c3071351752a03b37f2633c2c64a9e4ff3dc23c5c1311745e3fbb0a51028d7f` |

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

The one-time interactive setup used Apple Recovery to erase the target as APFS,
install Tahoe, create `yifan`, skip Apple Account, disable analytics, location,
Siri, Screen Time, and FileVault, and choose automatic update downloads without
automatic macOS installation.

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

During the 2026-09-14 bootstrap, the Nixpkgs 26.05 Intel Darwin cache omitted
test-only `character-ps`, `network-uri`, `semialign`, and `witherable` paths from
the `hermes-json` closure used by `nh`. Realizing their existing derivations
allowed the pinned build to complete; the accepted baseline snapshot retains the
resulting store closure.

## Acceptance record

Acceptance on 2026-09-14 produced these results:

- `just fmt`, `just fmt-check`, and `just check` passed on `el2`.
- `darwinConfigurations.Hackintosh` built and repeated `just darwin` activation
  returned zero in the guest.
- A fresh SSH shell provided Nix 2.35.2, just 1.51.0, nh 4.4.2, and Neovim
  0.12.4; guest `just check` passed.
- Password-only SSH was rejected with `Permission denied (publickey)` when SSH
  multiplexing was disabled for the test.
- Two batches containing JPEG, HEIC, and H.264 MP4 media were imported into the
  System Photo Library. Photos displayed six items. Exporting unmodified
  originals produced SHA-256 hashes identical to all six sources.
- The second three-item import took 1.36 seconds after the retained UI
  optimizations were active.
- At the three-minute post-boot sample, Photos used 0% CPU and 53 MiB RSS; the
  guest reported 98.7% CPU idle, 85% free memory pressure, and no swap activity.
- With Recovery and external OpenCore detached, an Incus stop/start reached
  automatic login in 49 seconds. The Photos library, Nix volume, exported files,
  and private identity fingerprint were unchanged.
- A stopped `accepted-baseline` Incus snapshot was created after acceptance.
- A stopped `identity-opencore-1.0.7` snapshot records the aligned MAC/ROM
  identity and OpenCore 1.0.7 system EFI.
- The `pre-apple-id-attestation-patch` snapshot precedes the Tahoe Apple Account
  kernel patch. The patched system EFI passes OpenCore 1.0.7 `ocvalidate`, and
  the running guest reports `kern.hv_vmm_present=0`.
- The 2 TiB pool0 data disk uses GPT and APFS, mounts at `/Volumes/Photos`, and
  passed a non-root write/read/delete test.
- The password-protected host VNC bridge displayed the live Photos desktop and
  accepted login input. A client restricted to unauthenticated VNC was rejected,
  and the listener was confined to `100.64.2.254:5900`.

The retained optimizations disable system/display/disk sleep, screen saver,
automatic logout, Dock animation and magnification, window animation, motion,
and transparency. Siri is disabled and `/nix` is not indexed. Photos analysis,
media indexing, Spotlight outside `/nix`, crash reporting, graphics frameworks,
and software-update checks remain enabled.

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

This phase does not claim iCloud compatibility or backup completeness. The data
disk is provisioned but the System Photo Library has not been moved to it. The
next phase must authenticate the Apple Account with two-factor authentication,
move or create the System Photo Library on `/Volumes/Photos`, enable Download
Originals to this Mac, test deletion propagation, and configure an independent
versioned backup of the library or exported originals.

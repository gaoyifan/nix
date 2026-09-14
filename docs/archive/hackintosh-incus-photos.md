# Incus Hackintosh for a Persistent Photos Workload

## Summary

Create an Incus virtual machine on `el2` that runs the latest stable Intel-compatible macOS release and is suitable for keeping Photos open continuously. The initial installation and Apple Account authentication may be interactive; routine operation must recover automatically after guest restarts and Incus stop/start cycles.

The VM will use hostname `Hackintosh`, local user `yifan`, and a minimal guest-specific nix-darwin environment initialized from `/Users/yifan/nix`. This phase validates the VM, local Photos behavior, remote administration, and unattended restart behavior. Real iCloud Photos synchronization, photo retention, and the independent backup pipeline remain a later phase.

## VM Configuration and Boot Chain

Use the following initial configuration:

| Setting | Value |
| --- | --- |
| Incus instance | `hackintosh` |
| macOS hostname and computer name | `Hackintosh` |
| Local user | `yifan` |
| macOS version | Latest stable Intel-compatible release at installation time; currently Tahoe 26.6.2 |
| CPU | One socket, four cores, one thread per core; fixed topology with CPU hotplug disabled |
| Memory | 8 GiB with memory hotplug disabled |
| System disk | 128 GiB on the `default` SSD-backed ZFS pool, formatted APFS in the guest |
| Photos data disk | 2 TiB custom block volume on `pool0`, formatted APFS and mounted at `/Volumes/Photos` |
| Network | Existing `br-core` bridge on VLAN 642, with a stable MAC address and DHCP reservation |
| Display | VMware virtual display at 1280x800 through the Incus graphical console |
| Firmware | Existing pinned 2025.05 OVMF build, with VM firmware Secure Boot disabled |

- Recheck Apple's current stable macOS release immediately before building the installer. Use the latest release that still boots on Intel, record the installed version and build number, and do not use beta software or silently fall back to an older major release.
- Base the OpenCore configuration, Tahoe CPU flags, and Apple Recovery flow on pinned revisions of `kholia/OSX-KVM`. Record source revisions and hashes for all imported boot artifacts.
- Present a Skylake-compatible Intel CPU with `GenuineIntel`, invariant TSC, and the features required by current macOS.
- Generate the VM's Mac identity exactly once during initialization. The identity consists of the product model, serial number, MLB, System UUID, ROM, network MAC, and NVRAM; use a Tahoe-supported Intel model such as `MacPro7,1`. Use a unique Apple-OUI MAC and derive ROM from the same six bytes without separators.
- Store the generated identity in the VM-specific OpenCore EFI and persistent NVRAM. Incus restarts, Nix rebuilds, and boot-artifact reconciliation must preserve it and must never invoke identity generation again.
- Treat the identity as part of the VM's durable state and recovery material. Back it up with the EFI and NVRAM metadata, keep it out of Git and the Nix store, and verify the same values after every restart test.
- Never run two VMs with the same identity. If `hackintosh` is cloned, generate a fresh identity for the clone before its first network boot while leaving the original identity unchanged.
- Adapt the pinned `macOS-on-Incus/QEMU-Scriptlet` device-remapping approach for this VM. Replace Incus's hot-plugged disks with static VirtIO block devices before macOS boots, expose a macOS-compatible VMXNET3 network device while retaining the Incus bridge, MAC address, and VLAN, and provide USB keyboard and tablet input.
- Preserve Incus management of storage, networking, QMP, and SPICE. Do not add GPU passthrough in this phase.
- Install OpenCore into the system disk's EFI partition after macOS installation. Remove the temporary Recovery and boot media, then verify that the VM boots from the system disk alone.
- Track the latest stable OpenCore release from `acidanthera/OpenCorePkg`. Preserve the personalized configuration, kext set, and identity when replacing OpenCore and its enabled bundled drivers, then validate the result with the matching `ocvalidate`.
- Register the instance in the existing `virtualisation.incusVms` inventory. Retain `last-state` as the default `boot.autostart` value and override it to `true` for `hackintosh` through the existing instance configuration map.
- Never reboot `el2` as part of Hackintosh deployment, validation, or maintenance. Verify the declarative autostart configuration without exercising a host reboot.
- Keep the host's current `kvm.ignore_msrs=0` setting unless an observed boot failure specifically requires changing it. Any host-wide KVM change must be tied to that failure and retested against existing VMs.

## Guest Nix Environment

- Add `darwinConfigurations.Hackintosh` with `x86_64-darwin` as its host platform. Keep the existing Apple Silicon configurations on `aarch64-darwin`.
- Build a small Hackintosh-specific nix-darwin composition that shares the existing shell, Git, SSH, tmux, editor, and basic command-line configuration. Do not enable the normal Homebrew desktop application set, Cemu, Whisper, Mutagen synchronization, or unrelated personal services.
- Include the tools needed to administer the guest and its repository: `just`, `nh`, Git, Neovim, curl, jq, ripgrep, and fzf. Ensure Neovim is installed through Nix because the shared shell configuration aliases `vi` and `vim` to `nvim`.
- Extend flake platform generation only as far as required for the Hackintosh configuration and its packages. Handle packages unavailable on Intel Darwin explicitly, without adding `x86_64-darwin` to the full CI build matrix.
- After creating user `yifan`, install upstream multi-user Nix because Determinate no longer publishes `x86_64-darwin` installers. Place the repository, including the implementation of this plan and the existing lock file, at `/Users/yifan/nix`. Obtain `just` through a temporary Nix invocation for the first activation, then run `just darwin` as `yifan`.
- Allow initial activation without the private secrets submodule. Do not put the login password, Apple Account credentials, or generated Mac identity in Git or the Nix store. Continue generating `username.nix` through the existing Just recipe.
- Update `just check-all` so its Darwin architecture selection understands Intel macOS. Verify that `just check` and repeated `just darwin` activations work from the guest repository.

## Photos-Specific Optimization and Unattended Operation

Optimize for a continuously running Photos workload with software-rendered display output:

- Enable Reduce Motion and Reduce Transparency, disable Dock magnification and launch animations, use a static wallpaper, disable the screen saver, and retain the 1280x800 display resolution.
- Prevent system sleep and automatic logout. Configure `yifan` for automatic login, but open Photos manually rather than through a login agent. Keep FileVault disabled because it conflicts with unattended login after boot.
- Disable Siri and unrelated login items. Exclude `/nix` from Spotlight indexing, while retaining Spotlight, Photos analysis, media indexing, and iCloud background services for the Photos library.
- Do not apply the OSX-PROXMOX optimization list wholesale. In particular, do not initially force-disable Metal, OpenGL, Core Image, image verification, crash reporting, or software updates. Test any additional setting individually, retain it only when it measurably reduces load without breaking Photos, and express retained settings in the Hackintosh-specific nix-darwin configuration.
- Enable SSH key authentication. Provide authenticated VNC access to the Incus graphical console over the existing private network or VPN path; do not depend on guest Screen Sharing if the unaccelerated virtual display cannot produce usable frames. Keep software-update checks enabled, but install major and minor macOS updates manually during a maintenance window after taking a stopped Incus snapshot.
- Document the few interactive initialization steps: macOS installation, local user creation, automatic login, Apple privacy prompts, and any permissions required for remote administration. Avoid building a general-purpose installer or service framework for these one-time operations.

## Validation and Acceptance Criteria

- Run `just fmt` and `just check` on the host repository. Evaluate the new Intel Darwin configuration and build it in the macOS guest before activation.
- Install the latest verified Intel-compatible stable macOS version. Confirm hostname `Hackintosh`, user `yifan`, persistent OpenCore identity, correct clock behavior, network access, and cold boot without installation media.
- Import representative JPEG, HEIC, and short video files into a new System Photo Library. Confirm that Photos displays them correctly and that exporting unmodified originals produces files with matching hashes.
- Record idle CPU and memory use and sample import time after initial indexing settles with the selected UI optimizations active. Remove any optimization that causes visual corruption, failed imports, broken exports, or persistent Photos errors.
- Close the graphical console and confirm the guest continues to run. Test a normal macOS restart and an Incus stop/start cycle. In each case, verify automatic login, SSH availability, library persistence, and unchanged Mac identity. Do not reboot `el2` for this validation.
- From `/Users/yifan/nix`, verify `just check`, `just darwin`, and a fresh SSH shell using the shared command-line environment.
- Connect through the private VNC endpoint with authentication and verify both current display output and keyboard or pointer input. Confirm that unauthenticated VNC is rejected.
- Confirm the separate 2 TiB data disk uses GPT and APFS, mounts automatically at `/Volumes/Photos`, and is writable by `yifan`. Treat its snapshots and backups independently from the VM system disk.
- Create a stopped baseline snapshot after acceptance and record the installed macOS build, OpenCore and source revisions, artifact hashes, retained optimizations, and recovery procedure.
- Do not claim iCloud compatibility or backup completeness in this phase. The next phase must separately validate Apple Account login, two-factor authentication, moving the System Photo Library to the data disk, Download Originals behavior, deletion propagation, and an independent versioned backup of the Photos library or exported originals.

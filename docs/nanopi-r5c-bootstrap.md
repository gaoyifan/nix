# NanoPi R5C bootstrap

The R5C has two images. The normal bootstrap image runs from a TF card or eMMC.
The dedicated TF-to-eMMC image boots from a TF card with SSH available and
leaves eMMC untouched until an explicit command writes the normal image there.
It verifies every byte and powers off on success. Booting the TF card again
does not start another write.

Both images contain no agenix secrets, production network settings, or SSH
private key. Root has an empty password for local console login; SSH accepts
only this repository's authorized keys. The board generates its own SSH host
key on first boot. The serial console uses 1500000 baud.

## Network

Both the normal bootstrap and eMMC writer use DHCP on WAN. For direct access,
connect a workstation to LAN and set its address below. To use WAN, connect it
to a network with a DHCP server and look up its lease.

| R5C port | R5C address | Workstation/network |
| --- | --- | --- |
| WAN (`wan0`) | IPv4 DHCP | DHCP-enabled network |
| LAN (`lan1`) | `198.51.100.254/24` | `198.51.100.1/24` |

The names follow the R5C PCI paths from
[`bdew/nixos-nanopi`](https://github.com/bdew/nixos-nanopi/blob/master/models/r5c.nix).
Confirm the physical port mapping on the board before using it as a router.

## Prepare a TF card

Build one of the images:

```console
just build-nanopi-bootstrap-image r5c
just build-nanopi-r5c-emmc-flasher-image
```

Use a TF card of at least 8 GB for the eMMC writer. Each command leaves a
`result` symlink. Flash the `.img.zst` inside its
`sd-image/` directory to the entire TF device, not a partition. For example:

```console
zstd -dc result/sd-image/nanopi-r5c-bootstrap.img.zst | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
```

Use `nanopi-r5c-emmc-flasher.img.zst` instead when preparing the eMMC writer.
Replace `/dev/sdX` with the actual TF card device.

Boot the writer TF card, connect over SSH as `root` at `198.51.100.254` on LAN
or at its DHCP address on WAN, and inspect the eMMC before starting the write:

```console
lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS
systemctl start flash-nanopi-r5c-emmc.service
```

This command erases the existing eMMC system. The writer checks that it booted
from TF and that the target is the only detected eMMC, is not the root disk,
has no mounted or swap partitions, and has enough capacity. After a successful
write and full readback checksum, it powers off; the SSH connection may close
at that point. Remove the TF card, then power on again to start the normal
bootstrap from eMMC. Leaving the TF card inserted can boot the writer again
even without pressing MASK. On failure it remains on; inspect the serial
console or `journalctl -u flash-nanopi-r5c-emmc.service` over SSH before
retrying. Do not remove power while it writes.

The writer and the installed bootstrap have distinct disk and filesystem
identifiers, so the TF and eMMC can safely coexist during the installation.
If the board starts its existing eMMC system instead of the writer TF card,
leave the card inserted, power off, hold MASK while powering on, and release
MASK after about four seconds. Check the DHCP lease for hostname
`nanopi-r5c-emmc-flasher` before starting the service. This follows
[FriendlyELEC's boot-priority guidance](https://wiki.friendlyelec.com/wiki/index.php/Template:RockchipBootPriority/zh).

## Enroll and deploy

After the normal bootstrap starts from TF or eMMC, read its newly generated
SSH host public key. Replace `TARGET` with the final NixOS hostname:

```console
target=TARGET
ssh root@198.51.100.254 cat /etc/ssh/ssh_host_ed25519_key.pub \
  | awk -v comment="root@$target" '{ print $1, $2, comment }'
```

Replace the target host key in `secrets/files/secrets.nix`, then run
`just rekey`. The private key stays on the device. Deploy a target profile
that imports `nixos/optional/nanopi-r5c.nix` with:

```console
just deploy-nanopi-from-bootstrap TARGET
```

The command stages the next generation for boot without changing the current
network session. Reboot only after deployment succeeds, following the
repository's per-host reboot approval rule.

---
name: resize-incus-vm-root-disk
description: Expand the root disk of a declaratively managed Incus KVM virtual machine and verify that the guest filesystem grew. Use when an Incus KVM VM needs more root-disk capacity.
---

# Resize an Incus KVM root disk

The Debian guests grow their root partition and ext4 filesystem during boot. Only expand disks; Incus block volumes cannot shrink. Update the declaration before the runtime configuration to avoid drift.

1. Check the current capacity and host free space:

   ```sh
   incus config device get <vm> root size
   incus exec <vm> -- lsblk
   incus exec <vm> -- df -hT /
   df -h /var/lib/incus
   ```

2. Locate the VM's declarative definition, set `devices.root.size`, then apply the configuration:

   ```sh
   just fmt
   just check
   just
   incus config device get <vm> root size
   incus restart <vm> --timeout 120
   ```

3. Verify the Incus configuration, guest disk, root filesystem, and VM state:

   ```sh
   incus config device get <vm> root size
   incus exec <vm> -- lsblk
   incus exec <vm> -- df -hT /
   incus info <vm>
   ```

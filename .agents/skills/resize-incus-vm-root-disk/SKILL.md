---
name: resize-incus-vm-root-disk
description: Resize the root disk of an Incus KVM virtual machine and verify that the guest filesystem grew. Use when an Incus KVM VM needs more root-disk capacity.
---

# Resize an Incus KVM root disk

The Debian guests in this project grow their root partition and ext4 filesystem during boot.

1. Check the current capacity and host free space:

   ```sh
   incus config device get <vm> root size
   incus exec <vm> -- lsblk
   incus exec <vm> -- df -hT /
   df -h /var/lib/incus
   ```

2. Set an explicit target such as `500GiB`, then restart the VM:

   ```sh
   incus config device set <vm> root size=<target>
   incus restart <vm> --timeout 120
   ```

3. Verify the Incus configuration, guest disk, root filesystem, and VM state:

   ```sh
   incus config device get <vm> root size
   incus exec <vm> -- lsblk
   incus exec <vm> -- df -hT /
   incus info <vm>
   ```

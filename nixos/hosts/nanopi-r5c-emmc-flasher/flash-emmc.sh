#!/usr/bin/env bash
set -euo pipefail

image="$1"
image_size="$2"
expected_sha256="$3"
sys_block="${SYS_BLOCK_DIR:-/sys/block}"
device_dir="${DEVICE_DIR:-/dev}"

emmc_devices=()
for entry in "$sys_block"/mmcblk*; do
  if [ -f "$entry/device/type" ] && [ "$(cat "$entry/device/type")" = MMC ]; then
    emmc_devices+=("$device_dir/$(basename "$entry")")
  fi
done

if [ "${#emmc_devices[@]}" -ne 1 ]; then
  echo "Expected exactly one eMMC device; found ${#emmc_devices[@]}" >&2
  exit 1
fi
target="${emmc_devices[0]}"

root_source="$(findmnt -n -o SOURCE /)"
# Btrfs reports a mounted subvolume as /dev/mmcblkNpM[/path].
root_source="$(readlink -f "${root_source%%\[*}")"
root_parent="$(lsblk -ndo PKNAME "$root_source")"
root_name="${root_parent:-$(basename "$root_source")}"

if [ ! -f "$sys_block/$root_name/device/type" ] ||
  [ "$(cat "$sys_block/$root_name/device/type")" != SD ]; then
  echo "Refusing to flash: current root is not on a TF card" >&2
  exit 1
fi

if [ ! -b "$target" ]; then
  echo "eMMC target $target is not a block device" >&2
  exit 1
fi
if [ "$(blockdev --getro "$target")" != 0 ]; then
  echo "eMMC target $target is read-only" >&2
  exit 1
fi
if lsblk -nr -o MOUNTPOINTS "$target" | grep -q '[^[:space:]]'; then
  echo "eMMC target $target has mounted or swap partitions" >&2
  exit 1
fi
if [ "$(blockdev --getsize64 "$target")" -lt "$image_size" ]; then
  echo "eMMC target $target is smaller than the bootstrap image" >&2
  exit 1
fi

echo "Writing $image_size bytes from $image to $target"
wipefs --all "$target"
zstd -dc "$image" | dd of="$target" bs=4M conv=fsync status=progress
blockdev --flushbufs "$target"
actual_sha256="$(head -c "$image_size" "$target" | sha256sum | cut -d' ' -f1)"
if [ "$actual_sha256" != "$expected_sha256" ]; then
  echo "eMMC readback checksum mismatch: $actual_sha256" >&2
  exit 1
fi

echo "eMMC readback verified; shutting down. Remove the TF card before powering on."
systemctl --no-block poweroff

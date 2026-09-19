#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Run this test as root; it uses a temporary loop device." >&2
  exit 1
fi

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
test_dir="$(mktemp -d)"
loop_device=""
cleanup() {
  if [ -n "$loop_device" ]; then
    umount "$test_dir/mnt" 2>/dev/null || true
    losetup -d "$loop_device"
  fi
  rm -rf "$test_dir"
}
trap cleanup EXIT

mkdir -p "$test_dir/sys/mmcblk9/device" "$test_dir/dev" "$test_dir/bin" "$test_dir/mnt"
truncate -s 64M "$test_dir/emmc.img"
loop_device="$(losetup --find --show "$test_dir/emmc.img")"
ln -s "$loop_device" "$test_dir/dev/mmcblk9"
printf MMC >"$test_dir/sys/mmcblk9/device/type"

root_source="$(findmnt -n -o SOURCE /)"
root_source="$(readlink -f "${root_source%%\[*}")"
root_parent="$(lsblk -ndo PKNAME "$root_source")"
root_name="${root_parent:-$(basename "$root_source")}"
mkdir -p "$test_dir/sys/$root_name/device"
printf SD >"$test_dir/sys/$root_name/device/type"

printf '#!/bin/sh\ntouch %s/poweroff\n' "$test_dir" >"$test_dir/bin/systemctl"
chmod +x "$test_dir/bin/systemctl"
printf 'NanoPi R5C test image' >"$test_dir/source.img"
truncate -s 2M "$test_dir/source.img"
zstd -q "$test_dir/source.img" -o "$test_dir/source.img.zst"
image_size="$(stat -c %s "$test_dir/source.img")"
image_sha256="$(sha256sum "$test_dir/source.img" | cut -d' ' -f1)"

flash() {
  SYS_BLOCK_DIR="$test_dir/sys" DEVICE_DIR="$test_dir/dev" PATH="$test_dir/bin:$PATH" \
    bash "$repo_root/nixos/hosts/nanopi-r5c-emmc-flasher/flash-emmc.sh" \
    "$test_dir/source.img.zst" "$1" "$2"
}

reject() {
  local output
  if output="$(flash "$1" "$2" 2>&1)"; then
    echo "Unexpected successful flash: $output" >&2
    exit 1
  fi
  if [[ $output != *"$3"* ]]; then
    echo "Expected '$3', got: $output" >&2
    exit 1
  fi
  test ! -e "$test_dir/poweroff"
}

rm "$test_dir/sys/$root_name/device/type"
reject "$image_size" "$image_sha256" "current root is not on a TF card"
printf SD >"$test_dir/sys/$root_name/device/type"

rm "$test_dir/sys/mmcblk9/device/type"
reject "$image_size" "$image_sha256" "Expected exactly one eMMC device; found 0"
printf MMC >"$test_dir/sys/mmcblk9/device/type"
mkdir -p "$test_dir/sys/mmcblk8/device"
printf MMC >"$test_dir/sys/mmcblk8/device/type"
reject "$image_size" "$image_sha256" "Expected exactly one eMMC device; found 2"
rm -r "$test_dir/sys/mmcblk8"

reject 100000000 "$image_sha256" "smaller than the bootstrap image"
mkfs.ext4 -F -q "$loop_device"
mount "$loop_device" "$test_dir/mnt"
reject "$image_size" "$image_sha256" "mounted or swap partitions"
umount "$test_dir/mnt"

reject "$image_size" "$(printf '%064d' 0)" "readback checksum mismatch"
flash "$image_size" "$image_sha256"
test -e "$test_dir/poweroff"
cmp -n "$image_size" "$test_dir/source.img" "$loop_device"
echo "NanoPi R5C eMMC flash checks passed"

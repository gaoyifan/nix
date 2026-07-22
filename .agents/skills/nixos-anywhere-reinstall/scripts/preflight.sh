#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 user@host" >&2
  exit 2
fi

ssh -o BatchMode=yes -o ConnectTimeout=10 "$1" 'sh -s' <<'REMOTE'
set -eu
printf 'HOSTNAME='; hostname
printf 'OS='; . /etc/os-release; printf '%s %s\n' "$ID" "$VERSION_ID"
printf 'ARCH='; uname -m
printf 'KERNEL='; uname -r
printf 'VIRT='; systemd-detect-virt || true
printf 'DMI_PRODUCT='; cat /sys/class/dmi/id/product_name 2>/dev/null || echo unavailable
printf 'DMI_BOARD='; cat /sys/class/dmi/id/board_name 2>/dev/null || echo unavailable
printf 'DMI_BIOS='; cat /sys/class/dmi/id/bios_version 2>/dev/null || echo unavailable
printf 'BOOT_MODE='; if [ -d /sys/firmware/efi ]; then echo UEFI; else echo BIOS; fi
printf 'CPU\n'; lscpu
printf 'MEMORY\n'; free -h
printf 'SYSTEM_RAM_RANGES\n'; sed -n '/System RAM/p' /proc/iomem
printf 'ZRAM\n'; zramctl || true
printf 'ROOT\n'; findmnt -n -o SOURCE,FSTYPE,OPTIONS /
printf 'BLOCK_DEVICES\n'; lsblk -b -O -J
printf 'BY_ID\n'; find /dev/disk/by-id -maxdepth 1 -type l -printf '%f -> %l\n' 2>/dev/null | sort
printf 'MOUNTS\n'; findmnt -R /
printf 'SWAP\n'; swapon --show --bytes || true
printf 'IP_ADDR\n'; ip -json addr
printf 'IP_ROUTE4\n'; ip -json -4 route
printf 'IP_ROUTE6\n'; ip -json -6 route
printf 'DNS\n'; sed -n '1,80p' /etc/resolv.conf
printf 'SSH_HOST_KEYS\n'; for key in /etc/ssh/ssh_host_*_key.pub; do
  [ -e "$key" ] || continue
  ssh-keygen -lf "$key" 2>/dev/null || printf 'invalid=%s\n' "$key"
done
printf 'AUTHORIZED_KEY_FINGERPRINTS\n'
for authorized_keys in /root/.ssh/authorized_keys /etc/ssh/authorized_keys.d/root; do
  [ -f "$authorized_keys" ] || continue
  printf 'FILE=%s\n' "$authorized_keys"
  ssh-keygen -lf "$authorized_keys" || true
done
printf 'KEXEC_BIN='; command -v kexec || echo unavailable
printf 'KEXEC_LOAD_DISABLED='; cat /proc/sys/kernel/kexec_load_disabled 2>/dev/null || echo unavailable
printf 'KEXEC_LOADED='; if [ -e /sys/kernel/kexec_loaded ]; then cat /sys/kernel/kexec_loaded; else echo unavailable; fi
REMOTE

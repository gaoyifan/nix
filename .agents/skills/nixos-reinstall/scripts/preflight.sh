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
printf 'BOOT_MODE='; if [ -d /sys/firmware/efi ]; then echo UEFI; else echo BIOS; fi
printf 'MEMORY\n'; free -h
printf 'ROOT\n'; findmnt -n -o SOURCE,FSTYPE,OPTIONS /
printf 'BLOCK_DEVICES\n'; lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS
printf 'BY_ID\n'; find /dev/disk/by-id -maxdepth 1 -type l -printf '%f -> %l\n' 2>/dev/null | sort
printf 'IP_ADDR\n'; ip -json addr
printf 'IP_ROUTE4\n'; ip -json -4 route
printf 'IP_ROUTE6\n'; ip -json -6 route
printf 'DNS\n'; sed -n '1,80p' /etc/resolv.conf
REMOTE

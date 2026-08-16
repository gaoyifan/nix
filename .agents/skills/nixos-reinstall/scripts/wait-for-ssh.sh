#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 1 ]]; then
  mode=up
  target=$1
elif [[ $# -eq 2 && $1 == --down ]]; then
  mode=down
  target=$2
else
  echo "usage: $0 [--down] user@host" >&2
  exit 2
fi

deadline=$((SECONDS + 300))
if [[ $mode == down ]]; then
  while ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=accept-new \
    "$target" true >/dev/null 2>&1; do
    if ((SECONDS >= deadline)); then
      echo "SSH did not stop within 300 seconds: $target" >&2
      exit 1
    fi
    sleep 5
  done
else
  until ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=accept-new \
    "$target" true >/dev/null 2>&1; do
    if ((SECONDS >= deadline)); then
      echo "SSH did not become ready within 300 seconds: $target" >&2
      exit 1
    fi
    sleep 5
  done
fi

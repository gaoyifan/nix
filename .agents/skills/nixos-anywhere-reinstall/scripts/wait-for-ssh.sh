#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 user@host" >&2
  exit 2
fi

deadline=$((SECONDS + 300))
until ssh \
  -o BatchMode=yes \
  -o ConnectTimeout=5 \
  -o StrictHostKeyChecking=accept-new \
  "$1" true; do
  if ((SECONDS >= deadline)); then
    echo "SSH did not become ready within 300 seconds: $1" >&2
    exit 1
  fi
  sleep 5
done

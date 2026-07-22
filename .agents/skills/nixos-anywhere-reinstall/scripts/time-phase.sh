#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 || $3 != -- ]]; then
  echo "usage: $0 TIMINGS_FILE PHASE -- COMMAND [ARG ...]" >&2
  exit 2
fi

timings_file=$1
phase=$2
shift 3

if [[ ! -e $timings_file ]]; then
  printf 'phase\tstarted_at\tseconds\texit_code\n' >"$timings_file"
fi

started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
started_seconds=$(date +%s)

set +e
"$@"
exit_code=$?
set -e

elapsed_seconds=$(($(date +%s) - started_seconds))
printf '%s\t%s\t%d\t%d\n' \
  "$phase" "$started_at" "$elapsed_seconds" "$exit_code" \
  | tee -a "$timings_file"

exit "$exit_code"

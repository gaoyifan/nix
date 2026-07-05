{
  lib,
  pkgs,
  ...
}: let
  ksmTune = pkgs.writeShellScriptBin "ksm-tune" ''
    set -eu

    export PATH=${lib.makeBinPath [pkgs.coreutils pkgs.gawk]}''${PATH:+:$PATH}

    ksm_dir=/sys/kernel/mm/ksm
    monitor_interval=60
    npages_boost=300
    npages_decay=-50
    npages_min=64
    npages_max=1250
    sleep_millisecs_for_16gib=100
    threshold_percent=20
    threshold_const_kib=2048
    npages=0

    [ -d "$ksm_dir" ] || exit 0

    stop_ksm() {
      echo 0 > "$ksm_dir/run"
    }

    start_ksm() {
      echo "$1" > "$ksm_dir/pages_to_scan"
      echo "$2" > "$ksm_dir/sleep_millisecs"
      echo 1 > "$ksm_dir/run"
    }

    if [ "''${1:-}" = "--stop" ]; then
      stop_ksm
      exit 0
    fi

    committed_qemu_memory() {
      total=0

      for proc in /proc/[0-9]*; do
        [ -r "$proc/comm" ] || continue
        comm=$(cat "$proc/comm")

        case "$comm" in
          .qemu-system-x8 | qemu-system-x86 | kvm) ;;
          *) continue ;;
        esac

        if [ -r "$proc/smaps_rollup" ]; then
          pss=$(awk '/^Pss:/ {print $2}' "$proc/smaps_rollup")
        else
          pss=$(awk '/^VmRSS:/ {print $2}' "$proc/status" 2>/dev/null || echo 0)
        fi

        total=$((total + ''${pss:-0}))
      done

      echo "$total"
    }

    free_memory() {
      awk '/^(MemFree|Buffers|Cached):/ {free += $2} END {printf "%.0f", free}' /proc/meminfo
    }

    increase_npages() {
      npages=$((npages + $1))

      if [ "$npages" -lt "$npages_min" ]; then
        npages=$npages_min
      elif [ "$npages" -gt "$npages_max" ]; then
        npages=$npages_max
      fi
    }

    adjust() {
      total_kib=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
      scan_sleep=$((sleep_millisecs_for_16gib * 16 * 1024 * 1024 / total_kib))
      [ "$scan_sleep" -le 10 ] && scan_sleep=10

      threshold_kib=$((total_kib * threshold_percent / 100))
      if [ "$threshold_const_kib" -gt "$threshold_kib" ]; then
        threshold_kib=$threshold_const_kib
      fi

      free_kib=$(free_memory)
      committed_kib=$(committed_qemu_memory)

      if [ "$((committed_kib + threshold_kib))" -lt "$total_kib" ] && [ "$free_kib" -gt "$threshold_kib" ]; then
        stop_ksm
        return
      fi

      if [ "$free_kib" -lt "$threshold_kib" ]; then
        increase_npages "$npages_boost"
      else
        increase_npages "$npages_decay"
      fi

      start_ksm "$npages" "$scan_sleep"
    }

    sleep_pid=

    interrupt_sleep() {
      if [ -n "''${sleep_pid:-}" ]; then
        kill "$sleep_pid" 2>/dev/null || true
      fi
    }

    stop_service() {
      interrupt_sleep
      stop_ksm
      exit 0
    }

    trap stop_service INT TERM
    trap interrupt_sleep USR1

    while true; do
      adjust
      sleep "$monitor_interval" &
      sleep_pid=$!
      wait "$sleep_pid" || true
      sleep_pid=
    done
  '';
in {
  systemd.services.ksm = {
    description = "Kernel Samepage Merging tuner";
    wantedBy = ["multi-user.target"];
    unitConfig.ConditionPathExists = "/sys/kernel/mm/ksm/run";

    serviceConfig = {
      Type = "simple";
      ExecStart = "${ksmTune}/bin/ksm-tune";
      ExecStop = "${ksmTune}/bin/ksm-tune --stop";
    };
  };
}

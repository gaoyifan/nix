{
  hardware.ksm = {
    enable = true;
    sleep = 20;
  };

  systemd.tmpfiles.rules = [
    "w /sys/kernel/mm/ksm/advisor_max_cpu - - - - 20"
    "w /sys/kernel/mm/ksm/advisor_target_scan_time - - - - 300"
    "w /sys/kernel/mm/ksm/advisor_min_pages_to_scan - - - - 500"
    "w /sys/kernel/mm/ksm/advisor_max_pages_to_scan - - - - 10000"
    "w /sys/kernel/mm/ksm/smart_scan - - - - 1"
    "w /sys/kernel/mm/ksm/advisor_mode - - - - scan-time"
  ];
}

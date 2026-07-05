# bees block-level deduplication for the root btrfs filesystem: VM images
# and container layers on this host share a lot of identical blocks.
{...}: {
  services.beesd.filesystems.root = {
    spec = "/";
    # 1GB hash table indexes ~1TB of unique data at 16KB extent granularity,
    # matching the ~900GB device.
    hashTableSizeMB = 1024;
    # info logs every dedup action; keep the journal quiet.
    verbosity = "warning";
    # Back off when the always-on VMs and containers need the CPU.
    extraOptions = ["--loadavg-target" "5.0" "--thread-count" "2"];
  };
}

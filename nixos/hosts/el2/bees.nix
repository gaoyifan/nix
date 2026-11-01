# Deduplicate the Nix store on the root btrfs filesystem.
{...}: {
  services.beesd.filesystems.root = {
    spec = "/";
    # Index the ~223 GiB volume at 4 KiB extent granularity.
    hashTableSizeMB = 1024;
    verbosity = "warning";
    # Leave capacity for routing, services, and VMs on this 40-thread host.
    extraOptions = ["--loadavg-target" "20.0" "--thread-count" "2"];
  };
}

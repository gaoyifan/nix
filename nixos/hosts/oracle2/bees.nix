# Deduplicate the host and runner stores on the same root btrfs filesystem.
{...}: {
  services.beesd.filesystems.root = {
    spec = "/";
    # Sized for the 200 GiB volume.
    hashTableSizeMB = 256;
    verbosity = "warning";
    # Leave capacity for services and pause workers during busy CI builds.
    extraOptions = ["--loadavg-target" "3.0" "--thread-count" "1"];
  };
}

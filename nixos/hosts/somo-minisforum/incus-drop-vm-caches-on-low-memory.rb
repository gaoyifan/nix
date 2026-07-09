require "json"

INCUS = ENV.fetch("INCUS")
STAMP = "/run/incus-drop-vm-caches.last"
COOLDOWN = 3600
THRESHOLD_PERCENT = 10

def meminfo
  File.read("/proc/meminfo").each_line.to_h do |line|
    key, value = line.split(":", 2)
    [key, value.to_i]
  end
end

exit 0 if File.exist?(STAMP) && File.mtime(STAMP) > Time.now - COOLDOWN

mem = meminfo
exit 0 unless mem.fetch("MemAvailable") * 100 < mem.fetch("MemTotal") * THRESHOLD_PERCENT

File.write(STAMP, "")

JSON.parse(IO.popen([INCUS, "list", "-f", "json"], &:read)).each do |vm|
  next unless vm.fetch("status") == "Running"
  next unless vm.fetch("type") == "virtual-machine"

  name = vm.fetch("name")
  puts "Dropping guest caches: #{name}"
  system(INCUS, "exec", name, "--", "sh", "-c", "sync; echo 3 > /proc/sys/vm/drop_caches", exception: false)
end

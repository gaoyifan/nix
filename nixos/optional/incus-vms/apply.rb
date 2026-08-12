require "json"
require "open3"

INCUS = ENV.fetch("INCUS")
VM_SPEC = ENV.fetch("VM_SPEC")

def incus(*args)
  out, status = Open3.capture2e(INCUS, *args)
  raise out unless status.success?

  out
end

def instances
  JSON.parse(incus("list", "-f", "json")).to_h { |vm| [vm.fetch("name"), vm] }
end

def instance_devices(name)
  state = JSON.parse(incus("query", "/1.0/instances/#{name}"))
  state.fetch("devices", {})
end

def apply_profile(profile)
  name = profile.fetch("name")
  desired = {
    "config" => profile.fetch("config"),
    "description" => profile.fetch("description", ""),
    "devices" => profile.fetch("devices")
  }
  current = JSON.parse(incus("query", "/1.0/profiles/#{name}"))
  current = desired.keys.to_h { |key| [key, current[key]] }
  return if current == desired

  incus("query", "-X", "PUT", "-d", JSON.generate(desired), "/1.0/profiles/#{name}")
end

def apply(spec, state)
  failed = []

  spec.each do |name, vm|
    puts "Applying instance config: #{name}"

    begin
      unless state[name]
        image = vm["image"]
        raise "instance is missing and no image is declared" unless image

        puts "Creating virtual machine #{name} from images:#{image}"
        incus("init", "images:#{image}", name, "--vm")
        state = instances
      end

      current = state.fetch(name)
      profile = vm.fetch("profile")
      apply_profile(profile)
      profile_name = profile.fetch("name")
      incus("profile", "assign", name, profile_name) unless current.fetch("profiles", []) == [profile_name]

      profile.fetch("config").each_key do |key|
        incus("config", "unset", name, key) if current.fetch("config", {}).key?(key)
      end

      local_devices = instance_devices(name)
      profile.fetch("devices").each_key do |device_name|
        incus("config", "device", "remove", name, device_name) if local_devices.key?(device_name)
      end
    rescue => e
      warn "#{name}: #{e.message}"
      failed << name
    end
  end

  failed
end

systemd = ARGV.delete("--systemd")
spec = JSON.parse(File.read(VM_SPEC))

incus("info")

failed = apply(spec, instances)
exit 0 if failed.empty?

warn "Failed to apply complete VM config: #{failed.join(" ")}"
exit 1 if systemd

print "Stop and restart all pending VMs now? [y/N] "
exit 1 unless STDIN.gets&.strip&.match?(/\A(?:y|yes)\z/i)

failed = failed.filter do |name|
  current = instances[name]
  incus("stop", name, "--timeout", "60") if current && current["status"] != "Stopped"
  next true unless apply(spec.slice(name), instances).empty?

  incus("start", name)
  false
end

abort "Still failed: #{failed.join(" ")}" unless failed.empty?

require "json"
require "open3"

INCUS = ENV.fetch("INCUS")
IMAGE_REMOTE = ENV.fetch("IMAGE_REMOTE")
IMAGE_REMOTE_URL = ENV.fetch("IMAGE_REMOTE_URL")
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

        remotes = JSON.parse(incus("remote", "list", "-f", "json"))
        unless remotes.key?(IMAGE_REMOTE)
          incus("remote", "add", IMAGE_REMOTE, IMAGE_REMOTE_URL, "--protocol=simplestreams", "--public")
        end

        puts "Creating virtual machine #{name} from #{IMAGE_REMOTE}:#{image}"
        incus("init", "#{IMAGE_REMOTE}:#{image}", name, "--vm")
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

    # The first pass never stops a VM. Even when part of its config failed,
    # start any instance that exists so the failure does not become an
    # avoidable service outage.
    begin
      current = instances[name]
      incus("start", name) if current && current["status"] != "Running"
    rescue => e
      warn "#{name}: failed to start: #{e.message}"
      failed << name unless failed.include?(name)
    end
  end

  failed
end

restart = !ARGV.delete("--no-restart")
spec = JSON.parse(File.read(VM_SPEC))

incus("info")

failed = apply(spec, instances)
exit 0 if failed.empty?

warn "Failed to apply complete VM config: #{failed.join(" ")}"
exit 1 unless restart

print "Stop and restart all pending VMs now? [y/N] "
exit 1 unless STDIN.gets&.strip&.match?(/\A(?:y|yes)\z/i)

failed = failed.filter do |name|
  incus("stop", name, "--timeout", "60")
  !apply(spec.slice(name), instances).empty?
end

abort "Still failed: #{failed.join(" ")}" unless failed.empty?

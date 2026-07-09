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

def same?(a, b)
  a.to_s.delete_suffix("\n") == b.to_s.delete_suffix("\n")
end

def instances
  JSON.parse(incus("list", "-f", "json")).to_h { |vm| [vm.fetch("name"), vm] }
end

def apply(spec, state)
  failed = []

  spec.each do |name, vm|
    puts "Applying VM config: #{name}"

    begin
      unless state[name]
        puts "Creating VM #{name} from #{IMAGE_REMOTE}:#{vm.fetch("image")}"
        incus("init", "#{IMAGE_REMOTE}:#{vm.fetch("image")}", name, "--vm")
        state[name] = {"status" => "Stopped", "config" => {}, "devices" => {}}
      end

      current = state.fetch(name)

      vm.fetch("config").each do |key, value|
        next if same?(current.dig("config", key), value)
        incus("config", "set", name, "#{key}=#{value}")
      end

      vm.fetch("devices", {}).each do |dev, desired|
        current_devices = current.fetch("devices", {})

        unless current_devices.key?(dev)
          incus("config", "device", "override", name, dev)
          current_devices[dev] = {}
        end

        desired.each do |key, value|
          next if same?(current_devices.dig(dev, key), value)
          incus("config", "device", "set", name, dev, "#{key}=#{value}")
        end
      end

      incus("start", name) unless current["status"] == "Running"
    rescue => e
      warn "#{name}: #{e.message}"
      failed << name
    end
  end

  failed
end

restart = !ARGV.delete("--no-restart")
spec = JSON.parse(File.read(VM_SPEC))

begin
  incus("info")
rescue
  puts "Incus is not ready; skipping declarative VM setup"
  exit 0
end

unless JSON.parse(incus("remote", "list", "-f", "json")).key?(IMAGE_REMOTE)
  incus("remote", "add", IMAGE_REMOTE, IMAGE_REMOTE_URL, "--protocol=simplestreams", "--public")
end

failed = apply(spec, instances)
exit 0 if failed.empty?

puts "Pending restart to apply VM config: #{failed.join(" ")}"
exit 0 unless restart

print "Stop and restart all pending VMs now? [y/N] "
exit 0 unless STDIN.gets&.strip&.match?(/\A(?:y|yes)\z/i)

failed = failed.filter do |name|
  incus("stop", name, "--timeout", "60")
  !apply(spec.slice(name), instances).empty?
end

abort "Still failed: #{failed.join(" ")}" unless failed.empty?

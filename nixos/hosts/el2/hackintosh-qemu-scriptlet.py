# ruff: noqa: F821
"""Adapt Incus-managed QEMU devices for macOS.

The device remapping follows the approach developed by macOS-on-Incus at
commit 041550e8f2e25f085e984de8799deccae2304bc9. CPU and device choices follow
kholia/OSX-KVM at commit 4c378a4b5e0b219783683012bec680325eb40719.
"""


def replace_cpu_model():
    command = get_qemu_cmdline()
    cpu_index = -1
    for index, argument in enumerate(command):
        if argument == "-cpu":
            cpu_index = index
            break
    if cpu_index < 0:
        fail("[macOS] Incus QEMU command line has no -cpu argument")
    command[cpu_index + 1] = (
        "Skylake-Client,-hle,-rtm,kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,+ssse3,+sse4.2,+popcnt,+avx,+aes,+xsave,+xsaveopt,check"
    )
    set_qemu_cmdline(command)


def configure_devices(devices):
    command = get_qemu_cmdline()
    command.extend(
        [
            "-blockdev",
            "node-name=devzero,driver=raw,file.driver=host_device,file.filename=/dev/zero",
        ]
    )
    set_qemu_cmdline(command)

    removed = [
        'device "qemu_gpu"',
        'device "qemu_keyboard"',
        'device "qemu_tablet"',
        'device "qemu_usb"',
        'device "qemu_spice-usb1"',
        'device "qemu_spice-usb2"',
        'device "qemu_spice-usb3"',
    ] + ['device "qemu_pcie{}"'.format(index) for index in range(8, 16)]
    configuration = []
    for entry in get_qemu_conf():
        if entry["name"] in removed:
            continue
        if entry["name"] == "boot-opts":
            entry["entries"]["strict"] = "off"
        if entry["name"] == 'device "dev-qemu_serial"':
            entry["entries"].pop("addr")
            entry["entries"]["bus"] = "pcie.0"
        if entry["entries"].get("driver") == "virtio-9p-pci":
            entry["entries"].pop("addr")
            entry["entries"]["bus"] = "pcie.0"
        configuration.append(entry)

    configuration.extend(
        [
            {
                "name": 'device "apple_smc"',
                "entries": {
                    "driver": "isa-applesmc",
                    "osk": "ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc",
                },
            },
            {
                "name": 'device "macos_vga"',
                "entries": {"driver": "vmware-svga", "bus": "pcie.0"},
            },
            {
                "name": 'device "macos_usb"',
                "entries": {"driver": "qemu-xhci", "p2": "8", "p3": "8"},
            },
            {
                "name": 'device "macos_keyboard"',
                "entries": {"driver": "usb-kbd", "bus": "macos_usb.0"},
            },
            {
                "name": 'device "macos_tablet"',
                "entries": {"driver": "usb-tablet", "bus": "macos_usb.0"},
            },
        ]
    )

    for index in range(1, 4):
        configuration.append(
            {
                "name": 'device "macos_spice_usb{}"'.format(index),
                "entries": {
                    "driver": "usb-redir",
                    "chardev": "qemu_spice-usb-chardev{}".format(index),
                    "bus": "macos_usb.0",
                },
            }
        )

    configuration.append(
        {
            "name": "global",
            "entries": {
                "driver": "ICH9-LPC",
                "property": "acpi-pci-hotplug-with-bridge-support",
                "value": "off",
            },
        }
    )

    for name in sorted(
        [
            name
            for name, device in devices.items()
            if device["type"] == "disk"
            and name != "opencore"
            and device.get("source") != "agent:config"
            and (device.get("path", "") in ["", "/"])
        ],
        key=lambda name: (name != "root", name),
    ):
        configuration.append(
            {
                "name": 'device "macos_disk_{}"'.format(name),
                "comment": "macOS static VirtIO disk placeholder",
                "entries": {
                    "driver": "virtio-blk-pci",
                    "drive": "devzero",
                    "share-rw": "on",
                },
            }
        )

    set_qemu_conf(configuration)


def remap_disks():
    for block in run_command("query-block"):
        inserted = block.get("inserted")
        if not inserted:
            continue

        node = inserted.get("node-name", "")
        if not node.startswith("incus_"):
            continue

        name = node[len("incus_") :]
        if name == "opencore":
            continue

        fdset = "fdset{}".format(inserted["file"].split("/")[-1])
        direct = inserted["drv"] == "host_device"
        log_info("[macOS] Remapping disk {} to static VirtIO".format(name))
        run_qmp(
            {
                "execute": "blockdev-add",
                "arguments": {
                    "aio": "native" if direct else "threads",
                    "cache": {"direct": direct, "no-flush": False},
                    "discard": "unmap",
                    "driver": inserted["drv"],
                    "filename": inserted["file"],
                    "locking": "off",
                    "node-name": fdset,
                    "read-only": inserted["ro"],
                },
            }
        )
        qom_set(
            path="/machine/peripheral/macos_disk_{}".format(name),
            property="drive",
            value=fdset,
        )

        qdev = block["qdev"]
        if qdev.endswith("/virtio-backend"):
            qdev = qdev[:-15]
        device_del(id=qdev)


def network_file_descriptors():
    descriptors = {}
    result = run_qmp(
        {
            "execute": "human-monitor-command",
            "arguments": {"command-line": "info network"},
        }
    )["return"]
    for line in result.strip().split("\r\n"):
        if not line.startswith(" \\ "):
            continue
        netdev = line.split(":")[0][3:]
        descriptors.setdefault(netdev, [])
        if "fd=" in line:
            descriptors[netdev].append(line.split("fd=")[1])
    return descriptors


def remap_network():
    descriptors = network_file_descriptors()
    for entry in qom_list(path="/machine/peripheral"):
        if entry["type"] != "child<virtio-net-pci>":
            continue

        qdev = entry["name"]
        path = "/machine/peripheral/{}".format(qdev)
        netdev = qom_get(path=path, property="netdev")
        mac = qom_get(path=path, property="mac")
        replacement = "macos_{}".format(netdev)
        log_info("[macOS] Remapping NIC {} to vmxnet3".format(netdev))
        netdev_add(type="tap", id=replacement, fds=":".join(descriptors[netdev]))
        device_add(
            driver="vmxnet3",
            id=replacement,
            netdev=replacement,
            mac=mac,
            bus="qemu_pcie3",
        )
        run_command("set_link", name=qdev, up=False)
        device_del(id=qdev)


def qemu_hook(instance, stage):
    if stage == "config":
        replace_cpu_model()
        configure_devices(instance.expanded_devices)
    elif stage == "pre-start":
        remap_disks()
        remap_network()

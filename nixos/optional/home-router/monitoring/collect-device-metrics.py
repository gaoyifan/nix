import http.client
import ipaddress
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time


def read_socket_json(socket_path, host, path):
    connection = http.client.HTTPConnection(host, timeout=5)
    connection.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    connection.sock.settimeout(connection.timeout)
    try:
        connection.sock.connect(socket_path)
        connection.request("GET", path)
        with connection.getresponse() as response:
            if response.status != 200:
                raise http.client.HTTPException(f"{socket_path}{path}: {response.status} {response.reason}")
            return json.load(response)
    except (FileNotFoundError, ConnectionRefusedError):
        return {}
    finally:
        connection.close()


def parse_nft_counters(data):
    counters = []
    for entry in data["nftables"]:
        nft_set = entry.get("set")
        if nft_set is None:
            continue
        name = nft_set["name"]
        for element in nft_set.get("elem", []):
            element = element["elem"]
            interface, address = element["val"]["concat"]
            kind = "mac" if name.endswith("_mac") else "ip"
            address = address.lower() if kind == "mac" else str(ipaddress.ip_address(address))
            byte_count = element["counter"]["bytes"]
            # On LAN logical VLAN interfaces, netdev egress includes the 14-byte
            # Ethernet header; ingress and the layer-3 hooks count IP bytes.
            if name == "download_mac":
                byte_count -= 14 * element["counter"]["packets"]
            counters.append(
                {
                    "interface": interface,
                    "address": address,
                    "direction": "upload" if name.startswith("upload") else "download",
                    "bytes": byte_count,
                }
            )
    return counters


def read_dhcp_names(lease_file):
    try:
        leases = Path(lease_file).read_text()
    except FileNotFoundError:
        return {}
    names = {}
    for line in leases.splitlines():
        fields = line.split()
        # dnsmasq also stores an IPv6 server DUID line in the lease file.
        if len(fields) >= 4 and fields[1].count(":") == 5 and fields[3] != "*":
            names[fields[1].lower()] = fields[3]
    return names


def parse_incus_names(instances):
    names = {}
    for instance in instances:
        for key, value in instance["config"].items():
            if key.startswith("volatile.") and key.endswith(".hwaddr"):
                names[value.lower()] = instance["name"]
        for device in instance.get("expanded_devices", {}).values():
            if device.get("hwaddr"):
                names[device["hwaddr"].lower()] = instance["name"]
    return names


def parse_tailscale_peers(status):
    peers = {}
    for node in (status.get("Peer") or {}).values():
        node_id = str(node["ID"])
        name = (node.get("DNSName") or "").split(".")[0] or node.get("HostName") or node_id
        for address in node.get("TailscaleIPs") or []:
            peers[str(ipaddress.ip_address(address))] = (f"tailscale:{node_id}", name)
    return peers


def read_wireguard_names(directory):
    if directory is None:
        return {}
    return {path.read_text().strip(): path.stem for path in Path(directory).glob("?*.pub") if path.is_file()}


def parse_wireguard_peers(allowed_ips, names):
    peers = {}
    for line in allowed_ips.splitlines():
        public_key, prefixes = line.split(None, 1)
        if prefixes == "(none)":
            continue
        for prefix in prefixes.split():
            network = ipaddress.ip_network(prefix)
            if network.prefixlen == network.max_prefixlen:
                peers[str(network.network_address)] = (f"wireguard:{public_key}", names.get(public_key, public_key))
    return peers


def prometheus_labels(labels):
    def escape(value):
        return value.replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')

    return ",".join(f'{key}="{escape(value)}"' for key, value in labels.items())


def render_metrics(counters, config, dhcp_names, incus_names, tailscale_peers, wireguard_peers):
    lines = [
        "# HELP home_router_device_bytes_total IP traffic bytes observed on a LAN interface.",
        "# TYPE home_router_device_bytes_total counter",
        "# HELP home_router_device_info Device display name.",
        "# TYPE home_router_device_info gauge",
    ]
    devices = {}
    for counter in sorted(counters, key=lambda row: (row["interface"], row["address"], row["direction"])):
        interface = counter["interface"]
        address = counter["address"]
        if interface in config["lans"]:
            lan = config["lans"][interface]
            device_id = f"mac:{address}"
            name = dhcp_names.get(address) or incus_names.get(address) or address
            metric_address = ""
        else:
            lan = interface
            device_id, name = f"ip:{address}", address
            if interface == config["tailscale"]:
                device_id, name = tailscale_peers.get(address, (device_id, name))
            elif interface in config["wireguard"]:
                device_id, name = wireguard_peers[interface].get(address, (device_id, name))
            else:
                raise ValueError(f"Unconfigured layer-3 interface: {interface}")
            # Keep addresses separate so expiry/reset of one counter cannot corrupt
            # the counter history for the peer's other IPv4/IPv6 addresses.
            metric_address = address
        devices[(lan, device_id)] = name
        labels = prometheus_labels(
            {"lan": lan, "device_id": device_id, "address": metric_address, "direction": counter["direction"]}
        )
        lines.append(f"home_router_device_bytes_total{{{labels}}} {counter['bytes']}")
    for (lan, device_id), name in sorted(devices.items()):
        labels = prometheus_labels({"lan": lan, "device_id": device_id, "name": name})
        lines.append(f"home_router_device_info{{{labels}}} 1")
    return "\n".join(lines) + "\n"


def write_metrics(output_file, metrics):
    output_file = Path(output_file)
    with tempfile.NamedTemporaryFile(
        mode="w", dir=output_file.parent, prefix=".home-router-devices-", delete_on_close=False
    ) as out:
        out.write(metrics)
        out.flush()
        os.chmod(out.name, 0o644)
        os.replace(out.name, output_file)


def collect_metrics(config):
    counters = []
    if config["lans"]:
        counters.extend(
            parse_nft_counters(
                json.loads(
                    subprocess.check_output(
                        ["nft", "--json", "list", "table", "netdev", "home-router-devices"], timeout=5
                    )
                )
            )
        )
    if config["tailscale"] or config["wireguard"]:
        counters.extend(
            parse_nft_counters(
                json.loads(
                    subprocess.check_output(
                        ["nft", "--json", "list", "table", "inet", "home-router-devices"], timeout=5
                    )
                )
            )
        )
    dhcp_names = read_dhcp_names(config["leaseFile"])
    incus_names = (
        parse_incus_names(
            read_socket_json("/var/lib/incus/unix.socket", "localhost", "/1.0/instances?recursion=1").get(
                "metadata", []
            )
        )
        if config["incus"]
        else {}
    )
    tailscale_peers = (
        parse_tailscale_peers(
            read_socket_json("/run/tailscale/tailscaled.sock", "local-tailscaled.sock", "/localapi/v0/status")
        )
        if config["tailscale"]
        else {}
    )
    wireguard_names = read_wireguard_names(config["wireguardPeerNamesDirectory"]) if config["wireguard"] else {}
    wireguard_peers = {
        interface: parse_wireguard_peers(
            subprocess.check_output(["wg", "show", interface, "allowed-ips"], text=True, timeout=5),
            wireguard_names,
        )
        if Path(f"/sys/class/net/{interface}").exists()
        else {}
        for interface in config["wireguard"]
    }
    return render_metrics(counters, config, dhcp_names, incus_names, tailscale_peers, wireguard_peers)


def main():
    config_file, output_file = sys.argv[1:]
    config = json.loads(Path(config_file).read_text())
    while True:
        write_metrics(output_file, collect_metrics(config))
        time.sleep(15)


if __name__ == "__main__":
    main()

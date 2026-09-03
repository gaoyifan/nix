import os
import time
import ipaddress
import json
import httpx

PDNS_API_KEY = os.environ["PDNS_API_KEY"]
PDNS_API_URL = os.environ.get("PDNS_API_URL", "http://localhost:8081/api/v1")
TS_SOCKET = os.environ.get("TS_SOCKET", "/var/run/tailscale/tailscaled.sock")
TS_BASE_DOMAIN = os.environ.get("TS_BASE_DOMAIN", "ts.gaof.net.")
SYNC_INTERVAL = float(os.environ.get("SYNC_INTERVAL", "60"))
TAILSCALE_TTL = int(os.environ.get("TAILSCALE_TTL", "60"))

# Ensure base domain ends with a dot
if not TS_BASE_DOMAIN.endswith("."):
    TS_BASE_DOMAIN += "."


def log(msg):
    print(f"[tailscale-syncer] {msg}", flush=True)


def is_ip(value):
    try:
        ipaddress.ip_address(value)
        return True
    except ValueError:
        return False


def normalize_name(name, suffix, base):
    if not name:
        return None
    trimmed = name.rstrip(".")
    base_trimmed = base.rstrip(".")
    suffix_trimmed = suffix.rstrip(".") if suffix else ""
    if trimmed.endswith(base_trimmed):
        fqdn = f"{trimmed}."
    elif "." not in trimmed:
        # Headscale returns bare DNSName values when MagicDNS is disabled.
        fqdn = f"{trimmed}.{base_trimmed}."
    elif suffix_trimmed and trimmed.endswith(suffix_trimmed):
        relative = trimmed[: -len(suffix_trimmed)].rstrip(".")
        fqdn = f"{relative}.{base_trimmed}." if relative else f"{base_trimmed}."
    else:
        return None
    return fqdn.replace("..", ".")


def fetch_ts_nodes():
    try:
        # Use HTTPTransport for unix socket support in httpx
        transport = httpx.HTTPTransport(uds=TS_SOCKET)
        with httpx.Client(transport=transport) as client:
            # The hostname in the URL doesn't matter when using uds, but 'local-tailscaled.sock' is conventional
            res = client.get("http://local-tailscaled.sock/localapi/v0/status")
            res.raise_for_status()
            return res.json()
    except Exception as e:
        log(f"Failed to fetch Tailscale status: {e}")
        return None


def fetch_ts_netmap():
    try:
        transport = httpx.HTTPTransport(uds=TS_SOCKET)
        with httpx.Client(transport=transport) as client:
            with client.stream(
                "GET",
                "http://local-tailscaled.sock/localapi/v0/watch-ipn-bus?mask=8",
                timeout=10.0,
            ) as res:
                res.raise_for_status()
                for line in res.iter_lines():
                    if not line:
                        continue
                    notify = json.loads(line)
                    netmap = notify.get("NetMap")
                    if netmap:
                        return netmap
        log("No netmap received from watch-ipn-bus.")
        return None
    except Exception as e:
        log(f"Failed to fetch netmap via watch-ipn-bus: {e}")
        return None


def sync():
    payload = fetch_ts_nodes()
    if not payload:
        return

    suffix = payload.get("MagicDNSSuffix")
    base = TS_BASE_DOMAIN

    nodes = []
    if payload.get("Self"):
        nodes.append(payload["Self"])
    peers = payload.get("Peer") or {}
    if isinstance(peers, dict):
        nodes.extend(peers.values())

    desired_records = {}  # (name, type) -> set(values)

    for node in nodes:
        dns_name = (node.get("DNSName") or "").rstrip(".")
        ips = node.get("TailscaleIPs") or []
        if not dns_name or not ips:
            continue

        fqdn = normalize_name(dns_name, suffix, base)
        if not fqdn:
            continue

        for ip in ips:
            rtype = "AAAA" if ":" in ip else "A"
            key = (fqdn, rtype)
            if key not in desired_records:
                desired_records[key] = set()
            desired_records[key].add(ip)

    netmap = fetch_ts_netmap()
    if netmap:
        extra_records = (netmap.get("DNS") or {}).get("ExtraRecords") or []
        for record in extra_records:
            name = record.get("Name") or ""
            value = record.get("Value") or ""
            rtype = (record.get("Type") or "").upper()
            if not rtype:
                if is_ip(value):
                    rtype = "AAAA" if ":" in value else "A"
                else:
                    log(f"Skipping ExtraRecord without type: {record}")
                    continue
            fqdn = normalize_name(name, suffix, base)
            if not fqdn:
                log(f"Skipping ExtraRecord outside base zone: {record}")
                continue
            key = (fqdn, rtype)
            if key not in desired_records:
                desired_records[key] = set()
            if value:
                desired_records[key].add(value)

    headers = {"X-API-Key": PDNS_API_KEY}
    with httpx.Client(headers=headers, timeout=30.0) as client:
        # 1. Ensure Zone Exists
        zone_url = f"{PDNS_API_URL}/servers/localhost/zones/{base}"
        res = client.get(zone_url)

        current_rrsets = {}
        if res.status_code == 404:
            log(f"Zone {base} not found, creating...")
            res = client.post(
                f"{PDNS_API_URL}/servers/localhost/zones", json={"name": base, "kind": "Native", "rrsets": []}
            )
            res.raise_for_status()
        else:
            res.raise_for_status()
            # Map current records for reconciliation
            zone_data = res.json()
            managed_types = {"A", "AAAA"}
            managed_types.update({rtype for (_, rtype) in desired_records})
            for rrset in zone_data.get("rrsets", []):
                if rrset["type"] in managed_types:
                    values = {r["content"] for r in rrset["records"]}
                    current_rrsets[(rrset["name"], rrset["type"])] = values

        # 2. Plan updates
        patch_rrsets = []

        # Add/Update desired records
        for (name, rtype), ips in desired_records.items():
            if current_rrsets.get((name, rtype)) != ips:
                patch_rrsets.append(
                    {
                        "name": name,
                        "type": rtype,
                        "ttl": TAILSCALE_TTL,
                        "changetype": "REPLACE",
                        "records": [{"content": ip, "disabled": False} for ip in ips],
                    }
                )

        # Delete records no longer in Tailscale
        for name, rtype in current_rrsets:
            if (name, rtype) not in desired_records:
                patch_rrsets.append({"name": name, "type": rtype, "changetype": "DELETE"})

        if patch_rrsets:
            log(f"Reconciling {len(patch_rrsets)} RRsets in {base}")
            res = client.patch(zone_url, json={"rrsets": patch_rrsets})
            res.raise_for_status()
        else:
            log("No changes needed.")


if __name__ == "__main__":
    log(f"Started. Base Domain: {TS_BASE_DOMAIN}, Interval: {SYNC_INTERVAL}s")
    while True:
        try:
            sync()
        except Exception as e:
            log(f"Sync loop error: {e}")
            import traceback

            traceback.print_exc()
        time.sleep(SYNC_INTERVAL)

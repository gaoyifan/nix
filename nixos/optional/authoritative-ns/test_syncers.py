import importlib.util
import os
import sys
from unittest.mock import patch

import httpx


def load(name: str, path: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


os.environ["PDNS_API_KEY"] = "fixture-key"
tailscale_syncer = load("tailscale_syncer", sys.argv[1])
view_syncer = load("view_syncer", sys.argv[2])

assert tailscale_syncer.normalize_name("node.example.ts.net.", "example.ts.net", "ts.gaof.net.") == "node.ts.gaof.net."
assert (
    tailscale_syncer.normalize_name("gw-edge-01", "el2-gateway-headscale-router", "lib.gaof.net.")
    == "gw-edge-01.lib.gaof.net."
)
assert (
    tailscale_syncer.normalize_name("ring-backend.tailnet.auramont.cn.", "tailnet.auramont.cn", "kxing.gaof.net.")
    == "ring-backend.kxing.gaof.net."
)
assert tailscale_syncer.normalize_name("outside.example.net.", "example.ts.net", "ts.gaof.net.") is None


class FailingResponse:
    checked = False

    def raise_for_status(self):
        self.checked = True
        request = httpx.Request("GET", "http://127.0.0.1")
        raise httpx.HTTPStatusError("fixture", request=request, response=httpx.Response(500, request=request))


response = FailingResponse()
view_syncer.client = type("Client", (), {"get": lambda _self, _url: response})()
assert view_syncer.get_current_state() == (None, None)
assert response.checked

# A failed netmap fetch must not reconcile a partial node-only DNS snapshot.
with (
    patch.object(
        tailscale_syncer,
        "fetch_ts_nodes",
        return_value={"Self": {"DNSName": "node.ts.gaof.net", "TailscaleIPs": ["100.64.0.1"]}},
    ),
    patch.object(tailscale_syncer, "fetch_ts_netmap", return_value=None),
    patch.object(tailscale_syncer.httpx, "Client") as client,
):
    tailscale_syncer.sync()
    client.assert_not_called()

# A complete snapshot still publishes both node and Service records.
with (
    patch.object(
        tailscale_syncer,
        "fetch_ts_nodes",
        return_value={"Self": {"DNSName": "node.ts.gaof.net", "TailscaleIPs": ["100.64.0.1"]}},
    ),
    patch.object(
        tailscale_syncer,
        "fetch_ts_netmap",
        return_value={"DNS": {"ExtraRecords": [{"Name": "svc.ts.gaof.net.", "Value": "100.64.0.2", "Type": "A"}]}},
    ),
    patch.object(tailscale_syncer.httpx, "Client") as client,
):
    api = client.return_value.__enter__.return_value
    api.get.return_value.status_code = 200
    api.get.return_value.json.return_value = {"rrsets": []}
    tailscale_syncer.sync()
    updates = api.patch.call_args.kwargs["json"]["rrsets"]
    assert {(r["name"], r["records"][0]["content"]) for r in updates} == {
        ("node.ts.gaof.net.", "100.64.0.1"),
        ("svc.ts.gaof.net.", "100.64.0.2"),
    }

import importlib.util
import os
import sys

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

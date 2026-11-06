import json
import socket
import time
from http.server import BaseHTTPRequestHandler
from subprocess import PIPE, Popen


class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_error(404)
            return
        try:
            with Popen(["codex", "app-server"], stdin=PIPE, stdout=PIPE, text=True) as server:

                def rpc(method, **params):
                    print(json.dumps({"id": method, "method": method, "params": params}), file=server.stdin, flush=True)
                    reply = next(reply for reply in map(json.loads, server.stdout) if reply.get("id") == method)
                    if "error" in reply:
                        raise RuntimeError(reply["error"])
                    return reply["result"]

                try:
                    rpc("initialize", clientInfo={"name": "usage-metrics", "version": "1"})
                    print('{"method":"initialized"}', file=server.stdin, flush=True)
                    snapshot = rpc("account/rateLimits/read", excludeResetCreditDetails=True)
                    weekly = next(
                        window
                        for window in (snapshot["rateLimits"]["primary"], snapshot["rateLimits"]["secondary"])
                        if window and window["windowDurationMins"] == 10080
                    )
                    metrics = (
                        "# HELP codex_weekly_used_percent Percentage of the weekly Codex quota used.\n"
                        "# TYPE codex_weekly_used_percent gauge\n"
                        f"codex_weekly_used_percent {weekly['usedPercent']}\n"
                        "# HELP codex_weekly_reset_timestamp_seconds Unix timestamp of the weekly quota reset.\n"
                        "# TYPE codex_weekly_reset_timestamp_seconds gauge\n"
                        f"codex_weekly_reset_timestamp_seconds {weekly['resetsAt'] if weekly['resetsAt'] is not None else 'NaN'}\n"
                        "# HELP codex_usage_last_success_timestamp_seconds Unix timestamp of the last successful sample.\n"
                        "# TYPE codex_usage_last_success_timestamp_seconds gauge\n"
                        f"codex_usage_last_success_timestamp_seconds {time.time():.0f}\n"
                    )
                finally:
                    server.terminate()
        except Exception:
            self.send_error(500)
            raise
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.end_headers()
        self.wfile.write(metrics.encode())


with socket.socket(fileno=0) as connection:
    MetricsHandler(connection, connection.getpeername(), None)

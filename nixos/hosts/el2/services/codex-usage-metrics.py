import argparse
import json
import sys
import time
from pathlib import Path
from subprocess import PIPE, Popen

parser = argparse.ArgumentParser(description="Write one weekly Codex usage sample in Prometheus textfile format.")
parser.add_argument("metrics_file", type=Path, help="Destination .prom file")
args = parser.parse_args()

with Popen(["codex", "app-server"], stdin=PIPE, stdout=PIPE, text=True) as server:

    def rpc(method, **params):
        print(json.dumps({"id": method, "method": method, "params": params}), file=server.stdin, flush=True)
        reply = next(reply for reply in map(json.loads, server.stdout) if reply.get("id") == method)
        if "error" in reply:
            sys.exit(reply["error"])
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
        temporary = args.metrics_file.with_suffix(".prom.tmp")
        temporary.write_text(metrics)
        temporary.replace(args.metrics_file)
    finally:
        server.terminate()

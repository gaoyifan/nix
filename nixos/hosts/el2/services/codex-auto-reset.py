import argparse
import json
import sys
import time
from subprocess import PIPE, Popen

parser = argparse.ArgumentParser(description="Preview reset credits or automatically redeem them before expiry.")
parser.add_argument("--apply", action="store_true", help="Stay running and redeem credits one hour before expiry")
args = parser.parse_args()

with Popen(["codex", "app-server"], stdin=PIPE, stdout=PIPE, text=True) as server:

    def rpc(method, **params):
        print(json.dumps({"id": method, "method": method, "params": params}), file=server.stdin, flush=True)
        reply = next(reply for reply in map(json.loads, server.stdout) if reply.get("id") == method)
        if "error" in reply:
            sys.exit(reply["error"])
        return reply["result"]

    try:
        rpc("initialize", clientInfo={"name": "auto-reset", "version": "1"})
        print('{"method":"initialized"}', file=server.stdin, flush=True)
        while True:
            credits = rpc("account/rateLimits/read")["rateLimitResetCredits"]["credits"]
            print(credits, flush=True)
            if not args.apply:
                break
            for reset in sorted(credits, key=lambda c: c["expiresAt"] or float("inf")):
                if reset["status"] == "available" and (reset["expiresAt"] or 0) > time.time():
                    time.sleep(max(0, reset["expiresAt"] - time.time() - 3600))
                    print(rpc("account/rateLimitResetCredit/consume", creditId=reset["id"], idempotencyKey=reset["id"]))
            time.sleep(86400)
    finally:
        server.terminate()

# New API (QuantumNous/new-api): OpenAI-compatible gateway in front of the
# ChatGPT/Codex backend. The hermes-nix-* containers use the host-service
# address http://198.18.255.254:3000/v1 with per-user tokens. The Codex channel
# inside New API replays those requests to chatgpt.com/backend-api/codex with the
# ChatGPT OAuth credentials (configured in the admin UI, stored in /data).
#
# SQLite (the default when SQL_DSN is unset) is plenty for a handful of
# tokens; everything lives under /var/lib/new-api.
{
  lib,
  pkgs,
  ...
}: {
  virtualisation.oci-containers.containers.new-api = {
    image = "docker.io/calciumion/new-api:v1.0.0-rc.20";
    volumes = ["/var/lib/new-api:/data"];
    environment.TZ = "Asia/Shanghai";
    # nftables owns the ruleset, so do not publish ports through a bridge.
    # Listens on :3000.
    extraOptions = ["--network=host"];
  };

  systemd.tmpfiles.rules = ["d /var/lib/new-api 0750 root root -"];

  systemd.services.new-api-reset-hermes-quotas = {
    description = "Reset New API hermes-* token quotas";
    after = ["podman-new-api.service"];
    startAt = "Mon *-*-* 00:00:00";
    serviceConfig = {
      Type = "oneshot";
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateNetwork = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = ["/var/lib/new-api"];
    };
    script = ''
      updated="$(${lib.getExe pkgs.sqlite} /var/lib/new-api/one-api.db <<'SQL'
      .timeout 30000
      BEGIN IMMEDIATE;
      UPDATE tokens
      SET remain_quota = CAST(ROUND(500 * COALESCE(
            (SELECT CAST(value AS REAL) FROM options WHERE key = 'QuotaPerUnit'),
            500000
          )) AS INTEGER),
          unlimited_quota = 0,
          status = CASE WHEN status = 4 THEN 1 ELSE status END
      WHERE name LIKE 'hermes-%' AND deleted_at IS NULL;
      SELECT changes();
      COMMIT;
      SQL
      )"

      if (( updated == 0 )); then
        echo "No active New API tokens matched hermes-*" >&2
        exit 1
      fi

      echo "Reset remaining quota to USD 500 for $updated New API hermes-* tokens"
    '';
  };

  systemd.timers.new-api-reset-hermes-quotas.timerConfig.Persistent = true;
}

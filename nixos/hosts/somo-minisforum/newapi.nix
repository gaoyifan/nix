# New API (QuantumNous/new-api): OpenAI-compatible gateway in front of the
# ChatGPT/Codex backend. The hermes-* VMs on br-somo talk the Responses API
# to http://100.65.3.254:3000/v1 with per-VM tokens; the Codex channel inside
# New API replays those requests to chatgpt.com/backend-api/codex with the
# ChatGPT OAuth credentials (configured in the admin UI, stored in /data).
#
# SQLite (the default when SQL_DSN is unset) is plenty for a handful of
# tokens; everything lives under /var/lib/new-api.
{...}: {
  virtualisation.oci-containers.containers.new-api = {
    image = "docker.io/calciumion/new-api:latest";
    volumes = ["/var/lib/new-api:/data"];
    environment.TZ = "Asia/Shanghai";
    # Host networking, same as the other containers on this host (wlt,
    # diverge): nftables owns the ruleset, so no bridged port publishing.
    # Listens on :3000.
    extraOptions = ["--network=host"];
  };

  systemd.tmpfiles.rules = ["d /var/lib/new-api 0750 root root -"];
}

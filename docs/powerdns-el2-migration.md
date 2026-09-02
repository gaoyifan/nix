# PowerDNS el2 migration

Migration from the Debian Docker host to the NixOS-native el2 service completed on 2026-09-02.

## Completed cutover

- Decrypted PowerDNS, Lightningstream, Git deploy-key, and WireGuard secrets on el2 and compared their hashes with the running Docker configuration.
- Stopped all Docker writers before copying `pdns.lmdb` and `pdns.lmdb-0`; source and target hashes matched.
- Created `/pool1/services/powerdns-zones` as a filtered sparse checkout containing only `backup/` from the `pdns` branch.
- Changed the `wg-with-hc.automesh.org` health URL from `100.127.101.20:8088` to `100.127.100.2:8088`.
- Stopped all seven PowerDNS-related Docker containers. They remain available as a rollback source and use `restart=unless-stopped`.
- Drained the legacy `svc:pdns-ui` Tailscale service endpoint on the Docker host so the service VIP only routes to el2.

## Verification

- All 12 zone exports matched the Docker source before cutover.
- PowerDNS UDP/TCP queries, the local API, the Tailscale UI service, both WireGuard health endpoints, Lightningstream, and both syncers passed on el2.
- `powerdns-zone-backup.service` completed commit, rebase, and push; the first NixOS backup was pushed as `2c1cd08`.
- ali-sg, google, and oracle3 loaded the el2 snapshot and returned the new Lua record over UDP and TCP.
- Secondary nodes run `systemd-resolved` with `DNSStubListener=no`; `/etc/resolv.conf` follows its DHCP-derived uplink file while PowerDNS retains port 53.
- The old host no longer listens on ports 5354 or 8088.
- `curl -vL http://pdns-ui.ts.gaof.net/` from cjia returns HTTP 200 from Caddy.

Do not restart the old PowerDNS containers while el2 is active: that would reintroduce two writers using different Lightningstream instance identities.

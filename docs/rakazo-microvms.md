# Rakazo on el2

One NixOS MicroVM using Cloud Hypervisor hosts the shared Rakazo deployment.
API, worker, PostgreSQL, the sandbox supervisor, and Docker computers all run
inside that VM. Rakazo manages its users within the application. The supervisor
controls the VM's Docker daemon.

The VM and Tailscale Service are named `rakazo`. Additional users share this
deployment and do not create more VMs. The host uses microvm.nix's default
`microvm:kvm` account and TAP setup.

Rakazo's Compose source follows `main`, pinned by `flake.lock`. App and computer
images use the matching `sha-<commit>` tag. Update with `nix flake update rakazo-src`.
The host rebuilds the guest declaratively through microvm.nix. The host Nix store is
exported read-only; Docker data is stored in the guest's persistent disk.

## Configuration and credentials

The DHCP lease and Tailscale advertisement are configured directly in
`nixos/hosts/el2/services/rakazo/default.nix`. The application's public environment
is defined in `guest-os.nix` in the same directory.

The guest uses `100.64.2.81` from el2's existing `100.64.2.0/24`, outside the
`.100–.200` DHCP pool. The host binds the address to MAC `02:52:00:00:00:01`
in the existing dnsmasq service. DHCP supplies the guest's address, gateway,
and DNS (`100.64.2.254`); no address or route is set statically in the guest.
TAP `rakazo-tap` joins VLAN 642 through `homeRouter.switch.ports`; dnsmasq derives
the `/24` netmask from the existing LAN interface.

The guest has 4 vCPUs, 6144 MiB RAM, and an 81920 MiB sparse ext4 disk, set
directly in `nixos/hosts/el2/services/rakazo/vm.nix`. The volume size only
controls initial creation; changing it does not grow an existing filesystem.

Create `secrets/files/nixos/el2/rakazo-env.age` with `just edit-secret`.
It contains independent random values for:

```dotenv
POSTGRES_PASSWORD=<32 hexadecimal characters>
BETTER_AUTH_SECRET=<64 hexadecimal characters>
ENCRYPTION_KEY=<64 hexadecimal characters>
SCREEN_PROXY_SECRET=<64 hexadecimal characters>
SANDBOX_SUPERVISOR_TOKEN=<64 hexadecimal characters>
```

The existing el2 recipient rules cover these top-level host secrets. Preserve
`ENCRYPTION_KEY` and the database password when updating the deployment.
Credentials are decrypted on el2 and exported to that VM through a read-only
directory under `/run/rakazo`. Plaintext credentials never enter the Nix store.

Apply with `just nixos` on el2. Configuration or credential changes
restart the MicroVM. Guest services can be inspected from el2:

```sh
systemctl status microvm@rakazo
ssh root@100.64.2.81 systemctl status rakazo
ssh root@100.64.2.81 docker ps
```

Prepare the first owner account before setting `advertised = true`. The service
is available at `https://rakazo.ts.gaof.net`, using el2's
existing certificate and Tailscale DNS synchronization. Create the owner account,
then close registration through Rakazo's deployment settings before advertising
the service. The web port is also reachable from the LAN when the VM starts;
`advertised` only controls the Tailscale advertisement. An allowlist requires email
delivery, so the default empty allowlist is used. SMTP and
password recovery are not configured. Users connect their own model credentials
through the UI.

Define the Tailscale Service named `rakazo`
with endpoint `tcp:443` in the admin console, then approve el2 under that Service's
**Service hosts**. Defining the Service creates its DNS record before host approval;
DNS resolution alone does not mean the endpoint is ready. Check approval with:

```sh
tailscale status --json | jq '.Self.CapMap."service-host"'
curl --noproxy '*' https://rakazo.ts.gaof.net
```

The capability map must include `svc:rakazo`. See
[Tailscale's Service host approval instructions](https://tailscale.com/docs/features/tailscale-services#step-3-approve-a-service-host).

If the instance was advertised before its Service was defined and el2 does not
appear in **Service hosts**, re-advertise that instance after defining the Service:

```sh
tailscale serve drain svc:rakazo
tailscale serve advertise svc:rakazo
```

## Network and capacity

The guest joins the existing VLAN 642 like the Incus VMs and uses the shared
home-router and edge-firewall policies. No Rakazo-specific gateway, route,
DHCP firewall rule, or input/forward rules are added. LAN access, including el2
and the other devices, is available for Rakazo tasks. Public IPv4 egress uses
el2's existing outlets.

Cloud Hypervisor ballooning enables free-page reporting. Actual host memory is
measured through the VMM process's `smaps_rollup`, together with guest memory and
Docker statistics. The shared guest has a 6144 MiB ceiling. The pinned Compose
release defaults each computer to a 2 GiB and 2 CPU limit.

On 2026-09-30, the pilot's VMM and virtiofs processes together measured about
2.6 GiB PSS with its computer stopped and 3.6 GiB with one Chromium desktop.
This was an idle application/desktop test without model inference or concurrent
user workloads. The owner session and a workspace file were verified
across a VM restart, and a logical PostgreSQL dump was created and inspected.
First desktop provisioning completed
in 5.23 seconds after fixing the app network's gateway priority; web and supervisor
retain their app-network default gateway when computer networks are attached.

el2 currently boots with `mitigations=off`. Separate guest kernels do not restore
the disabled host CPU speculative-execution mitigations.

## Persistence and recovery

The guest's `/var` is stored in
`/pool1/services/rakazo/var.img`. It contains Docker images,
PostgreSQL, agent homes, browser profiles, and persistent SSH host keys. The
encrypted `pool1/services` dataset is already snapshotted and replicated to nfs
by znapzend. Active-VM disk snapshots are crash-consistent; the guest also writes
a logical PostgreSQL dump daily at 02:00 to
`/var/lib/rakazo/backups/database.dump`.

Keep `advertised = false` and stop the MicroVM before replacing `var.img`
from a snapshot. Restore its
matching encrypted credentials, preserve the disk owner, and start the VM again.
Verify the owner account and closed registration before advertising the service.
The database dump can be inspected with `pg_restore --list` inside the PostgreSQL container.

Installer configurations disable the MicroVM host module.

Sources: [microvm.nix](https://github.com/microvm-nix/microvm.nix),
[Rakazo self-hosting](https://github.com/elie222/rakazo/blob/v0.1.6/docs/self-host.md).

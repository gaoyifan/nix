# Auramont CI on el2

`el2-auramont` is a dedicated systemd-nspawn runner for
`cardio-angel/auramont-mono`, following the existing `el2-nspawn` runner pattern.
It has its own root at `/pool1/services/auramont-runner/root`, Nix store, Docker
daemon, work directory and HOME. No host Docker socket, Nix daemon or home
files are mounted. Its private network namespace joins the internal LAN at
`100.64.2.82`; Docker bridges and firewall rules stay in that namespace.

Both runners share `nixos/hosts/el2/services/github-runner/nspawn.nix` for host
startup and `github-runner/guest-base.nix` for the guest's Nix configuration,
garbage collection, nested namespaces and runner defaults. Their profiles keep
repository identity, networking, tools and resource limits separate. Auramont's
complete job cleanup is in `auramont-runner/cleanup.sh`.

The host unit is `github-runner-auramont.service`, the machine is `auramont-ci`,
and its runner labels are `self-hosted, Linux, X64, el2, auramont`. The unit has
a 32 GiB memory limit and a 12-core CPU quota. Exactly one runner executes jobs
in this container: Web, Supabase and Coordinator tests use fixed Compose project
names and must not share a Docker daemon with concurrent jobs. ARM64 and mobile
workflows are unchanged in this first migration.

Nix, Node 24, Python, Docker/Compose and the runner are supplied by the pinned
NixOS guest closure. Application dependencies remain owned by Auramont's locks.
The guest uses the same nested Nix namespace support as the existing Nix runner.

## Registration and activation

Supply a short-lived repository registration token through standard input,
never a Nix value or tracked file:

```sh
gh api --method POST repos/cardio-angel/auramont-mono/actions/runners/registration-token --jq .token \
  | ssh el2 'sudo install -d -m 0700 /var/lib/github-runner-auramont; sudo install -m 0600 /dev/stdin /var/lib/github-runner-auramont/token'
just sync-and-rebuild el2
```

The host unit seeds the independent guest store and boots its declared NixOS
closure. Only the protected registration-token file is bound read-only into the
guest; systemd credentials deliver it to registration. Registered credentials
remain in the guest. Refresh the host token before registering a replacement
root, and drain the runner before changing or stopping its container.

The job hooks remove guest Docker containers, volumes and networks before and
after each job, retain recent image/build caches, and remove job-created SSH
and Docker login files. A Nix-built cleanup container restores ownership of
the runner work directory after Compose creates database bind mounts, so the
next checkout can clean it. These operations are scoped to this single-runner
container. Do not attach other workloads or a second runner to its Docker daemon.

## Verification

```sh
gh api repos/cardio-angel/auramont-mono/actions/runners
ssh el2 'sudo systemctl status github-runner-auramont --no-pager'
ssh el2 'sudo machinectl status auramont-ci'
ssh el2 'sudo systemd-run --machine=auramont-ci --wait --pipe docker info'
```

Test workflow changes on Auramont's `ci` branch before promoting them to `main`.
CI-branch pushes remain validation-only. Release tags and the existing protected
production dispatch conditions retain deployment control. Run only trusted
repository code on this persistent runner. CI validation does not authorize an
application production release.

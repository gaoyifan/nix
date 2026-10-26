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

## MongoDB memory locking and scoped repair (2026-10-26)

Native MongoDB authentication tests require `mlock` and `munlock` to keep SCRAM
credentials in locked memory. The Auramont nspawn allowlist permits exactly
these two calls; it does not add `CAP_IPC_LOCK` or raise the existing 8 MiB
memlock limit. Without this allowance, MongoDB aborts during user creation.

The repair passed the `ci` branch matrix before promotion to `main` as
`e645176`. Before the el2 switch, the real encrypted secrets submodule was
initialized, `hasRealFiles` and `system.switch.enable` were asserted, and all
22 secrets were decrypted to `/dev/null` using el2's host identity.

The scoped deployment retained the running Orca 1.4.239 package through a Nix
overlay rather than bringing in unrelated updates. Its reconstructed baseline
exactly matched `/nix/store/adv0rigj3vllv51zf80nqwkdlyk46y3z-nixos-system-el2-26.05.20261020.cd4ea8d`.
Only the two allowlist arguments changed in the generated runner unit;
`dry-activate` listed only that runner for restart. The accepted generation is
`/nix/store/9c0ys37vxbwqxp4wyksxk8d5aa79pg1r-nixos-system-el2-26.05.20261020.cd4ea8d`;
the baseline is retained at `/nix/var/nix/gcroots/auramont-runner-before-mlock`.
Actual guest-user syscall checks passed after the idle runner restarted; Orca's
existing process remained running. This maintenance did not migrate Auramont's
production MongoDB or importer.

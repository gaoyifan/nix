# Auramont CI on el2

Four dedicated systemd-nspawn runners serve `cardio-angel/auramont-mono` with
labels `self-hosted, Linux, X64, el2, auramont`.

| Runner | Machine | LAN address |
| --- | --- | --- |
| `el2-auramont` | `auramont-ci` | `100.64.2.82` |
| `el2-auramont-2` | `auramont-ci2` | `100.64.2.83` |
| `el2-auramont-3` | `auramont-ci3` | `100.64.2.84` |
| `el2-auramont-4` | `auramont-ci4` | `100.64.2.85` |

Host units are `github-runner-auramont.service` and
`github-runner-auramont-{2,3,4}.service`. The original root remains
`/pool1/services/auramont-runner/root`; new roots are
`/pool1/services/auramont-runner-{2,3,4}/root`. The short machine names keep
`vb-<machine>` within Linux's 15-character interface-name limit. Addresses are
outside the LAN's DHCP pool (`100.64.2.100`–`100.64.2.200`).

Each unit has an 8-core CPU quota, 24 GiB memory high watermark and 32 GiB memory
limit: at most 32 CPU equivalents and 128 GiB across the pool. These are caps,
not resource reservations. Each guest owns its Nix store, Docker daemon, network
namespace, work directory, HOME and tool cache; no host Docker socket, Nix daemon
or HOME is mounted. Keep exactly one runner per guest because jobs use fixed
Compose project names and daemon-wide job cleanup.

Host startup reuses `github-runner/nspawn.nix`; guest Nix, garbage collection,
namespaces and runner defaults reuse `github-runner/guest-base.nix`. Nix, Node 24,
Python, Docker/Compose and nix-ld come from the pinned guest closure. The existing
`el2-nspawn` runner remains separate. Auramont's `cleanup.sh` cleans only its
own guest's Docker resources, SSH and Docker authentication and workspace ownership;
recent build and SDK caches persist.

## Registration and activation

Supply a short-lived repository registration token through standard input for
**new or replacement guests only**. Existing registered guests keep their token
files and credentials unchanged. For example, to bootstrap slot 2:

```sh
suffix=-2
gh api --method POST repos/cardio-angel/auramont-mono/actions/runners/registration-token --jq .token \
  | ssh el2 "sudo install -d -m 0700 /var/lib/github-runner-auramont${suffix}; sudo install -m 0600 /dev/stdin /var/lib/github-runner-auramont${suffix}/token"
just sync-and-rebuild el2
```

Slots 3 and 4 use `-3` and `-4`; the original slot uses an empty suffix. Never put
registration tokens in Git, Nix values or the Nix store. Refreshing an existing
guest's token file causes the NixOS runner module to reset its registration state.

Drain a runner before changing or stopping its container: temporarily remove its
`auramont` routing label through GitHub's runner-label API, wait for `busy=false`,
then switch. Restore the label only after the container passes checks. No host
reboot is needed. Check the activation diff and preserve unrelated services and
real encrypted secrets; a routine whole-host switch may include unrelated updates.

## Verification

```sh
gh api repos/cardio-angel/auramont-mono/actions/runners
ssh el2 'sudo systemctl status github-runner-auramont{,-2,-3,-4} --no-pager'
ssh el2 'sudo machinectl list --no-pager'
ssh el2 'sudo systemd-run --machine=auramont-ci2 --wait --pipe docker info'
```

Verify four online runners, distinct Docker daemon IDs and network namespaces,
and simultaneous jobs without cross-guest cleanup. Workflow validation uses the
monorepo's `ci` branch before promotion to `main`. PRs cancel their own stale runs;
Coordinator publishes immutable per-tag images/releases without a global lock.
Existing Supabase/Web production deployment serialization remains in place.

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

# NanoPi R4S bootstrap

All NanoPi R4S devices start from the same bootstrap image. The bootstrap has
no agenix secrets or device-specific configuration. Its only job is to provide
SSH access, generate the device SSH host key, and accept the target NixOS
configuration.

## Network

Connect a workstation directly to either port and configure the workstation
address shown below.

| R4S port | R4S address | Workstation address |
| --- | --- | --- |
| WAN (`end0`) | `192.0.2.254/24` | `192.0.2.1/24` |
| LAN (`enp1s0`) | `198.51.100.254/24` | `198.51.100.1/24` |

SSH is available as `root` using the repository's authorized keys. Password
login is disabled. Both U-Boot and Linux use a 115200 baud serial console.

## Stage 1: flash and enroll the device identity

Build and flash the image:

```console
just build-nanopi-bootstrap-image
```

After the first boot, read the public half of the host identity generated on
the device and replace `TARGET` with the final hostname. Normalizing the
comment keeps the agenix recipient name independent of the bootstrap hostname:

```console
target=TARGET
ssh root@198.51.100.254 cat /etc/ssh/ssh_host_ed25519_key.pub \
  | awk -v comment="root@$target" '{ print $1, $2, comment }'
```

Replace the target's host key in `secrets/files/secrets.nix`, then re-encrypt
the secrets for the new recipient:

```console
just rekey
```

The private half remains only on the device and survives the second stage.
Never add it to the repository or a Nix derivation.

The bootstrap marks `/boot` and its existing subdirectories with the Btrfs
`compression=none` property. Keep that service enabled: files written there by
later deployments must remain uncompressed because U-Boot cannot read the
Btrfs zstd extents produced by the running kernel.

## Stage 2: install the target configuration

Deploy the target profile with `--boot`. This writes the next boot generation
without activating it, so the bootstrap address stays reachable throughout the
copy:

```console
just deploy-nanopi-from-bootstrap TARGET
```

When connected to the WAN port instead, pass its bootstrap address:

```console
just deploy-nanopi-from-bootstrap TARGET 192.0.2.254
```

Reboot only after the deployment succeeds:

```console
ssh root@198.51.100.254 reboot
```

The target configuration starts after reboot, agenix decrypts with the
preserved SSH host key, and secret-dependent network interfaces can start.

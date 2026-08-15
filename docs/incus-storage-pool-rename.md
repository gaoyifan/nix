# Incus storage pool rename

Checked against Incus upstream `main` at
[`4ef283c72a696d2d8f0ca226c3ab363e443519f9`](https://github.com/lxc/incus/commit/4ef283c72a696d2d8f0ca226c3ab363e443519f9)
on 2026-08-15.

## Conclusion

Incus does not support renaming a logical storage pool in place. There is no
supported, no-copy procedure for changing the Incus pool name from `default`
to `pool1` while retaining `pool1/incus` as its populated ZFS backend.

The supported choices are:

1. Keep the logical name `default`. This is the recommended choice here: Incus
   has [no special concept of a default storage pool](https://linuxcontainers.org/incus/docs/main/explanation/storage/#default-storage-pool),
   and selects the pool from the instance or profile root disk. A description
   can document that `default` is the SSD-backed `pool1/incus` pool.
2. If the logical name must be `pool1`, create it on another empty ZFS dataset,
   move every instance and custom volume to it, update all references, and
   delete the old pool after verification. This is a real storage migration,
   not a metadata rename.

For a cosmetic name change, the migration cost and risk are not justified.

## What can and cannot be renamed

| Object | Supported operation | Effect |
| --- | --- | --- |
| Incus logical pool name (`default`) | No rename API or CLI | Must remain unchanged or be replaced by a newly created pool |
| Pool `source` (`pool1/incus`) | Immutable after pool creation | Cannot be changed on a created pool |
| ZFS backend `zfs.pool_name` | Immutable through the Incus driver | A manual `zfs rename` would leave Incus pointing at the old dataset |
| Custom volume name | Supported within one logical pool | The ZFS driver can use `zfs rename`; this is distinct from renaming a pool |
| Instance/custom volume destination pool | Supported move | Cross-pool copy/migration followed by source deletion |

The API model makes the first distinction explicit: `Name` exists in the
creation request and full read model, while the writable `StoragePoolPut`
contains only `Config` and `Description`.
[`shared/api/storage_pool.go`](https://github.com/lxc/incus/blob/4ef283c72a696d2d8f0ca226c3ab363e443519f9/shared/api/storage_pool.go#L16-L83)

The `incus storage` CLI likewise registers create, delete, edit, get, info,
list, set, show, unset, bucket, and volume commands, but no pool rename command.
[`cmd/incus/storage.go`](https://github.com/lxc/incus/blob/4ef283c72a696d2d8f0ca226c3ab363e443519f9/cmd/incus/storage.go#L36-L86)

Incus rejects changing `source` once the pool is no longer pending, and the ZFS
driver separately rejects changing `zfs.pool_name`.
[`backend.go`](https://github.com/lxc/incus/blob/4ef283c72a696d2d8f0ca226c3ab363e443519f9/internal/server/storage/backend.go#L268-L321),
[`driver_zfs.go`](https://github.com/lxc/incus/blob/4ef283c72a696d2d8f0ca226c3ab363e443519f9/internal/server/storage/drivers/driver_zfs.go#L581-L610)

Creating a second logical pool that points at the already populated
`pool1/incus` dataset is not an adoption/alias mechanism: normal ZFS pool
creation rejects an existing source with child datasets.
[`driver_zfs.go`](https://github.com/lxc/incus/blob/4ef283c72a696d2d8f0ca226c3ab363e443519f9/internal/server/storage/drivers/driver_zfs.go#L298-L353)

Custom volume rename is a different, explicitly supported operation. The
[official volume guide](https://linuxcontainers.org/incus/docs/main/howto/storage_move_volume/#move-or-rename-custom-storage-volumes)
documents same-pool rename, and the ZFS implementation performs a backend
dataset rename.
[`driver_zfs_volumes.go`](https://github.com/lxc/incus/blob/4ef283c72a696d2d8f0ca226c3ab363e443519f9/internal/server/storage/drivers/driver_zfs_volumes.go#L2727-L2758)

## Why the supported alternative is a migration

The official procedure is to stop an instance and run
`incus move <instance> --storage <target_pool>`; custom volumes use
`incus storage volume move`.
[Official move guide](https://linuxcontainers.org/incus/docs/main/howto/storage_move_volume/)

Upstream implements a cross-pool instance copy by negotiating a migration
transport between the source and target backends, then creating the target
volume. It is not a rename of the pool or its root dataset.
[`backend.go`](https://github.com/lxc/incus/blob/4ef283c72a696d2d8f0ca226c3ab363e443519f9/internal/server/storage/backend.go#L1277-L1373)

For custom volumes, the move path explicitly copies into the new pool and only
then deletes the old volume.
[`storage_volumes.go`](https://github.com/lxc/incus/blob/4ef283c72a696d2d8f0ca226c3ab363e443519f9/cmd/incusd/storage_volumes.go#L1864-L1911)

With ZFS, optimized transfer can use ZFS send/receive, but it still needs a
distinct target dataset and temporary capacity for both source and target. It
is not a metadata-only operation.
[`driver_zfs_volumes.go`](https://github.com/lxc/incus/blob/4ef283c72a696d2d8f0ca226c3ab363e443519f9/internal/server/storage/drivers/driver_zfs_volumes.go#L2955-L3049)

## Unsupported shortcuts and risks

- Directly updating `storage_pools.name` in the global database is incomplete.
  Volumes refer to the pool by database ID, but instance/profile disk devices,
  project restrictions and limits, daemon volume settings, authorization
  objects, mount paths, and compatibility symlinks can contain the logical pool
  name.
- Manually renaming `pool1/incus` at the ZFS layer changes the backend object,
  not the Incus pool name, while Incus forbids updating the created pool's
  source afterward.
- Deleting and recovering/adopting the populated dataset is a disaster-recovery
  workflow, not a pool rename contract.

Incus documents arbitrary `incus admin sql` writes as a debugging and disaster
recovery facility that should be used only for broken updates or bugs and after
consulting the Incus team. It is not a supported rename interface.
[Incus database debugging guidance](https://linuxcontainers.org/incus/docs/main/debugging/#running-custom-queries-from-the-console)

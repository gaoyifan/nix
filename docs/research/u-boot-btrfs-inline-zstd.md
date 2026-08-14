# U-Boot 无法读取 Linux 写入的 Btrfs zstd 内联 extent

调查日期：2026-08-13；修复验证：2026-08-14
结论状态：已本地复现，并在 U-Boot fork 与 NanoPi R4S 构建中修复

## 结论

NanoPi R4S 在初始 Btrfs 镜像上能够启动、但经过 Linux 运行时更新
`/boot` 后无法再次启动，根因是 U-Boot 的 Btrfs reader 为压缩内联
extent 分配了过小的解压缓冲区。

这不是 `mkfs.btrfs` 没有压缩初始镜像。初始镜像确实通过
`mkfs.btrfs -r --compress zstd:6` 对整个导入目录启用压缩；问题是 `mkfs.btrfs` 和 Linux
内核对小文件采用了不同的压缩输入长度：

- `mkfs.btrfs` 压缩文件的真实长度；
- Linux 对内联 extent 压缩一个完整的 Btrfs sector（当前为 4096 字节），
  但 extent 的 `ram_bytes` 仍记录文件的真实长度。

这两种磁盘表示都能被 Linux 正确读取。U-Boot 却把 `ram_bytes` 同时当作
文件长度和 zstd 输出缓冲区容量。当 Linux 生成的 zstd frame 要输出 4096
字节，而 `ram_bytes` 只有实际文件长度时，U-Boot 的 zstd 解压器返回错误
70，即 `ZSTD_error_dstSize_tooSmall`。

## 现场故障与排除项

故障镜像曾经成功进入 Linux，日志证明：

- U-Boot 已找到并加载 kernel、initrd 和设备树；
- Linux 识别 `/dev/mmcblk1p2` 上标签为 `NIXOS_SD` 的 Btrfs；
- initrd 成功挂载根文件系统并完成 `switch-root`；
- systemd 最终启动到串口登录提示符。

而在后续强制重启后，串口完全没有 Linux 内核日志。这说明失败发生在
Linux 启动之前。该问题与 SSH host private key、agenix 解密和运行时网络
配置无关；这些组件只有在 U-Boot 已成功加载 Linux 后才会参与启动。

## 可重复实验

实验使用与目标镜像一致的组件：

- U-Boot 2026.04，sandbox defconfig，并启用 `CONFIG_FS_BTRFS=y`；
- Linux 7.1.5 的 Btrfs 写入路径；
- btrfs-progs 6.19.1；
- zstd 1.5.7。

准备两个 128 MiB 的 Btrfs 镜像，并把同一个 1262 字节文件放到
`/boot/extlinux/extlinux.conf`：

1. 离线镜像通过 `mkfs.btrfs -r --compress zstd:6` 导入文件；
2. 运行时镜像先挂载为 `compress=zstd:3`，再由 Linux 复制相同文件。

随后使用同一个 U-Boot sandbox 读取：

```console
u-boot -c 'host bind 0 IMAGE; load host 0 100000 /boot/extlinux/extlinux.conf'
```

结果：

| 镜像写入者 | 文件 `ram_bytes` | 压缩 payload | zstd 实际输出 | 原始 U-Boot 2026.04 |
| --- | ---: | ---: | ---: | --- |
| `mkfs.btrfs` | 1262 | 749 | 1262 | `1262 bytes read` |
| Linux | 1262 | 761 | 4096 | `failed to decompress: 70` |

`btrfs inspect-internal dump-tree` 显示两个文件均为：

- `BTRFS_FILE_EXTENT_INLINE`；
- compression type 3，即 zstd；
- `ram_bytes = 1262`。

因此，差异不在于是否为内联 extent，也不在于是否压缩。把两个 zstd frame
从镜像中提取并交给 zstd 1.5.7 解压后，离线 frame 输出 1262 字节，Linux
frame 输出 4096 字节。

进一步缩小实验后，Linux 写入的 1 字节压缩文件仍然失败：其 19 字节 zstd
frame 解压为 4096 字节。相同内容写入带 `compression=none` 属性的目录后，
U-Boot 可以正常读取。这排除了具体文件内容、路径和压缩级别是决定因素。

## 写入端源码

### `mkfs.btrfs` 压缩真实文件长度

btrfs-progs 6.19.1 的 `zstd_compress_inline_extent()`：

1. 以传入的 `size` 设置 zstd pledged source size；
2. 设置 `input.size = size`；
3. 将同一个真实文件长度写入 extent 的 `ram_bytes`。

调用处传入 `st->st_size`。因此 1262 字节文件的 zstd frame 解压后也是 1262
字节。参见 btrfs-progs
[`mkfs/rootdir.c`](https://github.com/kdave/btrfs-progs/blob/v6.19.1/mkfs/rootdir.c#L1091-L1159)
和[内联 extent 调用处](https://github.com/kdave/btrfs-progs/blob/v6.19.1/mkfs/rootdir.c#L1287-L1353)。

本仓库的 image creator 确实向 `mkfs.btrfs` 传入了 `--compress zstd:6`，见
[`nixos/optional/make-btrfs-fs.nix`](../../nixos/optional/make-btrfs-fs.nix#L62-L68)。

### Linux 压缩完整 sector，但记录真实 `i_size`

Linux 7.1.5 的 `run_delalloc_inline()` 对小文件调用：

```c
cb = btrfs_compress_bio(inode, 0, blocksize, ...);
```

其中 `blocksize` 是 `fs_info->sectorsize`，当前镜像为 4096。压缩完成后，它
调用 `__cow_file_range_inline()` 时却把真实的 `i_size` 作为 `size`；最终
`insert_inline_extent()` 将这个 `size` 写入 `ram_bytes`。参见 Linux stable
v7.1.5 的
[`run_delalloc_inline()`](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/fs/btrfs/inode.c?h=v7.1.5#n2333)
和
[`insert_inline_extent()`](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/fs/btrfs/inode.c?h=v7.1.5#n458)。

Linux 的对应读取路径没有把 `ram_bytes` 当作 zstd 输出缓冲区容量。它为
zstd 准备 `fs_info->sectorsize` 大小的工作缓冲区，解压完成后再把需要的
范围复制到目标 folio。参见 Linux stable v7.1.5 的
[`zstd_decompress()`](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/fs/btrfs/zstd.c?h=v7.1.5#n676)。

## U-Boot 读取端缺陷

U-Boot 2026.04 的 `btrfs_read_extent_inline()` 执行：

```c
dsize = btrfs_file_extent_ram_bytes(leaf, fi);
cbuf = malloc(csize);
dbuf = malloc(dsize);

ret = btrfs_decompress(..., cbuf, csize, dbuf, dsize);
```

对于 Linux 写入的 1262 字节文件，U-Boot 因而只提供 1262 字节输出空间，
但 zstd frame 必须输出完整的 4096 字节。U-Boot 的 zstd wrapper 会把这个
容量原样传给 `zstd_decompress_dctx()`，后者返回错误 70。

U-Boot 自带错误枚举将 70 定义为 `ZSTD_error_dstSize_tooSmall`，参见
[`include/linux/zstd_errors.h`](https://github.com/u-boot/u-boot/blob/v2026.04/include/linux/zstd_errors.h#L52-L58)。
原始读取逻辑见
[`fs/btrfs/inode.c`](https://github.com/u-boot/u-boot/blob/v2026.04/fs/btrfs/inode.c#L361-L410)，
zstd wrapper 见
[`lib/zstd/zstd.c`](https://github.com/u-boot/u-boot/blob/v2026.04/lib/zstd/zstd.c#L14-L55)。

截至 2026-08-14，U-Boot `next` 的 commit
[`5a92645e`](https://github.com/u-boot/u-boot/commit/5a92645e1f9020d24d19e03fff2ae63f30080770)
仍按 `ram_bytes` 分配缓冲区，因此上游尚未修复该问题。

## 为什么初始镜像能启动，部署后却不能

故障时序如下：

1. 构建镜像时，`mkfs.btrfs -r --compress zstd:6` 创建 `/boot` 文件；这些
   frame 的解压长度就是文件真实长度，碰巧符合 U-Boot 的错误假设。
2. 初次启动成功。
3. `nixos-rebuild` 或 deploy-rs 运行 extlinux builder。builder 先在
   `/boot/extlinux` 中创建临时文件，再用 `mv -f` 替换
   `extlinux.conf`；kernel、initrd 和 DTB 也会在 `/boot/nixos` 下创建新
   inode。参见 nixpkgs 的
   [`extlinux-conf-builder.sh`](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/nixos/modules/system/boot/loader/generic-extlinux-compatible/extlinux-conf-builder.sh)。
4. 如果这些目录继承根文件系统的 zstd 压缩属性，Linux 会生成解压长度为
   一个 sector 的压缩内联文件。
5. 下次启动时，U-Boot 甚至无法读出 `extlinux.conf`，所以控制权从未进入
   Linux，也不会出现内核日志。

## U-Boot 修复

在临时 U-Boot 2026.04 sandbox 中，将压缩内联 extent 的解压缓冲区改为
Btrfs sector 大小：

```diff
 dsize = btrfs_file_extent_ram_bytes(leaf, fi);
+dbuf_size = leaf->fs_info->sectorsize;
 cbuf = malloc(csize);
-dbuf = malloc(dsize);
+dbuf = malloc(dbuf_size);
 ...
-ret = btrfs_decompress(..., dbuf, dsize);
+ret = btrfs_decompress(..., dbuf, dbuf_size);
```

解压后仍然只向调用者复制 `dsize` 字节。重新构建 sandbox 后：

- 原先失败的 Linux 写入镜像成功读出 1262 字节；
- `mkfs.btrfs` 生成的镜像仍成功读出 1262 字节。

这项测试闭合了“Linux 产生 4096 字节 frame → U-Boot 输出缓冲区过小 →
错误 70”的因果链。修复已提交到
[`gaoyifan/u-boot@ef064173`](https://github.com/gaoyifan/u-boot/commit/ef064173324d9fc28e20e951ad97b6bc95101499)，
并由 [`pkgs/nanopi-r4s-uboot.nix`](../../pkgs/nanopi-r4s-uboot.nix) 固定该提交作为构建源码。
fork 中的 U-Boot 2026.10-rc2 sandbox 对 Linux 与 `mkfs.btrfs` 两类镜像均
读出 1262 字节，内容 CRC32 均为 `6b972e7f`；同一源码的 NanoPi R4S ARM
U-Boot derivation 也已成功构建。

## 当前规避方案

对于已经写入 SD 卡、仍运行旧 U-Boot 的 NanoPi R4S，规避方案仍是让 U-Boot
需要读取的整个 `/boot` 目录树使用 `compression=none`：

```console
btrfs property set /boot compression none
find /boot -type d -exec btrfs property set '{}' compression none ';'
```

属性只影响之后创建或重写的 extent，不会原地解压已经存在的 extent。因此
必须在下一次 NixOS bootloader 更新之前设置，并确保
`/boot/extlinux`、`/boot/nixos` 以及后续新建的子目录继承该属性。本仓库暂时
保留 `btrfs-boot-no-compression` 服务，以免现有卡片在仅更新 NixOS、尚未
重刷修复后的 U-Boot 时失去启动能力，见
[`nixos/optional/nanopi-r4s.nix`](../../nixos/optional/nanopi-r4s.nix)。

单独使用不压缩的 FAT/ext4 boot 分区也能绕开 U-Boot 的 Btrfs 解压路径，
但会改变现有分区和部署布局。相比之下，修复 U-Boot 的缓冲区长度可以保留
当前单一 Btrfs 根分区设计。

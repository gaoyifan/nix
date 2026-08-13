# `nixos-rpi3b-cardio` 对 NanoPi R4S 镜像的参考价值

## 范围与版本

本笔记只评估镜像文件系统、镜像尺寸、首启扩容和启动链。研究对象为：

- `cardio-angel/nixos-rpi3b-cardio` 的 `e8dcba6f2521a02cc97eacc8c36b125bcbb6378d`，锁定 nixpkgs `566acc07c54dc807f91625bb286cb9b321b5f42a`（[`flake.lock:3-16`](https://github.com/cardio-angel/nixos-rpi3b-cardio/blob/e8dcba6f2521a02cc97eacc8c36b125bcbb6378d/flake.lock#L3-L16)）。
- 本仓库 HEAD `83c004adac1f0eed3f1e4ce4be4f55f3d1130772`，锁定 nixpkgs `531670d871c0e29724a02f3cbcac170adc65b58c`（[`flake.lock:402-414`](../../flake.lock#L402)）。
- 两个 nixpkgs 锁定版本的 `nixos/lib/make-btrfs-fs.nix` 逐字相同；本仓库当前的 `btrfs-progs.version` 和参考仓库的该值也都求值为 `6.19.1`。

复现版本检查：

```bash
nix eval --raw .#nixosConfigurations.cjia.pkgs.btrfs-progs.version
# 在参考仓库：
nix eval --raw .#nixosConfigurations.rpi3b.pkgs.btrfs-progs.version
```

## 结论

该仓库对 R4S **有直接参考价值**，而且给出了当前讨论中缺失的四块完整实现：

1. 用自定义 `rootFilesystemCreator` 在制镜像阶段执行 `mkfs.btrfs --compress zstd:6 --shrink`；
2. 让 U-Boot 能从压缩 Btrfs 根分区读取 `/boot/extlinux/extlinux.conf`、内核、initrd 和 DTB；
3. 让 initrd 挂载 Btrfs 根；
4. 把首启的 ext4 专用 `resize2fs` 换成 `btrfs filesystem resize max /`。

其中第 1、3、4 项可按 R4S 配置直接改写；第 2 项的**思路**可直接复用，但必须改 R4S 自己的 U-Boot 包，不能复制 Raspberry Pi 的固件或包名。若继续把 `/boot` 放在根分区，这四项缺一不可。

参考仓库的实际测量证明了“创建时压缩”这一方向有效：同一份 Pi 根文件系统从 ext4 的 `2.966 GiB` 已用空间降到 Btrfs zstd:6 的 `1.745 GiB`，而未压缩 Btrfs 仅比 ext4 少 `14.9 MiB`（[`docs/rpi3b-image-space.md:75-104`](https://github.com/cardio-angel/nixos-rpi3b-cardio/blob/e8dcba6f2521a02cc97eacc8c36b125bcbb6378d/docs/rpi3b-image-space.md#L75-L104)）。这个数值只适用于其 Pi 闭包，不能直接套算 cjia，但它说明只切换 Btrfs 而不在 `mkfs` 阶段压缩没有意义。

## 当前 R4S 与参考实现的共同基础

两边都使用 nixpkgs 的通用 `sd-image.nix` 组装两分区 MBR 镜像。该模块：

- `rootFilesystemCreator` 默认是 `make-ext4-fs.nix`，但选项明确允许换成 `make-btrfs-fs.nix`（[nixpkgs `sd-image.nix:131-143`](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/nixos/modules/installer/sd-card/sd-image.nix#L131-L143)）；
- 用根文件系统镜像的 apparent size，加上前置空隙和 30 MiB firmware 分区，计算最终 `.img` 大小（[同文件 `:321-339`](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/nixos/modules/installer/sd-card/sd-image.nix#L321-L339)）；
- 把根文件系统镜像逐扇区复制进第二分区（[同文件 `:341-343`](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/nixos/modules/installer/sd-card/sd-image.nix#L341-L343)）；
- 默认把 `/` 声明成 ext4（[同文件 `:253-268`](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/nixos/modules/installer/sd-card/sd-image.nix#L253-L268)）；
- 首启扩分区后无条件运行 ext4 的 `resize2fs`（[同文件 `:380-409`](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/nixos/modules/installer/sd-card/sd-image.nix#L380-L409)）。

所以无需重写整个 SD 镜像组装器。最小改动面就是 `rootFilesystemCreator`、根文件系统类型和首启扩容配置。

当前 ext4 creator 先按文件 apparent size 的 120% 粗估，再运行 `resize2fs -M`，最后增加 16 MiB（[nixpkgs `make-ext4-fs.nix:64-102`](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/nixos/lib/make-ext4-fs.nix#L64-L102)）。这解释了为什么当前 ext4 镜像即使 `df` 显示有空闲块，也不能从末尾继续大幅裁剪。

## 可以复用的具体实现

### 1. 创建时压缩的 Btrfs creator

参考仓库 vendored 了 nixpkgs 的 creator，只做了两处实质变化：用 user namespace 记录 root ownership，并给 `mkfs.btrfs` 增加 `--compress zstd:6`；`--shrink` 让输出文件按实际内容收缩（[`make-btrfs-fs.nix:42-81`](https://github.com/cardio-angel/nixos-rpi3b-cardio/blob/e8dcba6f2521a02cc97eacc8c36b125bcbb6378d/hosts/rpi3b/make-btrfs-fs.nix#L42-L81)）。上游 creator 只有 `mkfs.btrfs -r ... --shrink`，没有初始压缩（[nixpkgs `make-btrfs-fs.nix:37-70`](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/nixos/lib/make-btrfs-fs.nix#L37-L70)）。

这个文件的函数参数与本仓库锁定的上游 creator 兼容，可以作为 R4S 实现的起点。应保留创建时的 `--compress`；只在运行时给 mount 增加 `compress=zstd` 不会重新压缩镜像里已经写入的 Nix store，参考仓库也明确测量并记录了这一点（[`rpi3b-image-space.md:75-96`](https://github.com/cardio-angel/nixos-rpi3b-cardio/blob/e8dcba6f2521a02cc97eacc8c36b125bcbb6378d/docs/rpi3b-image-space.md#L75-L96)）。

不过，不应原样照抄文件头中“`mkfs.btrfs >= 7.0`”的版本判断（[`make-btrfs-fs.nix:7-10`](https://github.com/cardio-angel/nixos-rpi3b-cardio/blob/e8dcba6f2521a02cc97eacc8c36b125bcbb6378d/hosts/rpi3b/make-btrfs-fs.nix#L7-L10)）：两个锁定配置实际都求值为 `btrfs-progs 6.19.1`。user namespace 方案仍可避免依赖 fakeroot 是否拦截 `mkfs.btrfs` 的 ownership 查询，但在本仓库 builder 上应通过构建后检查镜像内 `/` 与 `/nix/store` 的 uid/gid 来验证，而不是依赖那条版本注释。参考仓库的 CI 还必须先允许 unprivileged user namespaces，说明这是一个真实的构建环境要求（[`.github/workflows/build-image.yml:47-57`](https://github.com/cardio-angel/nixos-rpi3b-cardio/blob/e8dcba6f2521a02cc97eacc8c36b125bcbb6378d/.github/workflows/build-image.yml#L47-L57)）。

### 2. 根文件系统和 initrd 设置

参考仓库把 `sdImage.rootFilesystemCreator` 指向自定义文件，让 initrd 同时带 Btrfs/ext4，并把根文件系统类型设成 `auto`（[`hardware.nix:9-30`](https://github.com/cardio-angel/nixos-rpi3b-cardio/blob/e8dcba6f2521a02cc97eacc8c36b125bcbb6378d/hosts/rpi3b/hardware.nix#L9-L30)）。同时支持 ext4 是因为同一份配置还会部署到旧 ext4 设备，这是源码明确记录的迁移要求。

R4S 若只生成并刷入新的 Btrfs 镜像，应复用 creator 和 initrd Btrfs 支持，但将 `/` 明确设为 `btrfs`；无需复制 `fsType = "auto"` 和 ext4 兼容层。只有计划把同一 generation 部署到仍运行 ext4 的 somo/cjia 时，才有参考仓库所面对的具体兼容需求。

参考仓库为了兼容旧 ext4，使用 oneshot 在检测到 Btrfs 后 remount `compress=zstd:3`（[`hardware.nix:32-44`](https://github.com/cardio-angel/nixos-rpi3b-cardio/blob/e8dcba6f2521a02cc97eacc8c36b125bcbb6378d/hosts/rpi3b/hardware.nix#L32-L44)）。纯 Btrfs R4S 不需要这个兼容 service，可直接给 `/` 设置 Btrfs mount option。

### 3. 首启扩容

参考仓库保留上游的分区扩展步骤，只按实际文件系统选择 `btrfs filesystem resize max /` 或 `resize2fs`（[`hardware.nix:61-75`](https://github.com/cardio-angel/nixos-rpi3b-cardio/blob/e8dcba6f2521a02cc97eacc8c36b125bcbb6378d/hosts/rpi3b/hardware.nix#L61-L75)）。本仓库锁定的 NixOS 已原生提供 `boot.growPartition` 和 `fileSystems."/".autoResize`，并支持 Btrfs，因此 R4S 无需复制这段 shell 脚本。

### 4. 给 R4S U-Boot 增加 Btrfs 读取能力

当前 R4S 把 extlinux 的 `/boot` 放在根分区（[`nixos/optional/nanopi-r4s.nix:33-38`](../../nixos/optional/nanopi-r4s.nix#L33)），而不是空的 FAT firmware 分区；U-Boot 因而必须理解根文件系统。

参考仓库通过 override `ubootRaspberryPi3_64bit`，追加 `CONFIG_FS_BTRFS=y`、`CONFIG_CMD_BTRFS=y` 和 `CONFIG_ZSTD=y`（[`hardware.nix:46-59`](https://github.com/cardio-angel/nixos-rpi3b-cardio/blob/e8dcba6f2521a02cc97eacc8c36b125bcbb6378d/hosts/rpi3b/hardware.nix#L46-L59)）。R4S 不能复制包名，但其本地包同样调用 nixpkgs `buildUBoot`（[`pkgs/nanopi-r4s-uboot.nix:1-9`](../../pkgs/nanopi-r4s-uboot.nix#L1)），而 `buildUBoot` 原生接受并在 defconfig 后追加 `extraConfig`（[nixpkgs `pkgs/misc/uboot/default.nix:52-75`](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/pkgs/misc/uboot/default.nix#L52-L75)，[`:118-125`](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/pkgs/misc/uboot/default.nix#L118-L125)）。因此这个思路可直接落实在 `pkgs/nanopi-r4s-uboot.nix`。

本仓库锁定的 U-Boot 是 Denx `2026.04`：nixpkgs 从官方 tarball 获取（[nixpkgs `default.nix:36-41`](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/pkgs/misc/uboot/default.nix#L36-L41)）。该版本的 `FS_BTRFS` 会自动选择 ZSTD，并声明为单设备只读 Btrfs 支持（[U-Boot `fs/btrfs/Kconfig:1-13`](https://source.denx.de/u-boot/u-boot/-/blob/v2026.04/fs/btrfs/Kconfig#L1-L13)）；其 Btrfs reader 能解压 zstd extents（[U-Boot `fs/btrfs/compression.c:135-167`](https://source.denx.de/u-boot/u-boot/-/blob/v2026.04/fs/btrfs/compression.c#L135-L167)）。`FS_BTRFS` 还把 Btrfs read/probe 注册到通用文件系统接口，extlinux bootmethod 正是通过通用 boot file reader 取文件（[U-Boot `fs/fs.c:319-338`](https://source.denx.de/u-boot/u-boot/-/blob/v2026.04/fs/fs.c#L319-L338)，[`boot/bootmeth_extlinux.c:71-89`](https://source.denx.de/u-boot/u-boot/-/blob/v2026.04/boot/bootmeth_extlinux.c#L71-L89)）。

所以最小必要配置是 `CONFIG_FS_BTRFS=y`；它已经选择 `ZSTD`。参考仓库的 `CONFIG_CMD_BTRFS=y` 会选择 `FS_BTRFS`，但该 command 只增加 `btrsubvol` 命令，普通列目录和读文件走通用 fs 命令（[U-Boot `cmd/Kconfig:2862-2871`](https://source.denx.de/u-boot/u-boot/-/blob/v2026.04/cmd/Kconfig#L2862-L2871)）。为了保持配置直接清楚，可以沿用参考仓库三项；为了最小化，则只加 `CONFIG_FS_BTRFS=y`。

我还检查了当前实际构建出的 R4S `u-boot.itb`：解出 `u-boot` payload 后，strings 中有 `ext4load`、`ext4ls`、`ext4size` 和 `extlinux/extlinux.conf`，没有 `btrfs`。这与当前 `nanopi-r4s-rk3399_defconfig` 未启用 Btrfs 一致（[U-Boot defconfig](https://source.denx.de/u-boot/u-boot/-/blob/v2026.04/configs/nanopi-r4s-rk3399_defconfig)）。因此当前镜像不能在不改 U-Boot 的情况下把含 `/boot` 的根分区直接换成 Btrfs。

检查方式（`dumpimage` 来自 `ubootTools`）：

```bash
out=$(nix build --no-link --print-out-paths \
  .#nixosConfigurations.cjia.pkgs.nanopi-r4s-uboot)
dumpimage -T flat_dt -p 0 -o u-boot.bin "$out/u-boot.itb"
strings u-boot.bin | grep -Ei 'btrfs|ext4(load|ls|size)|extlinux'
```

## Raspberry Pi 启动链中不能复用的部分

Pi 配置导入 `sd-image-aarch64.nix`（[`flake.nix:14-19`](https://github.com/cardio-angel/nixos-rpi3b-cardio/blob/e8dcba6f2521a02cc97eacc8c36b125bcbb6378d/flake.nix#L14-L19)）。该模块把 Raspberry Pi GPU firmware、`config.txt`、Pi DTB 和 `u-boot-rpi3.bin` 放入 FAT firmware 分区，由 Pi firmware 根据 `kernel=u-boot-rpi3.bin` 加载 U-Boot（[nixpkgs `sd-image-aarch64.nix:30-100`](https://github.com/NixOS/nixpkgs/blob/566acc07c54dc807f91625bb286cb9b321b5f42a/nixos/modules/installer/sd-card/sd-image-aarch64.nix#L30-L100)）。

R4S 没有这一级 Raspberry Pi GPU firmware。它当前：

- 导入通用 `sd-image.nix`；
- 保留 16 MiB 前置区域、让 firmware 分区为空；
- 把 Rockchip `idbloader.img` 写到 sector 64（32 KiB），把 `u-boot.itb` 写到 sector 16384（8 MiB）；
- 把 extlinux 文件放在根分区 `/boot`。

这些都由 [`nixos/optional/nanopi-r4s.nix:8-42`](../../nixos/optional/nanopi-r4s.nix#L8) 明确配置。因此以下内容不能从参考仓库复制：Pi 的 `config.txt`、`raspberrypifw`、`u-boot-rpi3.bin`、Pi DTB、`ubootRaspberryPi3_64bit` overlay 名称，以及 Pi 的 UART/Bluetooth/device-tree 设置。

参考仓库也没有展示“把 `/boot` 移到 FAT”方案；它恰恰选择重新编译 U-Boot，让 U-Boot 从 Btrfs 根读取 `/boot`。对当前 R4S 布局而言，这是改动更集中的路线，因为无需重新定义分区职责和 extlinux 搜索位置，但仍必须保留 Rockchip idbloader/ITB 的固定写入偏移。

## 镜像尺寸方面能得出的和不能得出的结论

能够确定：

- 最终 raw `.img` 的大小跟随 root filesystem image 的文件长度，所以 `mkfs.btrfs --compress ... --shrink` 只要产生更短的 rootfs 文件，就会等量缩短最终镜像（nixpkgs 组装逻辑见上文 `sd-image.nix:321-343`）。
- 参考仓库的同闭包测试中，初始 zstd:6 大幅降低 Btrfs 已用空间；未压缩 Btrfs 没有实质收益（[`rpi3b-image-space.md:86-100`](https://github.com/cardio-angel/nixos-rpi3b-cardio/blob/e8dcba6f2521a02cc97eacc8c36b125bcbb6378d/docs/rpi3b-image-space.md#L86-L100)）。
- 外层 `.img.zst` 不一定更小，因为根文件系统内部已经压缩；参考仓库实测其外层文件反而变大（[同文件 `:102-104`](https://github.com/cardio-angel/nixos-rpi3b-cardio/blob/e8dcba6f2521a02cc97eacc8c36b125bcbb6378d/docs/rpi3b-image-space.md#L102-L104)）。

不能据此确定：

- cjia 会缩小多少。Pi 测试闭包约 3 GiB，而 cjia 的 store 内容和文件可压缩性不同，必须构建后比较 rootfs apparent size 和最终 `.img`。
- Btrfs 会回收 ext4 `df` 所显示的全部空闲空间。两种文件系统的 metadata、chunk allocation 和最小可用空间规则不同；正确指标是实际产出的镜像长度及挂载后的可用空间，而不是拿 ext4 的 free blocks 直接相减。

## 建议的 R4S 落地边界

若决定实施，建议只做以下范围：

1. vendored 一个与参考仓库同结构、带初始 zstd 压缩的 Btrfs creator；
2. `sdImage.rootFilesystemCreator` 指向它，`/` 明确设为 Btrfs，并确保 initrd 支持 Btrfs；
3. R4S `buildUBoot` 开启 `FS_BTRFS`，继续生成和写入现有 `idbloader.img`/`u-boot.itb`；
4. 使用 `boot.growPartition` 和 `fileSystems."/".autoResize` 完成首启扩容；
5. 构建后验证 U-Boot payload 确实含 Btrfs、镜像 ownership 正确，并在 R4S 实机串口验证从压缩 Btrfs 读取 extlinux/kernel/initrd/DTB 和首启扩容。

不要顺带复制 Pi 专用启动文件、双 ext4/Btrfs 兼容 service、Bluetooth overlay 或镜像裁包策略。参考仓库关于删除 registry、精简 firmware/default packages 的数据（[`rpi3b-image-space.md:106-133`](https://github.com/cardio-angel/nixos-rpi3b-cardio/blob/e8dcba6f2521a02cc97eacc8c36b125bcbb6378d/docs/rpi3b-image-space.md#L106-L133)）可另行评估，但不属于把 R4S 根文件系统换成 Btrfs 所必需的实现。

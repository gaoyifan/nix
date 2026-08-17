# 小内存主机的 NixOS 全盘镜像安装方案

调研日期：2026-08-15。

## 结论

对于 1 GiB 及以下内存的虚拟机，推荐把分区、格式化、Nix store 复制和
bootloader 安装移到构建机，在目标机的 kexec 环境中用 rsync 把 raw image 直接写入
块设备，然后重启。这避免在目标机的 tmpfs Nix store 中运行 Nix daemon、GC、disko
和 `nixos-install`。需要保留旧主机状态的迁移不属于通用安装流程，必须在重启前单独
恢复和演练。

镜像不应按生产磁盘的完整容量构建。应生成能够容纳系统闭包的最小镜像，并在首次
启动时扩展最后一个 root partition 及其文件系统。固定 30 GiB raw image
仍需向磁盘写入 30 GiB；约 6 GiB 的可扩容镜像可以直接把生产写盘量降低到约
五分之一。

当前上游源码表明这条扩容链路是有意支持的。本仓库同时测试 UEFI + GPT + Btrfs
和 BIOS + MBR + ext4，覆盖两种常见启动环境。

## 已确认的上游能力

仓库锁定 disko
[`ff8702b4de27f72b4c78573dfb89ec74e36abdf1`](https://github.com/nix-community/disko/tree/ff8702b4de27f72b4c78573dfb89ec74e36abdf1)。
其 image builder 可直接从已有 NixOS + disko 配置生成 `.raw` 镜像：

- `system.build.diskoImages` 在 build VM 中运行分区脚本和 `nixos-install`；
- `system.build.diskoImagesScript` 把镜像生成到当前目录，适合把大文件放到
  `/pool0/playground`，而不是 Nix store；
- `disko.devices.disk.<name>.imageSize` 控制 raw image 的构建容量；
- `--post-format-files` 可以注入状态，但文件最终归 root 所有。

这些接口及行为见 disko 的
[`disko-images.md`](https://github.com/nix-community/disko/blob/ff8702b4de27f72b4c78573dfb89ec74e36abdf1/docs/disko-images.md#L1-L116)
和
[`make-disk-image.nix`](https://github.com/nix-community/disko/blob/ff8702b4de27f72b4c78573dfb89ec74e36abdf1/lib/make-disk-image.nix#L140-L195)。
builder 会复制目标闭包、建立 Nix DB，并运行目标系统自己的 `nixos-install`，所以
生成的是完整可启动系统，不是只含安装器的 bootstrap rootfs。

仓库锁定 Nixpkgs
[`531670d871c0e29724a02f3cbcac170adc65b58c`](https://github.com/NixOS/nixpkgs/tree/531670d871c0e29724a02f3cbcac170adc65b58c)。
其扩容分为两个有明确顺序的步骤：

1. `boot.growPartition = true` 生成 `growpart.service`。该 unit 从 root device
   推导父磁盘和分区号，调用 cloud-utils `growpart`，并显式排在
   `systemd-growfs-root.service` 之前，见
   [`grow-partition.nix`](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/nixos/modules/system/boot/grow-partition.nix#L19-L59)。
2. `fileSystems."/".autoResize = true` 添加 `x-systemd.growfs` mount option。
   当前 NixOS assertion 明确允许 `btrfs`，见
   [`filesystems.nix`](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/nixos/modules/tasks/filesystems.nix#L210-L218)
   和
   [`filesystems.nix`](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/nixos/modules/tasks/filesystems.nix#L231-L244)。

Nixpkgs 自己的 GCE profile 也同时启用 `boot.growPartition` 和 root
`autoResize`，见
[`google-compute-config.nix`](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/nixos/modules/virtualisation/google-compute-config.nix#L17-L35)。
它使用 ext4，因此只能证明云镜像的整体机制；Btrfs 和当前三分区布局仍需本仓库
自行验证。

Nixpkgs 的 [`make-disk-image.nix`](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/nixos/lib/make-disk-image.nix#L32-L47)
原生支持 `partitionTableType = "legacy"`，生成带单个 ext4 root partition 的 MBR
镜像并安装 BIOS GRUB。disko 的 legacy `table` 类型明确警告它与 image/test framework
的 module extension 不兼容，因此 BIOS + MBR 验收直接使用 Nixpkgs builder，不为此
增加仓库内的兼容包装。

本仓库的 NanoPi R4S 镜像已经对 Btrfs 使用同一组
`boot.growPartition` + `autoResize` 设置，见
[`nixos/optional/nanopi-r4s.nix`](../../nixos/optional/nanopi-r4s.nix#L8-L35)。
这进一步说明扩容应由目标 NixOS 首次启动负责，不需要在写盘工具中实现另一套
分区扩展脚本。

## 推荐镜像结构

沿用目标主机的实际 disko 布局，避免维护第二份分区定义。以 `google` 为例，当前
[`disk-config.nix`](../../nixos/hosts/google/disk-config.nix) 已经满足扩容的关键条件：

- GPT partition 1：1 GiB ESP；
- GPT partition 2：1 GiB swap；
- GPT partition 3：Btrfs root，且是磁盘最后一个分区；
- GRUB 以 removable EFI 路径安装，可从 GCE UEFI 启动。

当前 `google` system closure 约 2.0 GiB。第一轮测试可以把
`disko.devices.disk.system.imageSize` 设为 6 GiB，使 root partition 约为
4 GiB。最终大小应根据实际构建结果留出明确余量，而不是写死为所有主机通用值。

`flake.lib.mkNixosDiskImage` 从任意满足上述布局约束的 host config 派生构建 variant，
不改变普通运行中的 host profile：

```nix
flake.lib.mkNixosDiskImage {
  host = flake.nixosConfigurations.target;
  imageSize = "6G";
}
```

当前 interface 支持恰好包含一个 disko disk、root 是该磁盘最后一个可扩分区的 host。
它从配置取得磁盘名和 hostname；调用方只提供 host 与按其闭包核算的 `imageSize`。
未来主机确定布局和容量后，可把返回配置的 `config.system.build.diskoImagesScript`
暴露为 package。Google 只作为测试 fixture，不增加专用 configuration 或 builder package。

## VM 扩容测试

测试覆盖两条实际启动链路：把 Google 的 6 GiB UEFI + GPT + Btrfs 镜像接到
30 GiB QEMU 磁盘；把 4 GiB BIOS + MBR + ext4 镜像接到 8 GiB 磁盘。两者都从镜像
自己的 GRUB 启动，而不是只对临时文件手工运行 `growpart`。

第一次 UEFI 启动后的验收条件：

1. 固件确实以 UEFI 启动，partition table 仍为 GPT；
2. 最后一个 root partition 的 start 不变，end 扩展到磁盘末尾；
3. `growpart.service` 的日志为 `CHANGED`；
4. Btrfs 文件系统容量接近新的 partition 大小。

随后再重启一次，验证 partition table 和 Btrfs 大小不再变化，`growpart` 返回
`NOCHANGE`。

BIOS + MBR 验收还要求固件环境中不存在 EFI runtime、partition table 保持 DOS/MBR、
唯一的 root partition 扩展到磁盘末尾、ext4 随后扩容，并在第二次启动时保持不变。

## 实现与 VM 验收记录

已加入通用的 `flake.lib.mkNixosDiskImage`，设置 `boot.growPartition`、root
`autoResize` 以及唯一 disko disk 的 `imageName`/`imageSize`。测试以现有 Google host
调用同一 interface；仓库不增加没有实际部署用途的 Google bootstrap output。

`checks.x86_64-linux.low-memory-disk-image` 同时验收 UEFI + GPT + Btrfs 和 BIOS +
MBR + ext4；发送和接收不再维护专用程序。

验收命令为：

```sh
nix build --accept-flake-config --no-link \
  '.#checks.x86_64-linux.low-memory-disk-image'
```

UEFI 测试使用 1 GiB 内存、真实 GPT + ESP + swap + Btrfs 镜像，并通过 SSH
检查目标系统，而不是替换目标系统的启动流程。接到 30 GiB 磁盘后，partition 3 从
8,384,512 sectors 扩展到 58,718,175 sectors，Btrfs 容量超过 25 GB。第二次重启后
分区表和 Btrfs 大小保持不变，`growpart` 返回 `NOCHANGE`。UEFI 路径首次启动约
104 秒；完整测试约 246 秒（当前环境使用 TCG）。

BIOS 测试使用 1 GiB 内存，从 MBR 中的 GRUB 启动，验证单个 ext4 root partition
从 4 GiB 镜像扩展到 8 GiB 磁盘并在第二次启动时保持不变。

此外，`just fmt-check`、`just check` 和 `nix flake check --no-build` 均通过。

## 生产写盘流程

生产流程不在目标端运行 Nix 构建：

```text
build host
  -> diskoImagesScript 生成小型 raw image
  -> rsync 通过 SSH 直接写入明确的 by-id 磁盘
  -> 操作者核对结果并重启
  -> NixOS 首启扩展 root partition 和文件系统
```

`nixos-disk-writer-kexec` 已有 OpenSSH 和 rsync，不需要增加专用程序、协议或额外
runtime package。rsync 不把完整镜像读入 RAM，并使用目标块设备作为 delta transfer
的 basis。

生产命令示例：

```sh
rsync --ignore-times --no-whole-file --write-devices --fsync \
  --compress-choice=zstd --compress-level=3 --info=progress2 \
  target-disk-image.raw \
  root@target:/dev/disk/by-id/target-disk
```

`--write-devices` 允许直接写块设备并隐含 `--inplace`；`--ignore-times` 防止按设备
metadata 跳过传输；`--no-whole-file` 启用 delta transfer；`--fsync` 在成功返回前同步
写入。网络中断后重跑同一命令，rsync 会重新扫描源和目标范围，但只传输并改写不同块。
块签名是 delta transfer 本身的一部分，不再叠加独立的流式或写后校验。详细依据和取舍见
[`resumable-disk-image-transfer.md`](./resumable-disk-image-transfer.md)。

设备路径由操作者在执行前用 `lsblk` 核对；个人项目不再为极少发生的目标盘过小、
serial 二次确认或 mounted/swap 检测维护额外程序。

旧设计中的 `--serial` 用来把用户提供的值与 `lsblk SERIAL` 再比较一次，以降低写错盘
的风险。既然专用写盘程序已经删除，这个参数也没有保留；执行前查看一次 `lsblk` 即可。

## 状态和 secrets

构建产物不得包含 SSH host private key、Tailscale state、Nylon private key 或
Home SSH private key。否则这些内容会进入 raw artifact，且可能进一步进入 Nix
store 或 binary cache。

通用安装工具不会恢复旧主机状态。迁移场景必须在重启前另行挂载新的 Btrfs root，
把经过核对的状态归档从迁移工作站直接流式解包进去，并保留 numeric owners：

- `/etc/ssh/ssh_host_*`；
- `/var/lib/tailscale`；
- `/etc/nylon`；
- `/home/yifan/.ssh` 及必要的 shell state。

disko 的 `--post-format-files` 会把注入文件设为 root 所有，因此不适合直接恢复
Home SSH。这个步骤依赖具体主机的状态清单、owner 和信任关系，不应塞进通用写盘命令。
不需要迁移旧状态时，写盘成功后直接执行 `ssh <host> reboot`。

## 最终判断

小型全盘镜像加首次启动自动扩容是当前最有希望的低内存迁移路径。它同时消除了
目标端 RAM Nix store、远程 Nix GC 和大规模 closure 下载，并显著减少生产写盘量。

通用单磁盘 image interface 和 QEMU 验收测试现已完成：UEFI + GPT + Btrfs 覆盖 6 GiB 到
30 GiB，BIOS + MBR + ext4 覆盖 4 GiB 到 8 GiB，两者都验证第二次启动幂等。生产写盘
使用 rsync 直接写块设备，并可在中断后重跑续传。状态归档恢复属于具体迁移流程，仍需
单独实现和演练；在此之前不要把 secrets 写入通用镜像。

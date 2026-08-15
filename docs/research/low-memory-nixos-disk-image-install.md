# 小内存主机的 NixOS 全盘镜像安装方案

调研日期：2026-08-15。

## 结论

对于 1 GiB 及以下内存的虚拟机，推荐把分区、格式化、Nix store 复制和
bootloader 安装移到构建机，在目标机的 kexec 环境中只执行压缩镜像的流式写盘、
状态恢复和重启。这避免在目标机的 tmpfs Nix store 中运行 Nix daemon、GC、disko
和 `nixos-install`。

镜像不应按生产磁盘的完整容量构建。应生成能够容纳系统闭包的最小镜像，并在首次
启动时扩展最后一个 root partition 及其 Btrfs 文件系统。固定 30 GiB raw image
即使用 zstd 传输，解压后的 `dd` 仍需向磁盘写入 30 GiB；约 6 GiB 的可扩容镜像
可以直接把生产写盘量降低到约五分之一。

当前上游源码表明这条扩容链路是有意支持的，但本仓库的 GPT + ESP + swap +
Btrfs 布局仍须先通过 VM 测试。测试通过前，这个方案不能替代现有安装流程。

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

本仓库的 NanoPi R4S 镜像已经对 Btrfs 使用同一组
`boot.growPartition` + `autoResize` 设置，见
[`nixos/optional/nanopi-r4s.nix`](../../nixos/optional/nanopi-r4s.nix#L8-L35)。
这进一步说明扩容应由目标 NixOS 首次启动负责，不需要在 writer 中实现另一套
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

目标 profile 需要增加：

```nix
{
  boot.growPartition = true;
  fileSystems."/".autoResize = true;
  disko.devices.disk.system = {
    imageName = "google-bootstrap";
    imageSize = "6G";
  };
}
```

镜像配置应作为仅用于构建镜像的 variant 导入；运行中的普通 host profile 不需要
暴露 image builder 选项。

## VM 扩容测试

先用当前 host profile 构建 6 GiB raw image，再把它接到 30 GiB 的 QEMU
磁盘。测试必须覆盖真实的 UEFI、GPT、分区顺序和 Btrfs，而不是只对一个临时文件
手工运行 `growpart`。

第一次启动前记录：

- raw image 的压缩和解压大小、构建时间；
- GPT 主/备份表位置；
- partition 3 的结束 sector；
- Btrfs `device size` 和 `df` 容量。

第一次 UEFI 启动后的验收条件：

1. GRUB 从 removable EFI 路径启动目标 generation；
2. `growpart.service` 成功，或只返回其被 NixOS 接受的退出码；
3. GPT backup header 被移动到 30 GiB 磁盘末尾，`sgdisk -v` 无错误；
4. partition 1 和 2 的 start、size、PARTUUID 均未改变；
5. partition 3 扩展到磁盘末尾，保留合理的 GPT 尾部空间；
6. `systemd-growfs-root.service` 在 `growpart.service` 后成功；
7. Btrfs 可用容量接近 28 GiB，现有数据和 Nix DB 可读；
8. swap、ESP、root mount options 与 host 配置一致；
9. SSH、networkd 和串口均可用。

随后再重启一次，验证扩容幂等：partition table 和 Btrfs 大小不再变化，启动日志
没有 GPT、growpart、growfs 或 Btrfs 错误。

还应执行两个边界测试：

- 把 6 GiB 镜像接到恰好 6 GiB 的磁盘，确认无可扩空间时仍能正常启动；
- 把镜像接到小于 6 GiB 的磁盘，writer 必须在写盘前按解压大小拒绝操作。

测试报告应保留 `lsblk -b`、`sfdisk --json`、`sgdisk -v`、
`btrfs filesystem usage /`、两个相关 systemd unit 的 journal，以及两次启动耗时。

## 生产写盘流程

生产流程只让目标端承担常量内存工作：

```text
build host
  -> diskoImagesScript 生成小型 raw image
  -> zstd 压缩并计算 SHA-256
  -> SSH / Nylon / MPLS 流式传输
  -> kexec writer: zstd -d | dd of=<已核对的 by-id 磁盘>
  -> 挂载新 root，流式恢复运行时状态
  -> reboot
  -> NixOS 首启扩展 partition 3 和 Btrfs
```

kexec writer 只需网络、OpenSSH、`zstd`、coreutils、util-linux、tar、Btrfs
驱动和用于只读核对磁盘的工具。它不应包含 Nix daemon、disko、
`nixos-install` 或目标 system closure。写盘使用 direct I/O 或等效方式，避免让
page cache 随镜像大小增长。

writer 在写盘前必须核对：

- 目标 by-id 路径解析到预期磁盘和 serial；
- 目标磁盘没有 mount 或 active swap；
- 目标磁盘容量不小于 raw image 的解压大小；
- 压缩镜像 SHA-256 与构建端记录一致。

SSH 提供传输完整性；`dd` 成功后仍需 flush，并在重启前重新读取 partition table。
传输中断时 writer 仍在 RAM 中，磁盘虽然暂时不可启动，但可以从头重写同一镜像。

## 状态和 secrets

构建产物不得包含 SSH host private key、Tailscale state、Nylon private key 或
Home SSH private key。否则这些内容会进入 raw artifact，且可能进一步进入 Nix
store 或 binary cache。

写盘完成后，在 writer 中挂载新的 Btrfs root，把经过核对的状态归档从迁移工作站
直接流式解包进去，并保留 numeric owners：

- `/etc/ssh/ssh_host_*`；
- `/var/lib/tailscale`；
- `/etc/nylon`；
- `/home/yifan/.ssh` 及必要的 shell state。

disko 的 `--post-format-files` 会把注入文件设为 root 所有，因此不适合直接恢复
Home SSH。把运行时状态与通用镜像分开，也使同一个 writer 和镜像构建机制可以用于
其他小内存主机。

## 最终判断

小型全盘镜像加首次启动自动扩容是当前最有希望的低内存迁移路径。它同时消除了
目标端 RAM Nix store、远程 Nix GC 和大规模 closure 下载，并显著减少生产写盘量。

下一步不是直接用于真实主机，而是实现一个 image-only variant 和 QEMU 验收测试。
只有 6 GiB 到 30 GiB 的 GPT + Btrfs 扩容、第二次启动幂等性以及小内存 writer
都通过后，才把该流程加入生产迁移工具。

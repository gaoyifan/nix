# 低内存主机的 NixOS 安装

## 目标

在构建机上生成可启动的 raw disk image，通过 SSH 写入目标磁盘，使只有 1 GiB
左右内存的未来主机不必在内存文件系统中运行 Nix、disko 或 `nixos-install`。

Google 主机只作为现有 NixOS 配置的测试样本，不是本方案的目标，也不拥有专用镜像配置。

## 适用范围

- 目标配置只有一块由 NixOS 接管的系统盘；
- root 是磁盘上的最后一个分区，可以占用剩余空间；
- 支持 UEFI + GPT 和 BIOS + MBR；
- 新安装不负责迁移旧系统的运行时数据或密钥。

多系统盘、RAID、加密根分区等布局应在出现实际需求时单独设计。

## 构建

每个 NixOS configuration 都会惰性暴露对应的 `diskImage`；只有构建指定目标时才会
求值该主机配置：

```sh
just build-disk-image target
```

该入口直接构建 `nixosConfigurations.<target>.diskImage`。不含单系统盘 disko 配置的
目标会在被请求时失败。NanoPi bootstrap SD image 使用独立的
`just build-nanopi-bootstrap-image` 入口。

为目标架构构建写盘环境：

```sh
nix build .#nixos-disk-writer-kexec
```

该 kexec image 只包含启动框架、SSH、rsync 和磁盘工具，不在目标机运行 Nix、disko
或 `nixos-install`。

通用 disko 路径在内部调用 `self.lib.mkNixosDiskImage`。它接收任意符合约束的 NixOS host 配置，
返回对应的安装镜像：

```nix
self.lib.mkNixosDiskImage {
  host = self.nixosConfigurations.target;
}
```

构建时会启用 `boot.growPartition` 和 root filesystem 的 `autoResize`，但不修改目标主机
正常部署所使用的配置。

UEFI + GPT 镜像使用 disko image builder。BIOS + MBR 镜像直接使用 Nixpkgs
`make-disk-image.nix` 的 `partitionTableType = "legacy"`。入口根据 disko partition table
选择 builder。镜像默认是 6 GiB。

## 写盘与续传

从目标机现有 Linux 系统上传并启动与其架构一致的 kexec tarball：

```sh
scp nixos-disk-writer-kexec-x86_64-linux.tar.gz root@target:/root/
ssh root@target tar -xzf /root/nixos-disk-writer-kexec-x86_64-linux.tar.gz -C /root
ssh root@target /root/kexec/run
./.agents/skills/nixos-reinstall/scripts/wait-for-ssh.sh --down root@target
./.agents/skills/nixos-reinstall/scripts/wait-for-ssh.sh root@target
ssh root@target test -e /etc/nixos-disk-writer-kexec
```

`run` 返回约 6 秒后才执行 kexec，因此必须先观察 SSH 中断，再等待新系统可连接。
PVE 7.1 / QEMU 6.1 i440FX 出现 initramfs 解压或 `/sysroot/nix/.ro-store` 挂载失败时，
给 `run` 增加 `--kexec-extra-flags "--kexec-syscall --mem-max=0xffffffff"`。

SSH 恢复后，用 `lsblk` 确认稳定的磁盘路径。rsync 会替换目标 symlink，而不是写入
symlink 指向的块设备，因此先在 kexec 系统中解析一次路径，再从构建机执行：

```sh
target_device=$(ssh root@target readlink -f /dev/disk/by-id/target-disk)
mountpoints=$(ssh root@target lsblk -no MOUNTPOINTS "$target_device")
test -z "$mountpoints"
rsync --ignore-times --no-whole-file --write-devices --fsync \
  --compress-choice=zstd --compress-level=3 --info=progress2 \
  target-disk-image.raw \
  "root@target:$target_device"
```

连接中断后重跑同一命令。rsync 会扫描源镜像和目标设备，仅重传不同的数据，因此目标
设备本身就是续传状态。重新扫描有顺序读取成本，但无需维护 checkpoint、发送端、接收端
或自定义协议。

写盘流程不额外执行磁盘容量下限、serial、流式 checksum 或写后读回校验。操作人负责
选择目标磁盘。rsync 成功后安排重启，等待旧 SSH 下线，再删除旧 host key 并等待新系统：

```sh
ssh root@target systemd-run --on-active=1s systemctl reboot
./.agents/skills/nixos-reinstall/scripts/wait-for-ssh.sh --down root@target
ssh-keygen -R target
./.agents/skills/nixos-reinstall/scripts/wait-for-ssh.sh root@target
```

## 首次启动

首次启动时，NixOS 扩展最后一个 root partition，随后扩展 root filesystem。后续启动
重复执行不会继续改变已经占满磁盘的布局。

## 验证

`checks.x86_64-linux.low-memory-disk-image` 在 1 GiB VM 中覆盖：

- 最小 UEFI + GPT + Btrfs 测试配置；
- 独立的 BIOS + MBR + ext4 镜像；
- 首次启动后的分区和文件系统扩容；
- 再次启动时扩容结果保持不变。

`checks.x86_64-linux.nixos-disk-writer-kexec` 覆盖基础系统启动、kexec、从部分写入状态继续
rsync、从新镜像重启以及 root 扩容的完整流程。

`checks.x86_64-linux.nixos-disk-image-google` 单独构建真实 Google 主机配置，避免 VM
测试载入与镜像机制无关的生产服务。

未来主机只要满足单系统盘、root 最后分区的约束，就可复用同一套写盘和首次启动流程。

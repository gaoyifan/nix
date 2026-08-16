# Raw disk image 断点续传

日期：2026-08-17

## 结论

默认写盘方法是让 rsync 直接把未压缩的 raw image 写到远端块设备，不维护专用
发送/接收程序。目标 kexec 环境已经包含 rsync，连接中断后重跑同一命令：

```sh
rsync --ignore-times --no-whole-file --write-devices --fsync \
  --compress-choice=zstd --compress-level=3 --info=progress2 \
  bootstrap.raw \
  root@target:/dev/disk/by-id/target-disk
```

rsync 3.2.0 加入 `--write-devices`，3.2.4 修复源文件短于目标设备时的行为，并允许
它使用 delta transfer。本仓库当前 Nixpkgs 提供的 rsync 是 3.4.4，已经包含这些修复。
详见官方 [rsync 3.2.4 NEWS](https://download.samba.org/pub/rsync/NEWS.html#3.2.4)
和 [`--write-devices` 手册](https://download.samba.org/pub/rsync/rsync.1#opt--write-devices)。

这些参数各自只有一个必要职责：

- `--write-devices` 允许写块设备，并隐含 `--inplace`，因此目标设备本身就是续传基准；
- `--ignore-times` 禁止按大小和时间戳跳过整个目标；
- `--no-whole-file` 强制使用 delta transfer，重跑时扫描两端并只发送不同块；
- `--fsync` 在成功返回前同步输出；
- `--compress-choice=zstd` 压缩网络传输，但不改变目标设备上的 raw 布局。

代价是每次重跑仍要顺序读取完整源镜像和目标设备中对应的范围。它节省网络和重复写盘，
不保证立刻跳到精确的断点。传输完成前目标盘也仍然是半写入状态。这些限制对当前一次性
安装场景是合理的。

普通 `.zst` 流不适合按 raw offset 续传：Zstandard frame 本身不提供随机访问，见
[RFC 8878](https://www.rfc-editor.org/rfc/rfc8878.html)。rsync 的传输压缩避免了这个问题。

## 何时才值得写专用程序

只有实际环境无法使用上述 rsync，或者完整扫描目标盘的时间不可接受时，才值得维护一个
最小的分块发送程序。它只需要：

1. 按固定大小（例如 256 MiB）读取镜像；
2. 用 SSH 把一块交给远端 `dd`，通过 `seek=<offset>B conv=notrunc,fsync` 写入；
3. SSH 成功后记录下一块编号；连接结果不确定时重写当前块；
4. 重启程序后从记录的块编号继续。

固定偏移写入可直接建立在 GNU
[`dd`](https://www.gnu.org/software/coreutils/manual/html_node/dd-invocation.html) 上；SSH
命令的成功状态可作为 checkpoint 提交条件，见 OpenSSH
[`ssh` exit status](https://man.openbsd.org/ssh#EXIT_STATUS)。这不需要自定义接收协议、
chunk hash manifest、流式 checksum 或磁盘 serial 校验。

因此当前实现直接采用 rsync。若以后反复执行安装，可以把操作步骤放入 agent skill；
现在不为尚未发生的限制增加仓库代码。

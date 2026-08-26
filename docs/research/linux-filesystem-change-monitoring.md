# Linux 整棵目录树与文件系统变更监控

日期：2026-08-25

## 结论

Linux 确实提供了不需要在用户态为每个子目录安装 `inotify` watch 的机制，但没有一个同时满足
“任意目录子树、非特权、完整事件、可持久重放”的通用 ABI：

- **任意目录子树：Linux Audit** 的 `dir=/path` 是内核原生的递归子树匹配。一条规则即可覆盖
  子树，但它属于全局安全审计系统，需要系统级配置，并非面向普通应用的轻量 watcher。
- **整个文件系统：`fanotify` 的 `FAN_MARK_FILESYSTEM`** 用一个 mark 覆盖同一 filesystem
  instance 从所有 mount 发生的事件。Linux 5.1 起它能报告 create/delete/move/attribute，5.9
  起能携带父目录 handle 和名字，因此可以做出接近同步器所需的事件流；代价是
  `CAP_SYS_ADMIN`、filesystem file-handle 支持，以及必须在用户态过滤出目标子树。
- **整个 mount：`FAN_MARK_MOUNT`** 也只需一个 mark，但不能订阅需要 file handle 的
  `FAN_CREATE`、`FAN_ATTRIB`、`FAN_MOVE`、`FAN_DELETE_SELF` 等事件，所以只能可靠地当作
  内容写入提示，不能独立维护同步树的 namespace。
- **变更枚举而非实时通知：** Btrfs send、OpenZFS `zfs diff` 能从快照边界枚举变化；
  `dm-era` 能枚举改过的块。它们适合备份/复制，不是任意现有目录上的通用实时 watcher。

截至 2026-08-22 的 Linux `master`，fanotify UAPI 仍只有 inode、mount、filesystem 和
mount-namespace mark，没有 arbitrary-subtree/recursive mark；可直接核对当时的
[`include/uapi/linux/fanotify.h`](https://github.com/torvalds/linux/blob/2709dd5ae32f0828f386327c76bba9f39f63a1c6/include/uapi/linux/fanotify.h)。
该 commit 属于 Linux 7.2 开发周期。Linux 6.14 加入的 mount-namespace mark 只报告 mount
attach/detach，并没有补上目录子树监控。

## 能力对照

| 机制 | 范围 | 类型 | 特权 | 能否作为同步真相来源 |
| --- | --- | --- | --- | --- |
| inotify | 单 inode；递归须逐目录 mark | 实时、易溢出 | 否 | 否；溢出后须扫描 |
| fanotify mount mark | 整个 mount | 实时、易溢出 | `CAP_SYS_ADMIN` | 否；缺 create/delete/move 等关键事件 |
| fanotify filesystem mark | 整个 filesystem instance | 实时、易溢出 | `CAP_SYS_ADMIN` | 仍不能；但最适合作为变更提示/脏路径来源 |
| Linux Audit `dir=` | 任意非 `/` 子树，不自动越过 mount | 实时审计事件、易积压 | 系统审计权限 | 否；面向 syscall 审计，不是持久变更日志 |
| eBPF LSM/trace/kprobe | 可做全系统，再自行过滤 | 实时 instrumentation | 通常需要特权 | 否；需要自行定义完整语义和丢失恢复 |
| Btrfs/ZFS snapshot diff | subvolume/dataset | 两个边界间枚举 | 依操作而定 | 对快照区间可以；不是实时、非通用 FS |
| `dm-era` | 整个块设备 | 按 era 枚举写过的块 | 块设备管理权限 | 否；不知道路径、rename、delete |

这里的“不能作为真相来源”不是说事件没用，而是事件队列会丢失、事件到达时路径可能已变化，
或者机制本身不覆盖所有写入来源。同步器最终仍应以一次文件树 reconciliation 为准。

## 1. fanotify：真正的整 mount / 整 filesystem watcher

fanotify 最初在 Linux 2.6.36 引入、2.6.37 启用；相较 inotify，它明确增加了监控一个已挂载
文件系统内所有对象的能力。官方 [`fanotify(7)`](https://man7.org/linux/man-pages/man7/fanotify.7.html)
同时说明：create/delete/move 直到 Linux 5.1 才加入。

### 两种“一次覆盖整棵树”不是同一种能力

`fanotify_mark()` 提供：

- `FAN_MARK_MOUNT`：覆盖指定 mount 下的所有目录和文件，但 mount mark 不能请求依赖 file
  handle 的 create/attribute/move/delete-self 等事件；这是
  [`fanotify_mark(2)`](https://man7.org/linux/man-pages/man2/fanotify_mark.2.html) 明列的限制。
- `FAN_MARK_FILESYSTEM`（Linux 4.20）：覆盖 filesystem instance 中所有对象，而且从该
  filesystem 的任何 mount 路径发生的操作都会报告。它支持 FID 模式，因此才是同步器需要的
  namespace 事件的可行基础。两者都要求 `CAP_SYS_ADMIN`。

这也解释了一个表面矛盾：文档会说 mount monitoring 是 race-free 的整树监控，但 mount mark
并不等于“完整目录变更流”。它对自己允许订阅的事件是整树、race-free；缺失的 namespace
事件必须换成 filesystem mark 才能得到。

### 事件如何携带可用的对象身份

适合同步器的能力是分阶段补齐的：

- Linux 5.1：`FAN_REPORT_FID` 及 `FAN_CREATE`、`FAN_DELETE`、move、attribute/self 事件；
- Linux 5.9：`FAN_REPORT_DIR_FID`、`FAN_REPORT_NAME`，事件可携带父目录 file handle 和
  directory-entry name；
- Linux 5.17（另回移到部分 5.10/5.15）：`FAN_RENAME` 和 `FAN_REPORT_TARGET_FID`，rename
  可带旧/新父目录与名字，目录项事件还可带 child handle；
- Linux 6.14：`FAN_REPORT_MNT`、mount namespace marks 和 mount attach/detach 事件；它解决
  mount 拓扑观察，不是 arbitrary subtree watch。

这些标志的精确定义和版本见
[`fanotify_init(2)`](https://man7.org/linux/man-pages/man2/fanotify_init.2.html) 与
[`fanotify_mark(2)`](https://man7.org/linux/man-pages/man2/fanotify_mark.2.html)。FID/name 模式
避免了只拿到一个短命 fd 的局限，但 file handle 仍可能在消费事件前变成 `ESTALE`；用
`open_by_handle_at()` 重新打开还要求 `CAP_DAC_READ_SEARCH`，见
[`open_by_handle_at(2)`](https://man7.org/linux/man-pages/man2/open_by_handle_at.2.html)。

### 不能忽略的边界

fanotify 不是持久 change journal：

- 队列可以 overflow；超限事件会被丢弃，只留下 `FAN_Q_OVERFLOW`。内核 5.13 起队列上限可由
  `/proc/sys/fs/fanotify/max_queued_events` 调整，但这没有把队列变成可重放日志；
- 它只报告用户态通过 filesystem API 触发的事件，不捕获网络文件系统上由远端客户端造成的
  变化；文档也明确说不报告 `mmap`/`msync`/`munmap` 导致的访问和修改；
- FID 模式要求底层 filesystem 支持编码 file handles。`fanotify_mark(2)` 记录了 FUSE/零
  `fsid`、不支持 file handle 的 filesystem，以及 Btrfs subvolume `fsid` 边界可能产生的
  `ENODEV`、`EOPNOTSUPP`、`EXDEV`；
- mount mark 只观察“通过同一个 mount”触发的操作。一个 bind mount 被标记后，从原 mount
  路径写入同一 inode 的事件可能看不到；filesystem mark 才覆盖所有 mount。

以上限制均来自 [`fanotify(7)` 的 Limitations and caveats](https://man7.org/linux/man-pages/man7/fanotify.7.html)
和 [`fanotify_mark(2)` 的 errors](https://man7.org/linux/man-pages/man2/fanotify_mark.2.html)。
此外，Linux 5.13 才允许无 `CAP_SYS_ADMIN` 创建功能受限的 fanotify group；无特权调用者仍然
只能 mark inode，不能 mark mount 或 filesystem，见
[`fanotify_init(2)` 的 VERSIONS](https://man7.org/linux/man-pages/man2/fanotify_init.2.html)。

不必自己写程序也能验证它：inotify-tools 自带的 `fsnotifywait` 默认使用 fanotify，`-S` 会给
参数所在的整个 filesystem 加 mark，例如：

```sh
sudo fsnotifywait -m -F -S /some/path
```

它证明 ABI 可用，但范围仍是 `/some/path` 所在的整个 filesystem，不是该 path subtree；选项
语义见 [`fsnotifywait(1)`](https://man7.org/linux/man-pages/man1/fsnotifywait.1.html)。

## 2. Linux Audit：内核原生的任意目录递归规则

Linux Audit 的 syscall rule 支持 `-F dir=/absolute/path`。官方手册直接定义 `dir` 为
“对该目录及整个 subtree 的 recursive watch”，示例是：

```sh
auditctl -a always,exit -F arch=b64 \
  -F dir=/path/to/root/ -F perm=wa -F key=sync-root
```

这不是 `auditctl` 在用户态递归展开成几千条规则；它是内核 audit tree 匹配。官方
[`auditctl(8)`](https://man7.org/linux/man-pages/man8/auditctl.8.html) 也建议使用 syscall 形式，
旧式 `-w /path -p wa` 只为兼容保留且性能较差。

它的实际边界是：

- 递归在 mount point 停止。规则建立时已经存在的 mounted subtree 会自动标记；之后 bind/move
  进来的 mount 要用 `auditctl -q mount-point,subtree` 建立 equivalence，详见
  [`audit.rules(7)`](https://man7.org/linux/man-pages/man7/audit.rules.7.html)；
- 不能 watch `/`，也不支持 wildcard；
- `perm=w` 并不是记录每次 `write(2)`。为避免淹没日志，read/write syscall 被省略，内核主要
  根据 open flags 判断请求的访问类型。它适合回答“哪个 syscall/进程触碰了树”，不等价于
  “这里有一条可精确重放的最终状态变化”；
- audit 是主机级共享政策。配置可能已经被 `auditctl -e 2` 锁到重启前不可更改，事件要通过
  `auditd`/dispatcher plugin 实时分发；内核 backlog 和 dispatcher queue 都可能 overflow。
  `auditctl -s` 暴露 lost 计数，官方 audit userspace
  [README](https://github.com/linux-audit/audit-userspace/blob/master/README.md) 描述了 auditd 的
  实时 plugin 分发架构。

因此 Audit 是用户问题中最直接的“任意特定目录递归内核监控”答案，但更适合由系统管理员部署
一个 privileged helper，再把“需要 reconcile”通知交给同步器，而不适合普通用户进程静默占用
系统审计基础设施。还要注意一个具体漏口：规则装载前就已打开为可写的 fd 后续继续写入时，
仅靠 `perm=w` 的 open 判定不能保证产生新事件；启动基线扫描和周期性校验仍不可省。

## 3. eBPF、LSM、tracepoints 和 kprobes

这些机制能实现定制的全系统文件操作 telemetry，但不是现成的递归文件变化 ABI。

[`BPF LSM`](https://docs.kernel.org/bpf/prog_lsm.html) 允许特权用户在运行时挂到 LSM hooks，
实现 system-wide audit/MAC policy，并把自定义记录写到 perf/ring buffer。理论上可以在 inode/file
相关 hooks 中按 mount、inode ancestry、cgroup 等条件过滤；但必须自行选择覆盖 create、unlink、
rename、attribute、write/mmap 等语义的 hook，自行处理 path 的重命名竞态和事件丢失。它更像构建
一个专用 watcher 的内核工具箱，而不是调用一个现成 ABI。

tracepoints/kprobes 更不适合作为长期可移植同步后端。Linux BPF 官方设计文档明确说
[tracepoint 和 kprobe attachment points 都不是稳定 ABI](https://docs.kernel.org/bpf/bpf_design_QA.html)；
它们绑定 VFS/filesystem 内部实现，内核升级可能要求修改程序。eBPF 可以降低每事件开销，却不会
自动提供 durable cursor、完整路径语义或 overflow 后恢复。

## 4. 文件系统原生与块层 change enumeration

这些方案回答的是“两个已知边界之间哪些东西变了”，不是“现在请递归 watch 任意路径”。

### Btrfs

`btrfs send -p <parent> <snapshot>` 生成两个只读 subvolume snapshot 之间的增量指令流；流中有
metadata、extent、rename、delete 等命令。它能高效、准确地复制 snapshot 边界，见官方
[`btrfs-send(8)`](https://btrfs.readthedocs.io/en/latest/btrfs-send.html) 和
[send stream format](https://btrfs.readthedocs.io/en/latest/dev/dev-send-stream.html)。限制是所有
相关 snapshot 必须只读，接收端必须保有完全相同的 parent；这天然更像单向 replication/backup，
不适合 Mutagen 式双向 live sync。

`btrfs subvolume find-new` 只承诺列出某 generation 之后“recently modified files”，见
[`btrfs-subvolume(8)`](https://btrfs.readthedocs.io/en/latest/btrfs-subvolume.html)。它不是包含
delete/rename 的完整命令日志，不能单独驱动通用同步。

### OpenZFS 与 dm-era

OpenZFS `zfs diff` 能列出 snapshot 到后续 snapshot 或 live dataset 之间的 add/remove/modify/
rename，见官方 [`zfs-diff(8)`](https://openzfs.github.io/openzfs-docs/man/master/8/zfs-diff.8.html)。
这是 filesystem-specific snapshot diff，不是 Linux VFS 通用 ABI。

device-mapper 的 [`dm-era`](https://docs.kernel.org/admin-guide/device-mapper/era.html) 会持久记录
每个 era 中哪些 block 被写过，设计用例包括增量备份。但块变化不能告诉同步器对应的 pathname、
rename 或 delete，且存储栈必须预先以 era target 构建。

没有发现 ext4、XFS 或 Linux VFS 提供一个面向普通用户态、类似 Windows USN Journal 或 macOS
FSEvents persistent cursor 的通用变更枚举 ABI。ext4 journal 等首先服务 filesystem crash
recovery；解析其内部日志不是稳定、跨 filesystem 的应用接口。

## 5. Mutagen 0.18.1 已有 fanotify 实现，但当前部署不会启用

这不是纯理论方案。Mutagen 0.18.1 源码已经包含一个 Linux recursive watcher：它用
`FAN_MARK_FILESYSTEM` 订阅 create/move/modify/attrib/delete，以 mount point 作为
`open_by_handle_at()` 的基准，再在用户态丢弃目标 path 之外的 filesystem-wide 事件。实现见
[`sspl/pkg/filesystem/watching/fanotify/watch.go`](https://github.com/mutagen-io/mutagen/blob/v0.18.1/sspl/pkg/filesystem/watching/fanotify/watch.go)。
这与上面推导出的最佳 fanotify 架构一致。

但它有三重启用条件：源码 build constraint 是
`linux && mutagensspl && mutagenfanotify`，而且运行时只允许 Mutagen sidecar 环境，并检查
`CAP_SYS_ADMIN`、`CAP_DAC_READ_SEARCH` 和 Linux >= 5.1；见
[`watch_recursive_linux_sspl_fanotify.go`](https://github.com/mutagen-io/mutagen/blob/v0.18.1/pkg/filesystem/watching/watch_recursive_linux_sspl_fanotify.go)
和
[`fanotify.go`](https://github.com/mutagen-io/mutagen/blob/v0.18.1/sspl/pkg/filesystem/watching/fanotify/fanotify.go)。
上游只有 sidecar image 的构建明确加入 `mutagenfanotify`，见其
[`Dockerfile`](https://github.com/mutagen-io/mutagen/blob/v0.18.1/images/sidecar/linux/Dockerfile)。

本仓库锁定的 Nixpkgs Mutagen derivation 只使用 `mutagencli`、`mutagenagent` tags，没有
`mutagensspl` 或 `mutagenfanotify`；见锁定 revision 的
[`package.nix`](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/pkgs/by-name/mu/mutagen/package.nix)。
服务端 agent 又是通过 SSH 以普通 `syncd` 用户进入 NixOS container，数据从 host 的
`/pool1/services/mutagen-sync/data`（ZFS pool）bind mount 到 `/data`；见
[`nixos/hosts/el2/mutagen-sync.nix`](../../nixos/hosts/el2/mutagen-sync.nix) 和客户端的
[`home-manager/default.nix`](../../home-manager/default.nix)。当前部署既不满足 build/sidecar
条件，也没有所需 capabilities，因此不能只加一个 Mutagen CLI option 来打开 fanotify。

ZFS 确实提供 `zfs diff`，所以若该目录是独立 dataset，可以用 snapshot diff 做批量变化枚举；
但这不会让当前 Mutagen agent 获得实时 wakeup，也会引入 snapshot 管理和新的集成层。它是另一种
同步架构，不是当前 polling watcher 的透明替换。

## 6. 对 Mutagen 类同步器的可行架构

事件流应该被当作“降低扫描频率和缩小扫描范围的 hint”，而不是事实数据库。可靠的组合是：

1. 先安装 watcher，再做一次完整 baseline scan；扫描期间继续缓存事件，从而关闭启动竞态。
2. 合并短时间内的事件，只把受影响路径/目录标脏；同步 cycle 对脏范围做 `stat`/内容校验。
3. 遇到 queue overflow、无法解析的 stale handle、mount 拓扑变化或 watcher 重启，立即把整棵同步
   root 标脏并 full reconcile。
4. 保留低频完整扫描作为 safety net，覆盖 fanotify 明确不报告的 mmap/远端网络文件系统变化，
   以及实现 bug。此时 polling 可以从“每 10 秒主检测机制”降为分钟级或更慢的纠错机制。

具体选择：

- **能够部署 privileged helper，且目标目录独占一个 filesystem instance：**
  `FAN_MARK_FILESYSTEM` + `FAN_REPORT_DFID_NAME_TARGET` 是最干净的实时后端。
- **privileged helper，但目标只是繁忙 filesystem 中的一棵子树：** Linux Audit `dir=` 提供最
  精确的内核子树过滤；若不希望占用 audit 基础设施，则用 filesystem-wide fanotify，在用户态
  维护/解析 FID 并过滤目标树。
- **普通用户、任意 filesystem、通用发行版：** 当前 Linux 没有免特权的递归单 mark。工程上仍
  需在 recursive inotify、polling，或二者混合之间选择。对几千个目录，逐目录 inotify 通常比
  每 10 秒全树扫描更合适，但必须处理 watch 上限、新目录竞态和 `IN_Q_OVERFLOW` 后 full scan。
- **允许改变存储与同步模型：** Btrfs/ZFS snapshots 能给出可靠 change enumeration，但会把产品
  变成 snapshot-driven replication，而不是通用双向 live sync。

所以，问题不是 Linux 内核“完全不会递归监控”，而是它把这项能力分散在三个不同定位的接口中：
Audit 负责 arbitrary subtree policy，fanotify 负责 mount/filesystem notification，filesystem
snapshot/journal 负责特定存储上的区间变化。普通应用缺少的，确实是把三者优点合并起来的那一个
非特权、通用、可重放 ABI。

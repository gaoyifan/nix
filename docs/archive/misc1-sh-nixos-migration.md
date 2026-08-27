# misc1-sh NixOS 迁移计划

## 执行手册与入口清单

本节保留执行期间不能丢失的控制面信息。不在文档中记录任何私钥
内容。

- 控制机：`el2`，工作仓库 `/home/yifan/nix`
- Nix 仓库：`/home/yifan/nix`
- Ansible 仓库：`/home/yifan/tmp/server-maintenance`
- 本地 SquashFS 目录：`/pool0/playground/`，已验证约有 32 TiB
  可用空间
- PVE 管理入口：`ssh root@103.127.243.2`
- PVE 主机名：`pve-b17-3u.node.nerocloud.io`
- PVE 版本：Proxmox VE 6.4-15，QEMU 5.2.0，单节点 quorate cluster
- 目标 VMID：`112`
- PVE VM 名称：`misc1-sh`（cloud-init `ipconfig1` 中的 `.76` 是旧
  元数据；在线系统已验证使用 `61.172.164.79`）
- PVE 系统盘卷：`local-lvm:vm-112-disk-0`，20 GiB，VirtIO SCSI
- PVE cloud-init 卷：`local-lvm:vm-112-cloudinit`
- VM 启动/显示：SeaBIOS、`bootdisk: scsi0`、`serial0: socket`、
  `vga: serial0`
- PVE `local-lvm` 在盘点时有约 66 GiB 可用空间，足以容纳
  20 GiB 系统盘重写后的 thin snapshot delta
- 目标公网 SSH：`ssh root@103.90.137.101`（已验证可用）
- 目标 Tailscale SSH：`ssh root@misc1-sh.ts.gaof.net`
- Tailscale 地址：`100.127.110.129`、
  `fd7a:115c:a1e0::4f01:ea0d`
- 当前 SSH host ED25519 指纹：
  `SHA256:MgtDJB9FvVtuTQWvlnV1cyHswCXtA0DZPK9O8eG2Tec`
- 当前 SSH host RSA 指纹：
  `SHA256:JNCWHfNnly7Ut6T/YZT/aSgbGyewEIc4z1ET7kXW9/w`
- 当前 SSH host ECDSA 指纹：
  `SHA256:4WUGcb5wxQttymbCBT+RMiipGuY7APquMX0vu2cw6l4`
- `yifan` 的 agenix/SSH ED25519 身份指纹：
  `SHA256:TnFX/kDG9wq1hXZJ41AyvrQuvEpL15iMesoH66fFlMs`
- WARP runtime 私钥源路径：`/etc/wireguard/privatekey-cloudflare`
- Nylon 身份源路径：`/etc/nylon/private.key` 和
  `/etc/nylon/public.key`
- Tailscale 身份源路径：`/var/lib/tailscale`
- Restic runtime environment：`/home/yifan/.config/restic/env`，实际是 Home
  Manager agenix symlink，不应将 symlink 目标当作普通文件复制
- 固定 nixos-anywhere revision：
  `github:nix-community/nixos-anywhere/91fc9b70fc295258c366cce8627efb6f185fd9fb`

PVE 快照名使用 `pre-nixos-<UTC timestamp>`。主回滚流程是：

```bash
ssh root@103.127.243.2
qm stop 112
qm rollback 112 <snapshot-name>
qm start 112
```

回滚后同时检查公网和 Tailscale SSH；不要在回滚后立即删除快照。

## 目标与已验证现状

将 `misc1-sh.ts.gaof.net` 从 Debian 13 原机迁移到由本仓库管理的
NixOS，保留 SSH、Tailscale、Nylon 和 Cloudflare WARP 身份以及三个
Nylon 出口的行为。目标是 PVE VM 112，当前配置为 x86_64、SeaBIOS、
4 GiB 内存、单块 20 GiB VirtIO SCSI 系统盘和两张 VirtIO 网卡。

已验证的关键值：

- 系统盘：`/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0`
- `eth0` (`2a:ae:f4:64:6d:0e`)：`103.90.137.101/27`，网关
  `103.90.137.97`
- `eth1` (`e2:1e:1a:33:76:68`)：`61.172.164.79/24`，table 100
  网关 `61.172.164.1`
- Nylon 节点：`misc1-sh`，`10.250.10.24` / `fd10:250:10::24`，
  numeric ID 24，UDP 6622
- Nylon 出口：label 100 经 `eth0`，101 经 `eth1`，102 经
  `wg-cloudflare`
- WARP：`172.16.0.2/32`、
  `2606:4700:110:8eab:cfbe:2c01:5062:8c3c/128`，reserved
  `0x3e781e`
- 最近一次 Restic 备份成功，运行时凭据与本仓库 Home Manager
  agenix secret 一致

## 仓库改动

### Nix 仓库

- 新增 `misc1-sh` x86_64 NixOS configuration 和 deploy-rs 节点，从旧
  system-manager `misc1` 列表移除。
- 复用 `qemu-guest`、`tailscale-gnet-vm-exit`、`nylon-public-exit`、
  `edge-firewall` 和所有 NixOS common/Home Manager/Restic 配置。
- 主机层只声明差异：
  - BIOS GRUB、GPT BIOS boot 分区、2 GiB swap、Btrfs root。
  - 按 MAC 固定 `eth0`/`eth1`，恢复两个静态地址、网关、DNS、
    `202.141.160.0/20` 路由及 table 100 源地址/fwmark 策略。
  - Nylon label 100 使用默认 `eth0` 出口，label 101 使用 `eth1`，
    label 102 使用 WARP。
  - WARP 私钥由 host-specific agenix secret 部署到 Nylon 模块已有的
    runtime path。
  - hostname 统一为 `misc1-sh`，`system.stateVersion = "26.05"`；用户
    UID 使用 NixOS 自动分配（现有值仍为 1000），时区继承仓库公共配置
    `Asia/Singapore`。
- 不迁移当前没有容器的 Docker/Containerd，也不迁移 Debian patched
  FRR；现有 Nix Nylon 模块直接接管 MPLS LSP、tc SNAT、conntrack
  anchor、WARP 和转发。
- 将保留的 SSH host ED25519 key 注册为 agenix host recipient，新增
  WARP secret，然后按仓库流程 rekey。

### server-maintenance 仓库

- 将 `misc1-sh` 加入 `NIXOS_HOSTS`，从 `ROOT_SSH_HOSTS` 和 root-only
  sudo playbook 移除，Ansible 改用 `yifan` + sudo。
- 设置 `nylon_managed_by_nix: true` 和 `frr_skip: true`。Ansible 继续管理
  Nylon keypair 及 `central.yaml`/`node.yaml`；Nix 管理 binary、systemd、
  MPLS 和出口数据面。
- `nylon-deploy.yml` 的共享配置模板按 `ansible_play_hosts_all` 生成；仓库
  runbook 明确规定 `--limit` 会故意只生成受限节点集合。因此不得为单机
  收敛运行该 playbook，除非本意就是替换为单节点 mesh。迁移验收只读取
  全网状态；完整配置沿用迁移前已备份且校验过的共享配置。

## 备份与状态保留

1. 手动运行并验证最终 Restic 备份。
2. 通过已验证可用的公网 SSH 停止 Nylon、Tailscale、FRR、Docker
   和备份 timer，保存带 numeric owner、ACL 和 xattr 的选定状态：
   - `/etc/nylon`
   - `/var/lib/tailscale`
   - `/etc/ssh/ssh_host_*`
   - `/home/yifan/.ssh`
3. 正常关闭 VM 112，在 PVE 上创建 `pre-nixos-<UTC>` 无内存磁盘
   冷快照，然后重新启动旧系统并进入 nixos-anywhere kexec 环境。
4. 在 kexec 环境中确认旧盘完全未挂载后，将 `/dev/sda1` 以
   `ro,noload` 挂载为旧 root，并将 `/dev/sda15` 只读挂载到其
   `/boot/efi`。以 `tar --numeric-owner --acls --xattrs` 流式送到控制机的
   `mksquashfs -tar`，保存为
   `/pool0/playground/misc1-sh-debian13-pre-nixos-<UTC>.squashfs`。文件权限
   为 0600，随后运行 `unsquashfs -s`、抽查文件并生成 SHA-256。只有
   这三项验证通过后才能执行 disko。

SquashFS 是文件级归档，不是可启动的整盘镜像。PVE 快照是主要回滚
手段，SquashFS 和 Restic 是第二层数据恢复手段。

## 安装

1. 运行 `just fmt`、`just check`、目标 configuration eval 和 closure
   dry-run/build。检查 server-maintenance inventory 和 Ansible syntax。
2. 使用固定的
   `nix-community/nixos-anywhere/91fc9b70fc295258c366cce8627efb6f185fd9fb`，
   通过 `103.90.137.101` 进入 kexec 安装环境，并在本机为 x86_64
   构建。
3. 目标是 PVE 6.4/QEMU 5.2 i440FX，不默认添加只在 PVE 7.1/QEMU
   6.1 上验证过的 kexec 兼容参数。仅在出现对应 initrd-placement
   错误时使用 `--kexec-syscall --mem-max=0xffffffff` 重试。
4. 在安装器中再次核对两张网卡、默认路由、PVE 串口及唯一系统
   盘，确认无其他磁盘并完成上述只读 SquashFS 后，分别执行
   `disko`、`install`、`reboot`。
5. 通过 nixos-anywhere extra-files 恢复选定状态；为 NixOS 上已声明的
   UID 1000 显式恢复 `~yifan/.ssh` 所有权。

## 验收与回滚

- 系统：NixOS、BIOS GRUB、Btrfs、swap、20 GiB root 扩容、两张网卡、
  table 100 策略路由、DNS 和 failed units。
- 身份：SSH host 指纹、Tailscale node ID/IP/DNS/tag、Nylon public key
  保持不变；Home Manager agenix 可解密。
- 数据面：Nylon UDP 6622/FakeTCP 正常，MPLS labels 100/101/102 和三个
  tc SNAT 出口存在，WARP 有新鲜握手且双栈出口正常。
- 防火墙：公网使用仓库标准 SSH、iperf、Nylon 和 Tailscale 端口；
  Tailscale/Nylon 转发正常。
- 保持迁移前的完整 Nylon 共享配置，运行全网 mesh regression，最后在
  新系统执行一次 Restic 备份。原计划中的无
  `--limit` 全量部署只可在确认 Nylon source pin 一致后执行；不得以
  本次单机迁移为由改动其他节点的 binary。
- 若清盘后验收失败，停止 VM 112，回滚 PVE 快照并启动。
- 全部验收完成后仍保留 PVE 快照和 SquashFS，不自动删除。

## 执行记录

本次执行的固定 ID 为 `20260827T154600Z`，后续产物使用下列精确名称：

- SquashFS：
  `/pool0/playground/misc1-sh-debian13-pre-nixos-20260827T154600Z.squashfs`
- SquashFS checksum：
  `/pool0/playground/misc1-sh-debian13-pre-nixos-20260827T154600Z.squashfs.sha256`
- SquashFS ACL sidecar：
  `/pool0/playground/misc1-sh-debian13-pre-nixos-20260827T154600Z.squashfs.acl`
- ACL sidecar checksum：
  `/pool0/playground/misc1-sh-debian13-pre-nixos-20260827T154600Z.squashfs.acl.sha256`
- 选定状态包：
  `/pool0/playground/misc1-sh-selected-state-20260827T154600Z.tar`
- nixos-anywhere extra-files 目录：
  `/pool0/playground/misc1-sh-extra-files-20260827T154600Z`
- PVE snapshot：`pre-nixos-20260827T154600Z`

已完成项：

- Nix 主机配置、deploy-rs、system-manager 移除和 server-maintenance
  管理边界已实现。
- WARP 私钥已加密为 agenix secret，解密后 SHA-256 与旧机原文
  完全一致。
- `nix build` 目标 system closure、`just check`、`just fmt-check`、
  Ansible inventory 与相关 playbook syntax check 均已通过。
- 生成的 networkd、policy-routing、nftables 和 Nylon exit units 已人工
  检查。
- 2026-08-27 15:45:04 UTC 最终 Restic 备份成功，snapshot ID
  `e0af6800`。
- 选定状态包已保存并验证必需文件；extra-files 目录已从该包
  生成。调用 nixos-anywhere 时必须附带
  `--chown /home/yifan 1000:100`，因为 extra-files 默认在目标上归
  root 所有，而 NixOS 中已固定 `yifan` UID 1000，主组 `users`
  GID 100。
- 旧 Debian 上的 Nylon、Tailscale、FRR、Docker、Containerd 和
  Restic timer 已停止，等待冷快照。公网 SSH 仍可用。
- 曾尝试在线流式生成 SquashFS，但都没有产生可接受的产物：第一次
  因以 `.` 为 tar 路径触发 `mksquashfs` 路径检查；第二、三次因把
  `/proc`/`/sys` 等挂载点作为输入而遇到伪文件系统读取错误；第四次
  虽排除了伪文件系统，但 SSH 自身会更新 `var/log/auth.log`，无法保证
  严格一致。所有尝试均已中止，`mksquashfs` 删除了未完成目标；不得
  将任何同名残片视为备份。
- 最终策略是在 PVE 冷快照后进入 kexec 环境，从未挂载的旧盘只读
  生成 SquashFS。旧盘已验证为 `/dev/sda`：root 是 `/dev/sda1`
  (ext4)，EFI 是 `/dev/sda15` (vfat)；稳定整盘路径是
  `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0`。
- VM 112 已正常关机；PVE 于 2026-08-28 01:14:37 创建并核验冷快照
  `pre-nixos-20260827T154600Z`，当前节点指向 snapshot 之后的 current
  状态。快照创建后 `local-lvm` 为 85.25% 使用、约 63.3 GiB 可用。
  PVE 同时提示 thin pool 没有启用自动扩展且虚拟卷逻辑容量超配；本次
  20 GiB 盘重写仍在已核对的剩余空间内，但安装期间必须监控
  `local-lvm`，不得删除该快照。
- 固定 revision 的 nixos-anywhere `kexec` 阶段已成功完成，没有使用
  兼容 flags。安装环境是 NixOS 25.11、hostname `nixos-installer`；该
  image 没有 `/etc/nixos-anywhere` marker，但命令成功返回，且旧盘
  `/dev/sda` 的所有分区均未挂载，两张网卡与公网默认路由正常。
- 最终 SquashFS 已从安装环境中的只读旧盘生成。`/dev/sda1` 挂载为
  ext4 `ro,norecovery`，`/dev/sda15` 挂载为 vfat `ro`。主文件大小
  4,405,886,976 bytes，包含 364,040 inode，SHA-256 为
  `d1cb8c42301baa313dc871db0d901d059d79218f733d7d0d85013cb24e539b37`。
  `unsquashfs -s` 验证 superblock 有效；`etc/os-release`、Nylon 公钥、
  Tailscale state、SSH host ED25519 公钥和 EFI GRUB 均与源盘哈希一致。
- `mksquashfs -tar` 会忽略 GNU tar 的 POSIX ACL 扩展，因此另存完整
  ACL sidecar（54,203,202 bytes，2,394,667 行），SHA-256 为
  `ee919b0445ebe45f1e72c85b030c76a22bbb7e5cfa37df6d245b7fde880419c5`。
  已在只读旧盘根目录下通过完整的
  `setfacl --test --restore=<sidecar>`；恢复 SquashFS 后应在恢复根目录
  中执行 `setfacl --restore=<sidecar>`。关机后残留的 Unix socket
  节点不在 SquashFS 中，服务启动时会重建。
- 清盘前最终 `just fmt-check` 和 `misc1-sh` system closure build 已再次
  通过。nixos-anywhere `disko` 阶段已成功完成：GPT partition 1 是
  1 MiB EF02 BIOS boot，partition 2 是 2 GiB swap（UUID
  `0a708090-5705-405c-977d-4de96d5160d9`），partition 3 是约 18 GiB
  Btrfs root（UUID `853c1523-5b18-44d6-a0f6-c9c19dd31938`），并已挂载
  到安装环境的 `/mnt`。
- nixos-anywhere `install` 阶段已成功完成。extra-files 已复制，agenix
  使用恢复的 host key 成功解密 WARP、root password 和 Tailscale
  auth secret；GRUB 以 `i386-pc` 模式成功安装到稳定整盘路径。目标
  system closure 是
  `/nix/store/9br57ngx7pml70zk0cpnn8mma8zw0llm-nixos-system-misc1-sh-26.05.20260803.531670d`。
- 重启前检查确认 Nylon/Tailscale 状态目录为 root:root 0700，`yifan`
  home 与 `.ssh` 为 1000:100 0700，三种 SSH host key 为 root:root
  0600 且指纹与迁移前完全一致。生成的 fstab 以
  `/dev/disk/by-partlabel/disk-system-root` 挂载 Btrfs root（
  `x-initrd.mount,compress=zstd:3,noatime`），并启用
  `disk-system-swap`。PVE thin pool 在安装后为 85.78% 使用、metadata
  4.23%。
- 首次启动后系统、磁盘、网络和数据面基础验收通过：NixOS 26.05、
  Btrfs root、2 GiB swap、两个公网地址和各自出口、table 52/100、
  DNS、Tailscale 原 IP/DNS/tag/exit-node 广告、Nylon 原公钥与 labels
  100/101/102、三组 tc SNAT、WARP 原私钥哈希和新鲜握手均正确；没有
  failed units。PVE 未配置 guest-agent virtio port，因此
  `qemu-guest-agent` inactive 且不属于 failed unit。
- Tailscale 首次验收发现非对称 DERP 故障：el2 可经 misc1 的 home DERP
  `tok` 到达 misc1，但 misc1 无法到达 el2 的 home DERP 900 (`hfe`)；
  目标抓包确认 TCP 包没有到达 misc1，排除 edge firewall。根因是通用
  internal DNS 将 `el2.gaof.net` 委派给 Tailscale 内的
  `100.64.2.254`，而自定义 DERP 本身又使用 `el2.gaof.net:10000`，在
  无公网 IPv6 的 misc1 上形成 bootstrap 循环。公网 DNS 的三个 A
  地址 `202.38.93.98`、`202.141.162.72`、`202.141.178.7` 均已从
  misc1 验证可连接 TCP 10000；主机配置固定这三个映射以打破循环，
  最新配置已经部署。部署后 `getent` 可立即解析；misc1 到 el2 经 DERP
  `hfe`、el2 到 misc1 经 DERP `tok` 的双向 Tailscale ping 均成功，
  Tailscale TCP/22、`ssh yifan@100.127.110.129` 和免密 sudo 均通过。
- 验收时发现 Nix package 固定 Nylon `f20427e9367ae3f66485d85c1be0a08ec612dee2`，
  而 server-maintenance 的全量部署仍固定
  `71d83f3b17ea5abdfe9b682429b0c7e295798f8e`。无 `--limit` 执行会影响
  所有非 NixOS 节点并可能造成 binary 回退，超出本次迁移权限范围。
  后续应另行统一两个仓库的 pin 后再做全量 rollout。
- 曾按原计划对 `misc1-sh` 限定运行 `nylon-deploy.yml`；模板按
  `ansible_play_hosts_all` 渲染，因此得到仅含 misc1、`graph: []` 的
  `central.yaml`，reload 后邻居数变成 0。这与 server-maintenance
  runbook 明示的 `--limit` 语义一致，不是 NixOS 服务故障。已立即从
  `/pool0/playground/misc1-sh-extra-files-20260827T154600Z/etc/nylon/central.yaml`
  恢复迁移前完整配置；文件为 130 行，SHA-256
  `f9118df629893065a4e27e4b433701ec451d971f5d8d0c70db90af90b9e49ec3`，
  当前 Nylon binary verify 与 reload 均成功。恢复后是 16 个邻居、79
  个 active endpoint（42 FakeTCP、37 UDP）。不得再次限定运行该
  playbook。
- 全网 Nylon regression 的 SSH reachability、17 节点 overlay ping
  matrix（0 不可达、0 部分丢包）和连续 120 秒 dispatch-loop 检查（0
  drop）通过。最短路径检查对 272 条路由使用精确相等判定，四次抓取
  分别有 1、3、1、2 条偏差；之后两次独立抓取的偏差又轮换为 2 条和
  3 条，最后一轮仅为 100、214、199 微秒，且不再涉及 misc1。由于各
  节点状态是顺序抓取、链路 RTT 同时持续更新，这些非固定的小偏差属于
  测量抖动；没有不可达路由，也没有持续指向 misc1 的错误下一跳。严格
  脚本最终状态仍记为 `regression FAIL`，不得把它误写成完整 PASS。
- 新 NixOS 上的首次 `restic-backups-system.service` 已成功完成：处理 36
  个文件、41.147 KiB，生成 snapshot `f941c240`；已用相同 runtime
  environment 从仓库读回并核验 snapshot，时间为
  2026-08-27 17:05:35 UTC，hostname 为 `misc1-sh`，备份路径是
  `/etc`、`/home`、`/root`、`/srv`、`/var/lib/tailscale`。timer 已启用，
  下一次计划运行时间为 2026-08-28 00:11:26 UTC。
- 2026-08-27 17:08:45 UTC 最终验收时运行的是
  `/nix/store/1n5xgmasjxwchx6bpwi74m4nmarfq0pb-nixos-system-misc1-sh-26.05.20260803.531670d`：
  critical services 和 Restic timer 均 active，failed units 为空；两个
  公网源地址出口分别返回原地址，WARP 握手为 73 秒前，MPLS 100/101/102
  及对应的 tc conntrack SNAT filter 均存在。三种 SSH 指纹、Tailscale
  身份、Nylon 身份和 16 邻居/79 active endpoints 再次核验不变。PVE
  冷快照仍存在，`local-lvm` 最终为 85.83% 使用、metadata 4.23%。
  `just fmt`、`just fmt-check`、`just check`、两份 Ansible syntax check、
  inventory host 解析和 `git diff --check` 均通过。
- 迁移完成后的仓库侧默认值复核删除了与公共或上游默认等价的声明：显式
  UTC/UID、GRUB enable、agenix mode、静态路由 metric、两个
  `IPv6AcceptRA = false`、Disko disk type/partition priorities，以及
  重复的全局 DNS。SSH host key 完全采用 NixOS 默认的 RSA/ED25519；
  原 ECDSA 文件仍留在目标文件系统，但 sshd 不再加载它。精简后的
  closure 已构建验证，本次没有重新部署目标主机。
- 后续命名统一将 PVE VM 112 名称改为 `misc1-sh`，并将三枚既有 SSH
  host key 的注释改为 `root@misc1-sh`；RSA、ED25519、ECDSA 指纹均
  保持不变，PVE 冷快照也仍然保留。历史 SquashFS 与快照内容不改写。

执行窗口已经结束。server-maintenance 已将 `misc1-sh` 切换为 NixOS
inventory 语义，当前 Tailscale SSH、`yifan` sudo 和
`/run/current-system/sw/bin/python3` 均已验证可用。

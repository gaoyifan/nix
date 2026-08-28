# misc1-sz NixOS 与 Nylon 角色迁移计划

## 目标

在 PVE 宿主机 `root@58.84.55.35` 上新增 NixOS VM `misc1-sz`，部署
Tailscale，并把 `misc0-sz` 的 Nylon 节点角色迁移到新 VM。迁移后：

- `misc1-sz` 接管 Nylon numeric ID/MPLS label `23`、IPv4 overlay
  `10.250.10.23` 和 IPv6 overlay `fd10:250:10::23`；
- Nylon 节点 ID 从 `misc0-sz` 改为 `misc1-sz`；
- Nylon keypair 从旧机迁移到新机，保持节点加密身份；
- 新机通过 `58.84.55.69` 和 `14.215.130.15` 提供 Nylon endpoint；
- 新机继续发布两个 Nylon 出口：label 100 走 ALVIDI，label 101 走深圳电信；
- `misc0-sz` 停止并禁用 Nylon，不再属于 Nylon inventory；其余服务不在本次迁移范围内。

这是角色替换，不是新增第 18 个 Nylon 节点。任何时刻都不得让新旧两台机器同时
运行 numeric ID `23` / overlay `10.250.10.23`。

## 实施前已验证事实

### PVE 与 VM

- PVE 为 `pve.example.com`，PVE 7.2，地址 `58.84.55.35/27`。
- `vmbr0` 接入 ALVIDI 网络，`vmbr108` 接入深圳电信网络。
- 旧 VM 103 `misc0-sz` 使用 4 vCPU、4 GiB RAM、20 GiB SCSI 系统盘：
  - `eth0`: `58.84.55.67/28`，网关 `58.84.55.65`，PVE `vmbr0`；
  - `eth1`: `14.215.130.4/25`，网关 `14.215.130.1`，PVE `vmbr108`。
- 新 VM 105 已从 Debian 13 Cloud-Init 模板 9104 做 full clone，但尚未启动：
  - 4 vCPU、4 GiB RAM、20 GiB SCSI 系统盘；
  - `net0` MAC `8E:2F:57:B9:92:1E`，PVE `vmbr0`；
  - `net1` MAC `36:73:2D:CF:A4:87`，PVE `vmbr108`；
  - Cloud-Init `ipconfig0`: `58.84.55.69/28`, gateway `58.84.55.65`；
  - Cloud-Init `ipconfig1`: `14.215.130.15/25`, gateway `14.215.130.1`。
- 从旧机的 `eth1` 对 `14.215.130.15` 做同二层探测时无 ICMP 回包，邻居状态为
  `INCOMPLETE`，未发现该地址已被占用。

### NixOS 配置模式

- 双网卡 PVE NixOS VM 应沿用 `nixos/hosts/misc1-sh/` 的结构，而不是复制仍为
  Debian 的 `misc0-sz`。
- 公共 NixOS 配置会启用 Tailscale，默认广告 Tailscale exit node；
  `tailscale-gnet-vm-exit.nix` 为从 `tailscale0` 到以太网 WAN 的流量做 masquerade。
- `nylon-public-exit.nix` 提供 Nylon 默认出口 label 100；主机配置需另加 label 101，
  interface `eth1`，gateway `14.215.130.1`。
- `edge-firewall.nix` 会公开 Nylon UDP 6622、Tailscale UDP 6627，并信任
  `nylon0` 和 `tailscale0`。
- NixOS 管理 Nylon binary、MPLS 内核设置和 systemd unit；
  `server-maintenance` 的 Ansible 继续管理 Nylon keypair 和
  `/etc/nylon/{central,node}.yaml`。

### Nylon 集群约束

- Nylon `central.yaml` 由完整 `ansible_play_hosts_all` 渲染。不得对
  `nylon-deploy.yml` 使用 `--limit` 做局部部署，否则会把 mesh 配置裁成部分节点。
- 角色迁移应在维护仓库中把 `misc0-sz.ts.gaof.net` 替换为
  `misc1-sz.ts.gaof.net`，并保留 numeric ID `23` 与 overlay 地址。
- endpoint 和出口地址改为：
  - label 100 / `eth0`: `58.84.55.69:6622`，gateway `58.84.55.65`；
  - label 101 / `eth1`: `14.215.130.15:6622`，gateway `14.215.130.1`。
- 不迁移旧机的 HE IPv6、Cloudflare WARP 或 `wgnd-tw` 出口 labels 102–104；这些接口
  是旧机专有状态，且不在用户要求范围内。

## 已决定事项

- VMID 使用当前 PVE 已分配的新 VM 105。
- 新机继续作为 Tailscale exit node。
- 新机发布两个 Nylon 公网出口，labels 100/101。
- 迁移并复用旧 Nylon keypair，不生成新的 Nylon 身份。
- 旧机只停止并禁用 Nylon；在新机和全网回归完成前保留旧 binary/config 作为回滚材料，
  不删除旧 VM 或其他旧机服务。
- 新机使用预生成的独立 SSH host ED25519 key 和 `yifan` 用户 ED25519 key。
  私钥只通过安装时的 `extra-files` 写入目标文件系统，不写入 Git 或 Nix store。

## 实施前问题与门槛（已解决）

### Nylon source pin 不一致

实施前两个仓库不满足维护流程所声明的“同一 reviewed commit”约束：

- Nix package pin: `f20427e9367ae3f66485d85c1be0a08ec612dee2`；
- `server-maintenance/playbooks/nylon-deploy.yml` pin:
  `71d83f3b17ea5abdfe9b682429b0c7e295798f8e`；
- 实施前本机 `~/nylon` 位于 `f20427e`。

因此不得直接运行现有完整 playbook；它会尝试把非 NixOS 节点部署为旧 binary。开始
全网配置切换前，必须按 `deploy-nylon` 流程把 Ansible/Nix pin 统一到同一 reviewed
commit，完成源测试、artifact build、pre-deploy snapshot 和 canary 验证。若不能完成这套
门槛，则停止在“新 NixOS/Tailscale 已上线、旧 Nylon 仍运行”的阶段，不进行 Nylon
身份切换。

### 安装与首次 secrets 解密

新机需要自己的 SSH host key 和 `yifan` 用户 key，才能分别解密共享 NixOS secrets 和
Home Manager secrets。实施前需：

1. 在 `secrets/files/secrets.nix` 注册 `hosts.misc1-sz` 和 `users.misc1-sz` 公钥；
2. 运行 `just rekey`；
3. 通过 nixos-anywhere `extra-files` 写入对应私钥和公钥，保持正确 owner/mode；
4. 安装后确认 agenix、Home Manager、Tailscale 和 Restic 环境均无解密错误。

## 仓库变更

### `~/nix`

1. 新增 `nixos/hosts/misc1-sz/default.nix`：
   - 导入 edge firewall、Nylon public exit、QEMU guest、Tailscale VM exit 和 disko；
   - 启用 Nylon label 101，经 `eth1` / `14.215.130.1`；
   - 保留 serial console，启用 edge firewall。
2. 新增 `nixos/hosts/misc1-sz/networking.nix`：
   - 用永久 MAC 固定命名 `eth0`/`eth1`；
   - `eth0=58.84.55.69/28`，默认网关 `58.84.55.65`；
   - `eth1=14.215.130.15/25`；
   - 独立 `shenzhen` table 100，安装 `14.215.130.1` 默认路由；
   - `from 14.215.130.15/32` 和 `fwmark 0x100` 查询 `shenzhen`。
3. 新增 `nixos/hosts/misc1-sz/disk-config.nix`：QEMU `scsi0`、GPT BIOS、2 GiB
   swap、Btrfs root。
4. 在 `flake/nixos.nix` 注册 x86_64 deployable host。
5. 更新 secrets recipient registry 并 rekey。
6. 运行 `git add -N`、`just fmt`、目标 evaluation/build 和 `just check`。

### `~/tmp/server-maintenance`

1. 把 `host_vars/misc0-sz.ts.gaof.net.yml` 替换为
   `host_vars/misc1-sz.ts.gaof.net.yml`：保留 ID/address/key identity 语义，更新节点名、
   endpoint、bind 和 labels 100/101 的地址。
2. `inventory/tailscale.py`：从 `ROOT_SSH_HOSTS`/`NYLON_HOSTS` 移除 misc0-sz；
   把 misc1-sz 加入 `NYLON_HOSTS` 和 `NIXOS_HOSTS`。
3. 更新 `nylon/runbook.md` 的节点表、IPv6 缺失清单和节点数量。
4. 统一 Nylon source pin，完成技能要求的测试、snapshot 和 canary。
5. 更新 `nylon/maintenance-log.md`，记录切换、回归和异常。

## 实施顺序

### 阶段 1：NixOS 与 Tailscale 上线，不切 Nylon

1. 完成 Nix/secrets 配置并验证 evaluation/build。
2. 启动 VM 105 的临时 Debian，验证两网卡、默认路由、source routing 和公网 SSH。
3. 运行 reinstall preflight，确认 x86_64、SeaBIOS、目标盘精确为
   `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0`。
4. 用固定 nixos-anywhere revision 分阶段执行 kexec、disko、install、reboot；
   `extra-files` 包含新机 SSH host/user keys。目标是本次新建的 VM 105，不接触 VM 103。
5. 验证 hostname、NixOS、磁盘扩容、两条公网链路、policy routing、edge firewall、
   Tailscale node/exit advertisement、failed units 和 secrets 解密。
6. 此阶段 `/etc/nylon` 尚无配置，NixOS 的 `nylon.service` 可因配置不存在而不启动；
   旧 misc0-sz Nylon 继续承载生产角色。

### 阶段 2：准备全网 Nylon 切换

1. 统一 Nylon pins，并通过 deploy-nylon 的 prepare-version/preflight。
2. 保存全网 before snapshot；确认所有现有节点 reachable、无 dispatch drop。
3. 从旧机以 numeric-owner、安全权限归档 `/etc/nylon`；检查 keypair 有效，传到新机但
   不启动服务。
4. 修改并验证维护仓库 inventory/host vars/runbook；确认 inventory 中总节点数不变，
   只是 `misc0-sz` 被 `misc1-sz` 替换。

### 阶段 3：切换窗口

1. 在旧 misc0-sz 停止并禁用 `nylon.service`；确认 UDP 6622 不再监听且 `nylon0`
   不再承载角色。
2. 在新机安装迁移的 keypair，完整运行 `nylon-deploy.yml`，不得使用 `--limit`。
3. 若有 Nix/非 Nix binary rollout，按技能要求先做 NanoPi canary，再做完整 fleet。
4. 完整 playbook 再运行一次，要求每个节点 `changed=0`、`unreachable=0`、`failed=0`。
5. 运行 `nylon-dns-sync.yml`，把 `misc0-sz.ny.gaof.net` 替换为
   `misc1-sz.ny.gaof.net`，overlay 地址保持不变。
6. 重生成四个现役 WLT selector：`el2`、`cjia`、`somo-minisforum`、
   `somo-nanopi-r4s`。

### 阶段 4：验收

1. 新机：
   - `nylon.service` active，UDP 6622 监听；
   - `nylon verify` 成功；
   - overlay 地址为 `.23` / `::23`；
   - 两个 endpoint 与 FakeTCP candidate 正常；
   - labels 100/101 的出口、SNAT、source routing 正确。
2. 全网运行 `SETTLE=120 nylon/regression/run-regression.sh`：
   - 所有节点/overlay 互通；
   - dispatch drop 为 0；
   - 无 unreachable route；
   - 与 before snapshot 相比无 material RTT/route regression。
3. 验证 Tailscale exit、SSH、failed units、Nix substituters 和 PVE guest agent。
4. 确认旧 misc0-sz Nylon 保持 stopped/disabled，但其他服务未受影响。
5. 删除安装 extra-files，并完成维护日志。

## 回滚

- 阶段 1 失败：停止 VM 105；旧 misc0-sz 未变，生产 Nylon 不受影响。
- 阶段 2 失败：不进入切换窗口；旧节点继续运行。
- 阶段 3 在新机启动前失败：恢复 maintenance inventory，重新启用并启动旧
  `nylon.service`。
- 新机已启动后发生异常：先停止新机 Nylon，确认 UDP 6622/overlay identity 已消失，
  再恢复旧机配置并启动旧 Nylon。不得让两端重叠运行。
- 全网 central config 已变更但回滚：恢复旧 inventory/host vars 后完整运行 playbook，
  同样不得使用 `--limit`，随后重跑 DNS、WLT selectors 和 regression。

## 完成条件

- Nix 与 server-maintenance 两边配置和文档均反映 misc1-sz；
- VM 105 稳定运行 NixOS，Tailscale 在线并广告 exit node；
- Nylon mesh 节点数不变，ID 23 的名称/endpoint/出口迁移到 misc1-sz；
- 全网部署 idempotent、DNS/WLT 同步、完整 regression 通过；
- misc0-sz Nylon stopped/disabled，其他服务保持原状；
- 临时私钥材料已从控制机安装目录删除；
- 未创建提交，除非用户另行明确要求。

## 实施结果（2026-08-28）

- VM 105 已安装并启动 NixOS；双公网 SSH、source-policy routing、两条绑定公网
  出站、PVE guest agent 和 secrets 解密均验证通过。
- Tailscale 节点 `misc1-sz` 为 `Running`，控制面已批准 `0.0.0.0/0` 和 `::/0`
  exit 路由。首次冷启动发现 tailscaled 早于静态 WAN 就绪，已在主机配置中加入
  `network-online.target` 顺序约束，并通过再次冷启动验证。
- Nylon pin 已统一到 `f20427e9367ae3f66485d85c1be0a08ec612dee2`；源码测试、
  amd64/arm64 artifact、Nix 检查、迁移前快照和两个顺序 canary 均通过。
- 旧 `misc0-sz` 的 Nylon 已 stopped/disabled，UDP 6622 与 `nylon0` 消失；旧
  binary/config 保留。keypair 经内存管道迁入新机并通过文件哈希和派生公钥校验。
- ID 23、`10.250.10.23`、`fd10:250:10::23` 已由 `misc1-sz` 接管；全网 17 节点
  playbook 成功，第二次完整运行全部 `changed=0`、`unreachable=0`、`failed=0`。
- PowerDNS 已删除旧名称并建立 `misc1-sz.ny.gaof.net` A/AAAA；四个 WLT selector
  已重生成，配置不再引用 `misc0-sz`。
- 回归得到全 overlay 矩阵 0 丢包、0 unreachable、0 dispatch drop。严格最短路径
  快照因非原子 RTT 采样出现 1–7 条、低于 1.3 ms 且不断变化的瞬时 mismatch；五次
  紧凑复测为 2、4、1、4、0，最终 272/272 一致。用户确认无需再做额外长回归。

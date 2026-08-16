# gw-el 迁移到 NixOS 的实施计划

## 目标和边界

本计划把当前 VMware 中运行 Debian 13 的 `gw-el` 替换为一台**新建的 NixOS 虚拟机**。旧虚拟机只在维护窗口前后作为回滚副本，不做原地重装，也不把旧根文件系统复制到新系统。

计划于 2026-08-09 修订，基础运行盘点来自 2026-08-07；正式切换前仍必须重采集一次。方案依据仓库当前主线以及 `nixos/hosts/el2` 的实现重新整理。相似功能优先使用仓库已有的 NixOS 原生模块和 `homeRouter` 设计；旧机上“正在运行”不等于“仍有迁移价值”。

本次复核直接对照了 `nixos/hosts/el2/networking.nix`、`services.nix`、`tailscale.nix`、`wg-iplc.nix`，以及 `nixos/optional/home-router`、`nylon.nix`、`diverge.nix`。主线相关变更包括多 WAN edge routing（`73bbed2`）、原生 diverge/WLT（`7667ce8`）、主机 DNS 经 diverge（`0504ca0`）和海外 IPv6 拒绝策略（`933403c`）；flake 当前锁定的 `diverge-rs` 为 `c0c97b52ac83d6dbc53062637e766934e4f86aa0`。这些实现是目标设计的依据，不把旧 Debian 的 systemd、Docker 或 FRR 配置当作规范。

## 迁移结论

| 现状 | NixOS 处理 | 决策依据 |
| --- | --- | --- |
| 四网卡接入 | `networking.homeRouter` 的 VLAN 641/931/22 + 独立管理口 | gnet641、CERNET、chinanet 分别使用 untagged 网卡，管理网使用第四张网卡且不接入 `br-core` |
| gnet DNS/DHCP | `homeRouter` 生成的 dnsmasq | 与 `el2` 一致；不迁移 Snap 版 AdGuard Home、查询日志、统计和租约数据库 |
| diverge | `nixos/optional/diverge.nix` 的原生 systemd 服务 | 主线已提供 `diverge-rs` NixOS module；dnsmasq 上游继续指向 `127.0.0.1#1054` |
| Nylon | `nixos/optional/nylon.nix` + policy-routing route batches | 当前 FRR 只有 Nylon 的 MPLS LSP；NixOS 模块直接创建 `nylon-routes`、出口 tc/nft/SNAT，不再安装 FRR 或旧的 `nylon-exit-*` unit |
| wg-iplc | NixOS `networking.wireguard.interfaces` | 保留现有 peer、地址和专用路由表；私钥只在运行时文件中提供 |
| Tailscale | NixOS module，迁移 `/var/lib/tailscale` | 保留节点身份、端口 6627、`NetfilterMode=off`/`NoSNAT`/advertised routes 等已确认语义；flags 放在主机配置中 |
| WLT | `networking.homeRouter.wlt` 原生实现 | 与 `el2` 对齐，提供客户端 outlet 选择和持久化 selector 状态；默认海外 IPv4 走 wg-iplc，IPv6 禁用 |
| FRP Server | 不迁移，切换后停用 | 该服务不在新的 NixOS 主机职责内；不迁移配置、token、客户端代理端口或 7000 防火墙规则 |
| light-single | 一个 host-network OCI container | 参照 `el2/services.nix`，由 ACME 证书目录只读挂载；不复制 Docker graph |
| Fail2ban、OpenSSH | NixOS 原生模块 | 当前 sshd jail 仍有效，SSH 主机密钥需保留 |
| vnStat | 不迁移 | 目标机暂不启用 homeRouter monitoring，也不迁移 `/var/lib/vnstat` 历史库 |
| Restic | 不在目标机启用 | `system-manager/restic.nix` 是非 NixOS 主机方案；只在切换前使用旧机做最后一次安全备份 |
| Exim、Shadowsocks、ttr | 删除 | 均已无实际用途；不迁移队列、容器、配置或端口规则 |
| 旧 DNAT/调试规则 | 删除 | 80/8501、8000/8883 DNAT 均无现有消费者；ttr redirect、nftrace 和旧端口白名单也无目标服务 |

## 当前基线

正式切换前仍要重新执行一次只读盘点；以下是已确认的地址和接口事实。

| 接口 | 当前地址 | 网关/用途 |
| --- | --- | --- |
| `gnet` | `100.64.1.254/24` | 内部 LAN，提供 DNS/DHCP |
| `cernet` | `202.38.93.152/24`、`192.168.93.152/24`、`2001:da8:d800:931::152/64` | `202.38.93.254`、`2001:da8:d800:931::1`；另有 `192.168.93.0/24`、`192.168.174.0/24`、`202.38.64.0/24` 路由 |
| `chinanet` | `202.141.162.122/24` | `202.141.162.126` |
| `cmcc` | `202.141.178.12/24` | `202.141.178.126` |

旧 VM 的虚拟硬件为 UEFI、x86_64、4 vCPU、约 3.8 GiB RAM、40 GiB PVSCSI 系统盘和四张 VMXNET3 网卡。新 VM 建议至少 4 GiB RAM、64 GiB 系统盘，并按顺序连接四张 VMXNET3 网卡：`ens192` 接 gnet641、`ens224` 接 CERNET、`ens256` 接 chinanet、`ens161` 接管理网。ESXi 上对应的现有 port group 为 `gnet-bridge`、`cernet`、`telecom` 和 `Management Network`；旧 `gw-debian` 也使用 `gnet-bridge`。ESXi 当前将 `gnet-bridge` 显示为 VLAN ID 64；本次不修改 ESXi 上游映射，NixOS 仅在 `br-core` 内将该 untagged 接入标记为 VLAN 641。虚拟机侧均接收 untagged 帧，不能使用 VLAN 22/931 trunk。管理网与 CERNET 虽同属上游 931 网络，管理网卡仍必须保持独立，不加入 `br-core`。接口名依据现有 VMXNET3 的 PCI 顺序，创建 VM 后仍须在控制台用 `ip link` 核对。

切换前保存：

```text
ip -d link show
ip address show
ip -4 rule; ip -6 rule
ip route show table all
nft list ruleset
wg show
tailscale status
ss -lntup
systemctl list-units --type=service; systemctl --failed
docker ps --no-trunc; docker inspect diverge ttr light-single ssserver-rust
```

确认 FRP 客户端已经迁移到其他入口或不再需要该服务；切换窗口停止旧机 FRPS，目标机不启动 FRPS，也不开放 7000 或其旧的 4000–50000 代理端口。

## el 与 el2 的差异

`el2` 是实现参考，不是可以直接复制的主机配置。两台机器的共同点是 homeRouter、多 WAN 策略路由、Nylon 出口和 diverge；以下差异必须在 `gw-el` 配置中显式保留：

| 方面 | el（目标 NixOS） | el2 | 迁移影响 |
| --- | --- | --- | --- |
| 运行环境 | VMware guest，启用 open-vm-tools，VMXNET3 + PVSCSI | 物理 x86_64 主机，使用 i40e/igb/aacraid/NVMe/SATA | `el` 不复制 `el2` 的 PCI、存储控制器或 CPU 参数 |
| 系统盘 | `/dev/sda` 上 1 GiB ESP + Btrfs 根分区 | 固定 ATA by-id 上的 ESP + Btrfs 根分区 | 新 VM 创建后必须确认系统盘确为 `/dev/sda` |
| 额外存储 | 无 | ZFS `pool0`/`pool1`、加密数据集和同步/快照服务 | 不导入 `el2` 的 ZFS、存储解锁和备份模块 |
| WAN 接入 | `ens224`/`ens256` 分别以 untagged access 接入 931/22 | `uplink0` active-backup bond 承载 VLAN 931/22 trunk | 只复用 VLAN 逻辑，不复用 `el2` 的 trunk 或物理 bond |
| gnet 接入 | `ens192` access/PVID 641，连接外部 gnet 二层网络 | gnet642 是 `br-core` 内部 VLAN，当前 homeRouter 未声明对应物理 access port | `el` 必须保留真实 gnet 物理接入，不能照抄 el2 的纯内部 VLAN |
| 内部 LAN | gnet641，`100.64.1.254/24`，VLAN 641 | gnet642，`100.64.2.254/24`，VLAN 642 | DHCP 地址、域名和内部信任集合使用 el 的值 |
| CERNET/管理地址 | CERNET 接口持有 `202.38.93.152` 和 IPv6 `...::152`；独立 `ens161` 管理口持有 `192.168.93.152` | VLAN 931 持有 `202.38.93.98` 与 IPv6 `...::98`；独立 `ens49f3` 持有 `192.168.93.98` | 两台主机都使用 management 9300 表和管理口 NAT，但设备名与地址不同 |
| 电信/移动地址 | 电信 `202.141.162.122/24`，移动 `202.141.178.12/24` | 电信 `.72/25`，移动 `.7/25` | 两个路由身份共用 VLAN 22，但保留各自网关、表和 SNAT 地址 |
| 专用路由 | 保留 `192.168.174.0/24`、`202.38.64.0/24` 经 CERNET | 无这两条 el 专用路由 | 删除旧机重复的 `192.168.93.0/24` 静态路由和已失效的 WireGuard endpoint host route |
| 策略路由 | 表 93/162/178、management 9300、wg-iplc 5100 | 表号相同 | 删除两台主机误加的 `cernetSourcePrefixes`，共享 datapath 从 WAN 配置派生 mark |
| Nylon exits | label 100/101/102，使用 el 的三个公网源地址 | 相同 label，使用 el2 地址 | 复用原生 module，不迁移 FRR/MPLS 静态配置 |
| WLT | 当前 Debian 没有 WLT；目标 NixOS 必须启用 | 已启用 WLT，并以 `wg-iplc` 作为默认 outlet | 采用 `el2` 的 WLT 入口、selector 持久化和默认出口语义 |
| DNS/DHCP 域 | 目标 dnsmasq 使用 `el.gaof.net`；旧机是 AdGuard Home + 容器 diverge | dnsmasq 使用 `el2.gaof.net` + 原生 diverge | 共享模块只复用机制，不复制 el2 的域名 |
| IPv4/IPv6 出口 | 旧机有宽泛 nft 分类和海外路径 | 主线明确区分中国/海外，海外 IPv6 拒绝 | 采用 el2 的 classifier 语义，不迁移旧 nft 表 |
| Tailscale | 迁移现有节点状态，端口 6627，广告旧机现有八条子网 | 广告 el2 自身子网、Nylon/WireGuard 网段和 /32，另有 Tailscale Serve | 不复制 el2 的 advertised routes 或 Serve 映射 |
| WireGuard | 仅 `wg-iplc`，地址 `11.13.112.74/24` | `wg-iplc` 为 `.77/24`，并有面向客户端的 `wg0` | 不复制 el2 的 wg0、用户配置或地址 |
| UDP 2197 | 从三类公网入口 DNAT 到 `202.38.93.98` | 本机 wg0 监听该端口 | `el` 只做有消费者的转发，不在本机启动 wg0 |
| 监控 | 旧机只有 vnStat；目标不启用 homeRouter monitoring | 当前 el2 主机配置也未启用 homeRouter monitoring | 不迁移 vnStat，也不在本次迁移中新增 Prometheus/Grafana |
| 运行服务 | 目标只含 dnsmasq、diverge、WLT、Nylon、Tailscale、SSH/Fail2ban、ACME 和 Light | 另有 DERP、ncps、wg0、Incus、媒体、存储和备份服务 | 不复制 `el2` 的业务服务集合 |
| 容器 | 仅 `light-single` | Light 之外还有媒体、数据库和存储相关容器 | 不复制 el2 容器，也不复制旧 Docker graph |
| 公网端口 | SSH、Light、Nylon、Tailscale、tsshd UDP 范围及 2197 DNAT | 另开放 iperf、ncps、DERP、STUN、wg0 等 | 共享过滤器由每台主机显式提供端口集合 |
| Podman/管理规则 | 无 podman DNS/8000 例外；`ens161` 做管理口 masquerade | 保留 podman DNS/8000/forward 与 `ens49f3` 管理口 masquerade | 共同复用管理网模式，Podman 规则仅由 el2 保留 |
| 备份 | NixOS 目标不启用 Restic；另制作旧根目录 squashfs 供查阅 | 有主机专用 Restic/Kopia/ZFS 任务 | 不复用 el2 或 system-manager 的备份服务 |
| 防火墙 | 仅保留仍有消费者的端口、SNAT 和 2197 DNAT | 共享基础规则外还有 el2 服务端口 | 删除 ttr、FRP、Shadowsocks、Exim、FRR 和调试遗留规则 |

## 目标网络设计

### homeRouter 和 dnsmasq

`networking.homeRouter.enable = true`，内部交换桥使用 `br-core`，并用 VLAN 拓扑尽量对齐 `el2`：

- `switch.ports.ens192.untagged = 641`、`switch.ports.ens224.untagged = 931`、`switch.ports.ens256.untagged = 22`。ESXi 分别完成 access VLAN 映射，guest 内不收发 802.1Q trunk。
- `lans.gnet641.vlan = 641`，gnet 主机接口为 `br-core.641`，地址为 `100.64.1.254/24`；关闭 LAN IPv6，DHCP 范围为 `100.64.1.100–100.64.1.200`、租期 1 小时。
- `wans.cernet.vlan = 931`、`wans.chinanet.vlan = 22`、`wans.cmcc.vlan = 22`，分别配置现有公网地址、网关和路由表 93/162/178；额外保留 `192.168.174.0/24` 和 `202.38.64.0/24` 两条 CERNET 路由。
- `ens161` 不加入 switch ports，单独配置 `192.168.93.152/24`、management 表 9300 和经 `192.168.93.254` 的源策略路由。
- dnsmasq 的本地域名采用 `el.gaof.net`；el2 使用的是 `el2.gaof.net`，两者不应混用。保留 `/cjia.gaof.net/100.65.1.254`、`/somo.gaof.net/100.65.2.254` 条件转发以及 `127.0.0.1#1054` 默认上游。现有配置未找到 `.lan` 的实际消费者，因此不迁移 `.lan` 域。
- dnsmasq 监听 LAN、`lo`、`tailscale0` 和 `wg-iplc`（按 homeRouter 的 `extraInterfaces` 配置），`resolved` 通过 `homeRouter.serviceAddresses.ipv4` 使用本机 dnsmasq。
- `homeRouter.wlt.enable = true`，domain 使用 `gaof.net`，默认 IPv4 outlet 为 `0x100`（wg-iplc），默认 IPv6 为 `disabled`；WLT 所需 TLS、SSH host key 和 selector 持久化状态通过 secrets 与 `/var/lib/wlt` 提供。

这一步完全替代 AdGuard Home；不得同时运行两个 DHCP/DNS 服务，也不要复制 `/var/lib/snapd`、AdGuard 查询日志或旧租约数据库。

### 策略路由、出口和 WireGuard

使用 homeRouter 的 policy routing 和主线 `el2` 的分类思路：CERNET/电信/移动目的地址分别标记 93/162/178，中国地址默认走电信，其他 IPv4 标记 `0x100` 进入 `wg-iplc` 表 5100。WLT 负责内部客户端的 outlet 选择，默认 IPv4 outlet 为 `0x100`，默认 IPv6 禁用；自定义 egress classifier 只处理 WLT 未标记的主机、转发和 Nylon/Tailscale 流量。保留已确认的 Nylon/Tailscale UDP 源端口（6622、6627）和管理源地址的出口选择；不要把旧机的 conntrack mark 数字原样复制。

`wg-iplc` 使用当前 `11.13.112.74/24`、MTU 1392、运行时私钥 `/var/lib/wireguard/wg-iplc-private-key`、table 5100、fwMark `0x90000` 和现有 peer endpoint。主机 IPv6 继续采用主线的明确策略：国内 IPv6 可走 CERNET，海外 IPv6 直接拒绝，避免误经 IPv4 隧道。

### Nylon（不使用 FRR）

```nix
services.nylon = {
  enable = true;
  policyRouting.enable = true;
  overlay.ipv4Subnet = "10.250.10.0/24";
  overlay.ipv6Subnet = "fd10:250:10::/64";
  exits = {
    cernet = { label = 100; interface = "cernet"; ... };
    chinanet = { label = 101; interface = "chinanet"; ... };
    cmcc = { label = 102; interface = "cmcc"; ... };
  };
};
```

实际地址和网关填入上表的 `gw-el` 值。迁移 Nylon 节点/central YAML、私钥和 Ansible 渲染的 `/var/lib/nylon/policy-routing/{routes,rules}{4,6}.batch`；不要迁移 FRR 配置、`tun-lugi` LSP、`nylon-exit-fwd.service`、`nylon-exit-snat@.service` 或手写 MPLS 静态路由。目标机只运行 NixOS module 生成的 `nylon.service`、`nylon-routes.service` 和相关 nft/tc 规则。

### Tailscale

使用 `nixos/optional/tailscale-gnet.nix`，主机文件仿照 `el2/tailscale.nix` 定义 flags 和 `port = 6627`。广告路由以切换前 `tailscale status`/控制面批准结果为准，当前需要覆盖：`10.254.0.0/21`、`100.64.0.0/24`、`100.64.1.0/24`、`192.168.93.0/24`、`192.168.174.0/24`、`202.38.93.0/24`、`202.141.162.0/24`、`202.141.178.0/24` 以及 exit-node 语义。保留 `RouteAll=true`、`NoSNAT=true`、`NetfilterMode=off` 的现有意图，并迁移 `/var/lib/tailscale` 以避免注册新节点。

## 服务和数据实现

已实现的主机文件：

```text
nixos/hosts/el/
├── default.nix
├── disk-config.nix
├── hardware-configuration.nix
├── networking.nix
├── services.nix
├── tailscale.nix
└── wg-iplc.nix
```

`networking.nix` 导入 `../../optional/home-router` 和共享的 `../../optional/gnet-edge-router.nix`；后者封装 el/el2 共同的 Nylon exits、策略路由、GeoIP classifier、SNAT 和基础过滤器。`services.nix` 导入原生 diverge 与 ACME 证书模块，并声明 Fail2ban 和 `light-single`。目标不启用 Docker 兼容层；OCI backend 只运行 Light。

本次迁移不启用 `networking.homeRouter.monitoring`，不创建 Prometheus/Grafana 状态。

### 需要迁移的持久状态

| 状态 | 处理 |
| --- | --- |
| SSH host keys | 在新 NixOS 首次启动前复制 `/etc/ssh/ssh_host_*`；agenix 已授权现有 ED25519 host key，且最终主机继续保留原指纹 |
| Tailscale | 复制 `/var/lib/tailscale`，先停旧机 tailscaled，启动后核对同一节点 |
| Nylon | 迁移 `/etc/nylon` 中 node/central 配置和密钥；route batches 由维护仓库重新渲染并校验 |
| WireGuard | 私钥部署到 `/var/lib/wireguard/wg-iplc-private-key`，权限 0600；不复制失效的 `wg-quick` unit |
| WLT | `el` 当前没有 WLT 状态可迁移；首次启动由原生服务创建 `/var/lib/wlt`，保留之后生成的 selector 持久化文件 |
| TLS/Light | 采用现有 ACME 证书模块和 `el2` 的只读证书挂载，不复制 Docker 内部层 |
| diverge | 使用主线 `diverge-rs` module 的声明式配置；不复制旧 `/home/yifan/diverge.conf` 或容器状态 |
| 监控 | 不启用 Prometheus/Grafana；不迁移 vnStat 数据库和旧查询日志 |

旧机现有 Restic 任务在切换前可最后执行一次，但它不是 NixOS 设计的一部分。目标 NixOS 不启用 Restic service/timer，代码已从 `flake/system-manager.nix` 的非 NixOS 主机列表移除 `gw-el`；长期可查阅副本以本地 root squashfs 归档为准。

## 旧系统根目录归档

在 `el`（当前主机名为 `gw-el`）关机前，必须把根目录完整归档到迁移工作站或其他独立的本地存储。该归档只用于关机后的查阅和取证，不作为 NixOS 的文件系统、服务状态或 secrets 导入源。

1. 在迁移工作站准备容量至少与旧根文件系统已用空间相当的目录，例如 `/srv/migration/gw-el-20260809/`；该目录不应位于 `el` 的系统盘。
2. `el` 仍在线时先执行一次完整同步；在维护窗口停止会写入状态的服务后再执行第二次同步，减少快照时差。同步需保留 owner、权限、ACL、xattr、硬链接和数字 UID/GID，并只排除伪文件系统及临时挂载：`/proc`、`/sys`、`/dev`、`/run`、`/tmp`、`/mnt`、`/media`、`/lost+found`。

   ```bash
   rsync -aHAX --numeric-ids --one-file-system \
     --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/run \
     --exclude=/tmp --exclude=/mnt --exclude=/media --exclude=/lost+found \
     el:/ /srv/migration/gw-el-20260809/root/
   ```

   实际执行时使用具备读取旧机根目录权限的 rsync 传输方式；不要把包含密码、私钥和证书的输出目录加入 Git。
3. 在本地同步目录制作 zstd 压缩的 squashfs，并记录校验值：

   ```bash
   mksquashfs /srv/migration/gw-el-20260809/root \
     /srv/migration/gw-el-20260809/gw-el-root.squashfs \
     -comp zstd -noappend
   sha256sum /srv/migration/gw-el-20260809/gw-el-root.squashfs \
     > /srv/migration/gw-el-20260809/SHA256SUMS
   ```

4. 用 `unsquashfs -s` 检查镜像元数据，并在需要时以只读方式挂载镜像验证 `/etc`、`/var/lib`、容器配置和网络文件可查阅。确认镜像和校验文件已复制到第二个独立位置后，才允许关闭 `el`。

## 防火墙和转发处置

目标采用 homeRouter/nftables 的默认拒绝、已建立连接、内部/Tailscale/WireGuard/Nylon 信任和显式 WAN 服务规则。不要保留旧 nft 表的重复 anchor 或 `ip daddr != 100.64.0.0/10 masquerade` 这类宽泛规则；NAT 由 homeRouter、wg-iplc 和 Nylon 模块按出口生成。

| 旧规则/端口 | 处理 |
| --- | --- |
| TCP DNAT 80/8501 → `100.64.1.25` | 删除；目标已验证无监听且仓库无消费者 |
| TCP DNAT 8000/8883 → `100.64.1.20` | 删除；目标已验证无监听且仓库无消费者 |
| UDP DNAT 2197 → `202.38.93.98` | 保留；`el2/wg0.nix` 仍使用该地址作为 wg0 endpoint，验收时从外部测试 |
| ttr 的源地址 redirect → 10080 | 删除；ttr 弃用 |
| Shadowsocks 27481、Exim 25 | 删除服务和端口 |
| TCP/UDP 5201 | 保留，用于 iperf3 |
| 旧 TCP 4443/6001/12345、UDP 6626/12345/27481/51800/51823 | 删除；没有目标监听或已确认过时 |
| FRR/`tun-lugi` 相关规则、重复 `nylon_exit` 表 | 删除；由 `services.nylon` 接管 |
| `ip daddr 10.254.0.31 meta nftrace set 1` | 删除；调试规则不进入生产配置 |
| SSH 特定源地址 allowlist | 删除重复项；保留通用 TCP 22 + Fail2ban |
| TCP 22、29979–29980 | 保留，分别用于 SSH 和 Light |
| UDP 6622、6627、61001–61999 | 保留，分别用于 Nylon、Tailscale 和现有 tsshd 管理工作流；若 tsshd 工作流已停用则连同范围删除 |

切换前对端口转发和 `100.64.1.0/24` 业务做一次流量观察；观察结果只能增加有证据的规则，不能恢复上述已判定无用的历史端口。

## 实施阶段

### 1. 盘点和冻结

重新采集网络、nftables、监听端口、容器、Nylon/Tailscale 状态；确认新 VM 的 gnet641、CERNET、chinanet 和独立管理网四个 untagged port group 及网卡顺序。确认 UDP 2197 的外部调用方。完成旧系统根目录归档；旧机最后一次 Restic 运行不构成目标机备份设计。

### 2. 编写和构建配置

新增 `nixosConfigurations.el` 和 `deploy.nodes.el`，从 system-manager 的非 NixOS 主机列表移除 `gw-el`。不设置 `el-install` 中间配置。先以 `git add -N` 纳入新 `.nix` 文件，再运行：

```bash
just fmt
just check
nix build '.?submodules=1#nixosConfigurations.el.config.system.build.toplevel'
nix build '.?submodules=1#nixosConfigurations.el2.config.system.build.toplevel'
```

分别检查生成的 networkd、policy-routing、nftables、dnsmasq、diverge、Nylon 和 tailscaled unit；把每个有意删除的旧规则记录在差异表中。

### 3. 安装新 VM

新 VM 使用 UEFI、PVSCSI 和四张 VMXNET3，按 `gnet-bridge`、`cernet`、`telecom`、`Management Network` 的顺序连接 port group。旧机完成最后同步并关机后，直接安装最终 `el` 配置，不使用临时 `el-install` generation。安装时把旧机 SSH host keys 写入目标 `/etc/ssh`，否则系统无法解密 agenix secrets。首次启动前核对 `/dev/sda`、`ens192`、`ens224`、`ens256`、`ens161` 及四个 port group 的对应关系。

### 4. 维护窗口切换

1. 冻结变更，停止旧机上的 AdGuard、diverge、Nylon、Tailscale、Light，以及待淘汰的 ttr、`ssserver-rust`、Exim、FRPS 等会写状态的进程。
2. 核对已经预置的 SSH host keys，并最后同步 Tailscale 状态、Nylon 配置/route batches 和证书；不复制 AdGuard/vnStat/Restic/Exim/Shadowsocks/ttr 状态。
3. 通过 VMware 控制台关闭旧 VM。
4. 安装并启动新 VM 的最终 `el` generation。
5. 先从 VMware 控制台检查接口名、四个网络的地址、路由、默认拒绝策略及 failed units；确认管理网、Tailscale/SSH 恢复后再开放业务流量。

### 5. 验收和回滚

验收通过后保留旧 VM 关机至少 7 天。若核心网络、DNS/DHCP、Tailscale、Nylon 或关键业务失败，先关闭新 VM 并断开生产网卡，再启动旧 VM；不要让两台机器同时使用生产地址。

## 验收标准

- NixOS 可从 UEFI 启动，`systemctl --failed` 为空，`nixos-rebuild switch --flake '.?submodules=1#el'` 可重复执行。
- VLAN 641/931/22、全部公网/管理地址、两条 CERNET 专用路由、策略路由和 `wg-iplc` 出口与基线一致；中国/海外 IPv4 分类符合设计，海外 IPv6 按预期拒绝。
- gnet 客户端能从 dnsmasq 获取 `100.64.1.100–200` 租约，能解析 `el.gaof.net`、`cjia.gaof.net`、`somo.gaof.net`；默认请求经本机 diverge `127.0.0.1:1054`。
- `diverge.service`、`nylon.service`/`nylon-routes.service`、`tailscaled.service`、WireGuard 的 `wg-iplc` 接口、Fail2ban 和 Light 正常运行；系统中没有 FRR、AdGuard、Restic、Exim、Shadowsocks、ttr、FRPS 或旧容器。
- WLT portal 可从 gnet 和 Tailscale 访问，客户端 outlet 选择能够改变源地址到 mark 的映射并在重启后恢复；默认海外 IPv4 走 `wg-iplc`，海外 IPv6 按设计禁用。
- Tailscale 节点身份未变化，端口 6627 可达，广告路由和 exit-node 行为与切换前批准状态一致。
- Nylon 三个出口 label 100/101/102 可达，`nylon0` 产生预期 MPLS/policy routes；`ip link`、`ip route` 和 nft 规则中不出现 FRR/tun-lugi 遗留项。
- 系统不运行 homeRouter Prometheus/Grafana/node/ping exporter，不要求保留 vnStat 历史曲线。
- 外部仅能访问明确保留的 SSH、iperf3 5201、Light 29979/29980、Nylon 6622、Tailscale 6627、tsshd 管理范围和 UDP 2197 DNAT；已删除端口均无监听或转发。

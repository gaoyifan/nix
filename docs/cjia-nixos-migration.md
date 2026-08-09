# cjia（NanoPi R4S）迁移到 NixOS 的实施计划

本文依据 2026-08-10 对 `cjia.ts.gaof.net` 的在线盘点，以及仓库当前的
`somo-nanopi-r4s`、`homeRouter`、Nylon、WLT 和 diverge 实现制定。迁移使用另一张
SD 卡，不在现有 Armbian 系统上原地重建；旧 SD 卡保持不变，作为回滚介质和离线参考。

## 现状与目标

cjia 是 4 GiB NanoPi R4S。Armbian 从 32 GiB SD 卡启动，内置 GMAC `lan0` 承载
`100.65.1.0/24`，PCIe RTL8168 `wan0` 接入中国电信并由 `ppp0` 拨号。NixOS 下相同
硬件分别命名为 `end0` 和 `enp1s0`；目标配置在 `end0` 上建立 homeRouter 的单一
untagged LAN，在 `enp1s0` 上运行 PPPoE 并保留独立的静态管理地址。

目标不是复刻 Armbian 的安装方式和全部历史服务，而是保留当前仍有实际用途的网络
语义，并改用仓库现有的 NixOS 原生实现。

| 现有功能 | 目标实现 | 处理结论 |
| --- | --- | --- |
| PPPoE、中国电信默认出口 | NixOS `services.pppd` + networkd 路由表 | 保留账号和 CHAP/PAP secrets；由 systemd 负责持续重拨，删除每分钟执行的 `gard-ppp0.sh` |
| LAN DNS/DHCP | `networking.homeRouter` 生成的 dnsmasq | 保留 `100.65.1.100`–`199`、24 小时租期和 `cjia.gaof.net`；不迁移 AdGuard Home、查询日志和租约库 |
| 国内/海外/科大路由 | nftables classifier + 声明式 RPDB | 国内走 PPPoE，海外走 `wg-iplc`，USTC 网段经 Nylon 走 el2 的 CERNET exit；WLT 选择优先于默认分类 |
| `wg-iplc` | NixOS WireGuard interface | 保留海外 IPv4 隧道和地址 |
| `wg-el` | 删除 | USTC 流量改走 Nylon，不再保留独立 WireGuard 接口和私钥 |
| `wgnd-tw` | 删除 | 已十天没有握手，Apple 流量被送入该隧道后全部超时；删除黑洞规则后按普通国内/海外策略路由 |
| Nylon | `nixos/optional/nylon.nix` | 保留节点配置、overlay 和本机 PPPoE exit label 100；不迁移 FRR 和旧 `nylon-exit-*` units |
| WLT | `networking.homeRouter.wlt` | 改用原生服务；保留 selector 快照，默认海外 IPv4 为 `wg-iplc`，IPv6 禁用 |
| diverge | `nixos/optional/diverge.nix` | 使用当前主线的原生模块，监听 `127.0.0.1:1054`；删除 Docker 容器 |
| Tailscale | `tailscale-gnet.nix` | 保留节点状态、UDP 6627、exit node 和 `100.65.1.0/24` 路由广告；不注册新节点 |
| Homebridge | NixOS `services.homebridge` | 迁移较新的 Snap 状态和两个插件；删除已经失效的 Docker/macvlan 副本 |
| GoDNS | NixOS `services.godns` | 保留 `cjia.ddns.gaof.net` 的 HE.net 更新，密码通过 systemd credential 注入 |
| vnStat | homeRouter Prometheus + Grafana | 不迁移 vnStat 数据库；Grafana 仅允许 LAN、loopback 和 Tailscale 访问 |
| FRR、AdGuard Home、ttr | 不安装 | 均不复制配置、状态、容器或遗留规则 |
| phantun、TunnelMonitor、迅雷快鸟及未启用 WireGuard | 不安装 | 当前均未运行；不迁移 disabled/failed units 和 cron 重解析任务 |

## 目标网络

### 接口与地址

- `end0` 加入 VLAN-aware `br-core`，以 untagged VLAN 651 承载 LAN；主机三层接口为
  `br-core.651`，地址 `100.65.1.254/24`。不延续旧 diverge 使用的
  `198.18.0.1/24` LAN 地址。
- `enp1s0` 同时作为 PPPoE carrier 和管理接口；不再获取当前
  `192.168.125.2/24` DHCP 地址，改用静态地址 `192.168.125.254/24`。
- `ppp0` 安装 main 和 `ppp` 表的默认路由，并作为 homeRouter 的 NAT、监控和 Nylon
  本地 exit 接口。
- `wg-iplc` 保留 `11.13.112.43/24`，路由表 `wg-iplc`，用于海外 IPv4。
- USTC 目的网段使用 selector mark `0x38`，命中 Nylon 维护流程渲染的 el2 CERNET
  route：`encap mpls 20/100`、table 5008。PPPoE 兜底规则位于 Nylon selector rules 之后。
- LAN 暂无可用原生 IPv6 前缀，因此不发送 RA；WLT 的 IPv6 outlet 明确禁用。

### DNS、DHCP 与服务发现

dnsmasq 仅在 LAN 和 Tailscale 上提供服务。DHCP 默认网关和 DNS 均为
`100.65.1.254`，动态地址范围为 `100.65.1.100,100.65.1.199,24h`；当前没有静态
租约。上游保留：

- `/taildeb190.ts.net/100.100.100.100`
- `/somo.gaof.net/100.65.2.254`
- `127.0.0.1#1054`（diverge）

Avahi 在内部 LAN 上发布 Homebridge 所需的 mDNS，不向 PPPoE 公网反射。

### 路由、NAT 与防火墙

默认分类只处理尚未被 WLT/conntrack 标记的流量：CN 目的地标记为 PPPoE，USTC
目的地标记为 el2 CERNET 的 Nylon selector，其余 IPv4 标记为 `wg-iplc`。Tailscale
和 Nylon 自身的 UDP transport 不强制进入代理隧道。LAN 经 PPPoE 和 `wg-iplc` 的
流量分别 masquerade；Nylon 的 overlay NAT、MPLS LSP 和 route batches 由 NixOS
Nylon 模块负责。

公网 `ppp0` 输入仅开放 SSH、TCP/UDP 5201、Nylon UDP 6622 和 Tailscale UDP
6627，并允许 ICMP 与已建立连接。来自 PPPoE、WireGuard 或 Nylon 的新建连接不能
直接进入 LAN；Tailscale 仍可按路由广告访问 LAN。以下旧规则删除：

- 指向本机不存在的 TCP 1080 的 7575–7577、8484 和两个公网地址重定向；
- `tcp sport 41139` 单点 drop、宽泛的历史接口集合和空的 IPv6 表；
- FRR/MPLS 手写规则和重复的 `nylon_exit` 表；
- Apple 目的地址强制进入失效 `wgnd-tw` 的规则；
- 已不存在的 `maple`、`wg-lug`、`wg-dev-gw`、`wg-ddl` 等策略表。

## 持久状态与 secrets

新的 SD 镜像不包含运行时私钥或设备状态。状态迁移采用“本机归档、首次启动时保持
服务 mask、恢复状态、正式启动”的顺序，不在服务运行时复制，也不允许新旧两套
Tailscale 或 Homebridge 同时上线。

切换前先做一次预备归档；进入维护窗口后停止旧机上的 Tailscale、Homebridge、Nylon
等写状态服务，再通过 SSH 将最终归档直接流式保存到迁移工作站。归档保留 numeric
owner、ACL 和 xattrs，记录 SHA-256，并以仅 root 可读或 age 加密的形式存放，不进入
Git。归档含 Tailscale 身份、HomeKit pairing、Nylon 私钥和设备凭据，应按 secret
处理。

### 状态范围

| 状态 | 目标 |
| --- | --- |
| `/etc/ssh/ssh_host_*` | 相同路径；首次启动前离线恢复，保留 SSH 身份，并使 agenix 可以解密 cjia secrets |
| `/var/lib/tailscale/` | 相同路径；迁移整个约 64 KiB 的目录，保留 node/machine key、profile、控制面身份和 Taildrop 状态 |
| `/etc/nylon/{central.yaml,node.yaml,private.key,public.key}` | 相同路径；route/rule batches 由维护流程按当前拓扑重新渲染到 `/var/lib/nylon/policy-routing` |
| `/var/snap/homebridge/common/{config.json,persist,accessories,auth.json,.uix-secrets,.uix-dashboard.json,.config,package.json}` | `/var/lib/homebridge`；保留 bridge identity、HomeKit pairing、UI 账号和插件配置，恢复后递归改为 `homebridge:homebridge` |
| `/etc/nftables/wlt_src2mark.conf` | 当前只有注释、没有 selector 条目，不迁移；新 WLT 从空的持久状态开始 |
| GoDNS、dnsmasq、Grafana/Prometheus、diverge | 不迁移运行状态；GoDNS 密码由 agenix 提供，DHCP leases、旧 DNS 查询记录和监控历史不保留 |

Tailscale 必须在旧机 `tailscaled` 完全停止后归档。目标机恢复整个
`/var/lib/tailscale`，保持 `root:root` 和目录模式 0700；启动后不得执行带 auth key 的
`tailscale up`。验收时确认 node ID 仍为 `n2UPBsBVan11CNTRL`，DNS 名仍为
`cjia.taildeb190.ts.net`，地址仍为 `100.127.100.3`，并确认 exit node 和
`100.65.1.0/24` 路由仍获控制面批准。旧机和目标镜像均使用 Tailscale 1.98.8。

Homebridge 不复制完整的 1.2 GiB Snap 数据目录：约 1004 MiB 的 `.npm`、185 MiB 的
`node_modules`、日志和历史备份不恢复到运行目录；备份可仅留在迁移工作站供查阅。
NixOS Homebridge 的 pre-start 会保留旧 `config.json` 中的 bridge username、PIN、
platform/accessory 和设备凭据，同时覆盖目标接口 `br-core.651`、端口与 Avahi 设置。

当前在线实例使用 Homebridge 2.2.1、`homebridge-playstation` 1.7.3 和
`homebridge-xiaomi-mi-air-purifier` 2.0.2，而当前镜像中的 Nixpkgs Homebridge 是
2.0.2，两个插件也尚未由 Nix 提供。正式切换前必须将 Homebridge 固定到 2.2.1，并把
两个插件做成声明式 Nix package 后重新构建镜像；不得以复制旧 `node_modules` 的方式
掩盖版本差异。恢复后以 `homebridge:homebridge` 运行，确认 HomeKit 无需重新 pairing。

### 首次启动与恢复

刷卡后先挂载新 SD 卡的 root 分区，只离线写入旧 SSH host keys。首次启动通过 kernel
参数 mask `tailscaled.service`、`homebridge.service`、`nylon.service`、
`nylon-routes.service`、`nylon-exit.service` 和 `wlt.service`，避免它们创建新身份或
空状态。通过 `enp1s0` 的 `192.168.125.254` 管理地址登录后：

1. 恢复 `/var/lib/tailscale`，核对 root 所有权和 0700 目录模式。
2. 恢复 Homebridge 的选定状态，执行递归 `chown`，但不恢复 `.npm` 和
   `node_modules`。
3. 恢复 `/etc/nylon`，再由维护流程渲染当前拓扑的 route/rule batches；确认 cjia
   存在 `encap mpls 20/100 dev nylon0 table 5008` 和 `0x38` 到 table 5008 的规则。
4. 去掉首次启动的 service masks 并重启，依次启动、验证 Tailscale、Nylon、WLT 和
   Homebridge。

PPPoE peer、CHAP/PAP、`wg-iplc` private key 和 GoDNS HE.net 密钥从在线旧机直接
写入私有 agenix submodule，不以明文进入 Git 或 Nix store。共享的 WLT TLS/SSH key
和 root password secret 增加 cjia 的现有 SSH host key recipient。

旧 SD 卡不重写，也不把 24 GiB 的 Armbian 根目录塞进新镜像。切换前另在迁移工作站
保存上述状态目录的带权限归档和校验值；旧 SD 卡本身作为完整离线参考。

## 实施顺序

1. 在仓库中抽出 NanoPi R4S 共用的 kernel、U-Boot 和 `sdImage` 模块，使
   `somo-nanopi-r4s` 与 cjia 不重复硬件配置。
2. 新增 `nixos/hosts/cjia`，声明 PPPoE、LAN、WireGuard、分类路由、NAT、防火墙、
   Nylon、WLT、diverge、Tailscale、GoDNS、Homebridge 和 monitoring。
3. 在 flake 中导出 `cjia` NixOS configuration、deploy node 和 `cjia-image`；让
   `just build-nanopi-image <host>` 可选择两台 R4S，而不再硬编码 SOMO。
4. 写入并 rekey cjia 所需 age secrets。先执行格式化、Nix 求值和相关 tests，再构建
   `packages.aarch64-linux.cjia-image`。
5. 对镜像执行 `file`、压缩镜像信息和 closure 输出检查，记录最终路径和 SHA-256。
6. 实际切换时停止旧机的 PPPoE、Tailscale、Nylon、WLT、Homebridge、GoDNS 和容器，
   完成最后状态归档；刷写新 SD 卡并离线写入 SSH host keys，首次启动时保持状态服务
   masked，再通过管理网恢复 Tailscale、Homebridge 和 Nylon 状态。
7. 启动后依次验证接口命名、PPPoE、DNS/DHCP、国内/海外/USTC 出口、WLT、Nylon、
   Tailscale、Homebridge、DDNS、Grafana 和公网端口；失败时关机换回旧 SD 卡。

## 验收标准

- R4S 能从构建的 SD 镜像启动，`end0`/`enp1s0` 对应关系正确，PPPoE 可持续重拨，
  `enp1s0` 可通过 `192.168.125.254/24` 管理。
- LAN 客户端获得 `100.65.1.100`–`199` 地址，可解析本地域和公网；系统中没有
  AdGuard Home、FRR、vnStat、ttr 或旧 Docker 服务。
- CN、海外和 USTC 流量分别命中 PPPoE、`wg-iplc`、el2 CERNET 的 Nylon exit，WLT
  可覆盖默认选择；系统中不存在 `wg-el` 接口；
  Apple 流量不再进入 `wgnd-tw` 黑洞。
- Tailscale 节点身份不变，仍广告 exit node 与 `100.65.1.0/24`，Nylon exit label
  100 使用动态 `ppp0` 地址完成 SNAT。
- Homebridge 保持原 HomeKit pairing、PlayStation 和米家空气净化器插件可用；只运行
  一套实例。
- `cjia.ddns.gaof.net` 随 PPPoE 地址更新；Grafana 可从 LAN/Tailscale 打开，公网不可达。
- 公网只出现计划中的 SSH、5201、6622、6627；旧 10080、1080 和容器端口不再监听。

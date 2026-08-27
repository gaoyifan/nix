# Home Router 共同能力的统一抽象

> 调查日期：2026-08-25。范围为仓库中 `cjia`、`el`、`el2`、
> `somo-minisforum` 和 `somo-nanopi-r4s` 五台 Home Router 的配置求值结果。
> 本文记录配置设计调查，不代表线上部署状态。

## 结论

除了 OUTPUT 默认出口选择和 POSTROUTING masquerade，以下四项适合继续由
`home-router` 统一拥有：

| 候选能力 | 五台配置的共同点 | 建议归属 |
| --- | --- | --- |
| Edge firewall | 全部启用 | 成为 `homeRouter` 的安全不变量 |
| WAN 监控 | 全部启用，并覆盖全部已配置 WAN | 默认启用，自动推导 WAN 列表 |
| WLT | 全部启用 | 成为 `homeRouter` 的默认能力，保留显式退出方式 |
| Tailscale 内网集成 | 全部启用，DNS 都监听 `tailscale0` | 由适配层统一 DNS、可信入口和 LAN 路由发布 |

优先级建议是：先收紧 Edge firewall 的模块边界，再统一监控和 WLT，最后处理
Tailscale 路由发布。Nylon 虽然五台都使用，但不适合直接并入 `home-router` 核心。

## 已验证的共同配置

对五台主机求值后，以下选项全部为真：

- `networking.edgeFirewall.enable`
- `networking.homeRouter.monitoring.enable`
- `networking.homeRouter.wlt.enable`
- `networking.homeRouter.wgIplc.enable`
- `services.nylon.enable`
- `services.nylon.policyRouting.enable`
- `services.tailscale.enable`

每台机器的 `networking.homeRouter.monitoring.wans` 都等于该机定义的全部 WAN：

| 主机 | WAN |
| --- | --- |
| `cjia` | `ppp` |
| `el` | `cernet`、`chinanet`、`cmcc` |
| `el2` | `cernet`、`chinanet`、`cmcc` |
| `somo-minisforum` | `cmcc` |
| `somo-nanopi-r4s` | `cmcc` |

五台机器的 dnsmasq 额外监听接口都包含 `tailscale0`。Avahi 则并不一致：
`cjia` 和两台 SOMO 启用，`el`、`el2` 禁用。

## 1. Edge firewall 应成为安全不变量

已验证事实：[`home-router/default.nix`](../../nixos/optional/home-router/default.nix)
启用后会关闭传统的 `networking.firewall` 并启用 nftables，但它本身不导入或启用
[`edge-firewall.nix`](../../nixos/optional/edge-firewall.nix)。目前依赖
`somo-router.nix`、`el-router.nix` 和 `cjia` 的调用层分别补上 Edge firewall。

这使模块组合过浅：启用 `homeRouter` 并不保证存在默认拒绝的边界防火墙。如果以后新增
Home Router 调用点而遗漏适配层，可能得到开启转发但缺少预期入口保护的配置。

建议：

- `homeRouter` 直接导入并启用 Edge firewall。
- 继续由现有推导逻辑信任内部网络接口、`tailscale0` 和 `nylon0`。
- 主机配置只提供真正特有的额外端口、INPUT/FORWARD 规则和可信接口。

这是安全边界，不只是减少重复，因此应当最先完成。

## 2. WAN 监控应从 WAN 定义自动推导

已验证事实：五台机器都启用
[`monitoring.nix`](../../nixos/optional/home-router/monitoring.nix)，且监控列表没有排除任何
已配置 WAN。重复声明 `monitoring.wans` 没有表达额外意图。

实施状态（2026-08-28）：`homeRouter` 现在以 `mkDefault (attrNames wans)` 推导监控列表，
五台主机和集成测试中的镜像声明已经删除；显式 `monitoring.wans` 覆盖能力以及
`monitoring.enable = false` 退出方式均保留。

建议：

- 默认启用 Home Router 监控。
- 默认令 `monitoring.wans = attrNames networking.homeRouter.wans`。
- 如果 Prometheus、Grafana 和探测器的资源成本需要兼容更小的未来设备，保留一个显式的
  `monitoring.enable = false` 退出方式。

这样 WAN 的增删只有一个事实来源，也避免新增 WAN 后遗漏监控。

## 3. WLT 适合作为默认能力

已验证事实：五台机器都启用
[`wlt.nix`](../../nixos/optional/home-router/wlt.nix)。WLT 同时涉及密钥、持久状态、Web/SSH
服务、nftables 映射，以及禁用 IPv6 时使用的路由表，属于完整的 Home Router 子系统。

建议：将 WLT 改为 `homeRouter` 默认能力，删除五处重复的 `wlt.enable = true`。由于它有
服务和状态成本，现阶段宜保留显式禁用能力；只有在确认“所有未来 Home Router 都必须运行
WLT”后，才值得完全移除开关。

WLT 的 `defaultOutlet` 应由共享出口选择实现提供，而不是继续由 WG-IPLC 等邻接模块交叉
设置。这样 WLT 只消费“默认出口”这一结果，不参与决定出口所有权。

## 4. Tailscale 需要 Home Router 适配层

已验证事实：[`tailscale-gnet.nix`](../../nixos/optional/tailscale-gnet.nix) 已统一 Tailscale
的基础运行参数和策略路由；五台 Home Router 又分别把 `tailscale0` 加入 dnsmasq，并发布
本地或站点路由。

适合进一步统一的是 Home Router 与 Tailscale 的连接逻辑，而不是把 Tailscale 本身塞进
Home Router 核心：

- Tailscale 启用时，dnsmasq 自动监听 `tailscale0`。
- Edge firewall 自动把 `tailscale0` 归类为可信内部入口。
- 默认发布非 guest LAN 的网段。
- 保留 `extraAdvertisedRoutes`，供 `el`、`el2` 发布额外站点和 connector 路由。
- 认证密钥、Headscale 地址和容器相关设置仍由主机拥有。

未决行为变化：`somo-nanopi-r4s` 目前只发布 IPv4 LAN，而
`somo-minisforum` 还发布对应的 IPv6 ULA。若自动从非 guest LAN 推导全部 IPv4/IPv6
前缀，NanoPi 会新增 IPv6 路由发布。实施前需要确认这一差异是遗漏还是有意限制。

## 5. Nylon 不应并入核心

已验证事实：五台机器都启用 Nylon 和它的策略路由，但出口模型不同：`cjia` 使用 PPP，
`el`、`el2` 有多个 WAN 出口，两台 SOMO 使用 CMCC 默认出口。

共同使用不等于共同 ownership。Nylon 也可用于非 Home Router 节点，并且出口标签和依赖
关系具有独立语义。建议保持 Nylon 为独立模块；如果仍想减少接线重复，可增加一个很薄的
Home Router–Nylon 适配层，从 WAN 数据推导接口和地址，但出口身份、标签仍显式配置。

## 不建议统一的配置

以下差异表达了真实拓扑或主机角色，不应为了减少行数而放进共同模块：

- OOB SSH：各机带外网络结构不同。
- Avahi：五台启用状态不一致。
- DNS 域名：分别属于 `cjia`、`el`、`el2`、`somo`、`somo2`。
- Wi-Fi、guest LAN 和 DNAT：只在部分主机存在，规则也依赖具体服务。

networkd 的 switch/VLAN/WAN 建模、策略路由、dnsmasq 基础配置、转发 sysctl、MSS clamp
和 WAN 计数器已经由 `home-router` 拥有，不需要再增加一层抽象。

## 推荐实施顺序

1. 让 Edge firewall 成为 `homeRouter` 的安全不变量，并删除各调用层的重复启用。
2. 自动推导监控 WAN，确认资源成本后决定是否默认启用监控。
3. 将 WLT 改为默认启用，并把默认出口来源收敛到共享出口实现。
4. 增加 Home Router–Tailscale 适配层；在确认 NanoPi 的 IPv6 行为后再自动发布 LAN 路由。
5. 仅在能明显减少实际接线时增加 Nylon 适配层，不改变其独立模块 ownership。

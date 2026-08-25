# Home Router 出口路由

本文定义 Home Router 对本机和转发流量的出口选择语义。具体 mark
编码由 [`policy-routing-marks.md`](policy-routing-marks.md) 负责，RPDB 阶段顺序由
[`policy-routing-priorities.md`](policy-routing-priorities.md) 负责，本机 OUTPUT 的
分类边界由 [`home-router-output-classification.md`](home-router-output-classification.md)
定义。

## 语义

Home Router 将 main 表视为自动选源流量的兜底路由：

- 带有出口 mark 的流量使用该 mark 对应的 WAN 路由表。
- 没有 mark、但显式绑定了本机 WAN 地址的流量使用该 WAN 的路由表。
- 其余流量使用真实的默认路由完成首次查询，再进入目的地址分类。
- `SO_BINDTODEVICE` 可以约束物理出口，但不能区分共享同一接口的多个逻辑 WAN。
- `SO_MARK` 仍可直接选择逻辑出口，并优先于绑定源地址。

`el` 和 `el2` 的 main 表以管理接口为首选默认出口，以 cernet 为更高 metric 的
备用默认出口。其他 Home Router 继续由各自主机拓扑决定 main 表默认出口；共享
防火墙不假设 main 表属于某个特定 WAN。

## 路由顺序

RPDB 保留以下职责边界：

```text
main 中的具体路由
  → fwmark 对应的出口表
  → 本机 WAN 源地址对应的出口表
  → main 中的真实默认路由
```

main 表的默认路由在前置 main 查询中被抑制，因此不会抢在 fwmark 和 WAN source
rule 之前返回。静态 WAN 地址生成 pref 300 的 `from ... lookup ...` 规则；fwmark
规则位于 pref 200，因此分类后的重路由不会被原源地址抢回。

对于 `el` 和 `el2`，默认路由为：

```text
management  较低 metric
cernet      较高 metric
```

普通连接首次选择 management。绑定 cernet、chinanet 或 cmcc 地址的 socket 则由
pref 300 source rule 选择对应的路由表；即使 chinanet 和 cmcc 共用一个接口，也能
通过不同源地址区分。

## 本机 OUTPUT 分类

本机分类的完整契约由
[`home-router-output-classification.md`](home-router-output-classification.md) 定义，包括
bind-source 边界、双栈 management 默认路由、分类链顺序、回复流量和 marked-WAN
SNAT；本文只负责 RPDB、出口表和 POSTROUTING 的整体关系。

## 转发流量

来自内部接口的转发流量始终在 PREROUTING 进入相同的目的地址分类，不使用 output
分类入口接口。guest LAN 等显式源路由策略继续由各自模块拥有，不属于 WAN 源地址选择
语义。

## POSTROUTING

出口路由和源地址转换是两个独立阶段：

- 带 mark 的静态 WAN 流量转换为该 WAN 的地址。
- 私有 IPv4 源地址从普通 WAN 或额外 masquerade 接口离开时执行 masquerade。
- wgIplc 流量按其出口 mark 执行 masquerade。
- 主机特有的 `masquerade.extraRules` 在上述规则之后按配置顺序执行。

在 `el` 和 `el2` 上，本机普通连接首次使用管理地址。目的地址分类选择公网 WAN 后，
带 mark 的 SNAT 规则将 IPv4 或 IPv6 管理地址转换为所选 WAN 地址；没有 mark 时则
继续使用管理默认出口。只承载宿主流量的管理接口不需要额外 masquerade。

## 故障行为

如果目的地址分类没有设置 mark，本机流量继续使用首次默认路由。对于 `el` 和 `el2`，
IPv4 和 IPv6 都因此继续通过管理网联网。

如果整个 nftables 配置没有加载，路由器本机仍可使用 management 的真实默认出口；
显式绑定的静态 WAN 地址也仍由 source rule 选择对应出口。转发流量不享有相同保证，
因为 nftables 同时提供 LAN masquerade；缺少 NAT 时，上游通常无法返回内部源地址。

管理网失效时，main 表可使用更高 metric 的 cernet 默认路由。该回退只负责基础路由，
不替代目的地址分类或 NAT 健康检查。

## 配置归属

- [`home-router/networkd.nix`](../nixos/optional/home-router/networkd.nix) 生成 WAN 表、
  fwmark/source RPDB 规则和带 metric 的静态默认路由。
- [`home-router/firewall.nix`](../nixos/optional/home-router/firewall.nix) 负责 OUTPUT、
  PREROUTING、conntrack mark 和 POSTROUTING。
- [`home-router/options.nix`](../nixos/optional/home-router/options.nix) 定义 OUTPUT 分类
  接口、目的地址集合规则和静态默认路由 metric。
- 主机配置决定 main 默认出口、metric 和额外 masquerade 接口。

WAN source rule 位于 fwmark 之后，只表达首次查询时的显式源地址选择，不覆盖已有出口
mark。非 Home Router 节点仍可独立使用通用 policy-routing 模块的源地址策略。

## 验收条件

- 无 mark 的 `el`、`el2` 本机 IPv4 和 IPv6 流量首先选择管理默认路由。
- 未绑定源地址的本机海外 IPv6 必须进入分类并被默认拒绝。
- 带 cernet、chinanet、cmcc 或 wgIplc mark 的流量选择对应出口。
- 显式绑定静态 WAN IPv4 或 IPv6 地址的流量跳过分类并选择该 WAN。
- Home Router 为静态 WAN 地址生成 pref 300 的 `from ... lookup ...` 规则。
- management 的 IPv4 和 IPv6 默认路由都必须真实可用；防火墙未加载时不能依赖假路由。
- Nylon 和 Tailscale UDP 传输流量不被重新分类。
- 内部转发流量仍按目的地址分类并在选定出口执行 NAT。
- 五台 Home Router 的配置均可求值，Home Router 集成测试通过。

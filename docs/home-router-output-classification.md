# Home Router 本机出口分类器

本文定义 Home Router 对本机流量执行出口分类的契约。RPDB 和路由表由
[`home-router/networkd.nix`](../nixos/optional/home-router/networkd.nix) 生成，nftables
规则由 [`home-router/firewall.nix`](../nixos/optional/home-router/firewall.nix) 生成。

## 目标语义

分类器只处理由内核自动选择源地址的本机连接。显式绑定已声明静态 WAN 地址的连接
直接使用该 WAN，不再根据目的地址分类。

- `bind(source address)` 选择逻辑 WAN，能够区分共用一个接口的多个 WAN。
- `SO_BINDTODEVICE` 只约束物理接口，是另一套语义。
- 已有 `SO_MARK` 或 conntrack mark 的连接保留已有出口决定。
- 只有配置在 `homeRouter.wans.<name>.addresses` 中、且具有专用路由表的静态地址享有
  bind-source 语义；DHCP、PPPoE 等运行时地址不在此契约内。

## 首次路由查询

RPDB 顺序是实现语义的一部分：

```text
pref 100  main 中的具体路由，抑制默认路由
pref 200  fwmark 对应的出口表
pref 300  from <static WAN address> lookup <WAN table>
最终       main 或主机声明的真实默认出口
```

pref 200 必须位于 pref 300 之前。首次查询时，显式绑定的 WAN 源地址命中 pref 300；
分类器设置 mark 后触发的第二次查询则先命中 pref 200，不会被原源地址抢回。

`networkd.nix` 必须为每个具有专用路由表的静态 WAN 地址生成精确 source rule：IPv4
使用 `/32`，IPv6 使用 `/128`。这些规则不是兼容代码，不能在 OUTPUT 重构时删除。

## 自动选源流量

`el` 和 `el2` 的 management 接口同时配置真实可用的 IPv4、IPv6 地址和 metric 100
默认路由；CERNET 默认路由以 metric 200 备用。

未绑定源地址时，pref 300 不匹配，首次默认路由选择 management。OUTPUT 只在首次
出口为 management 时跳转到分类链：

```text
main 默认路由选择 management
  → nft OUTPUT 按目的地址设置 mark
  → route hook 重新查路由
  → pref 200 使用 mark 对应的出口表
```

显式绑定 WAN 地址时，pref 300 已直接选择对应 WAN，首次出口不是 management，因而
跳过分类。

不能在 OUTPUT 阶段通过 `ip saddr` 区分显式绑定和自动选源：路由查询完成后，内核已经
为未绑定连接填入源地址。也不能将 OUTPUT 改成无条件分类，否则会破坏 bind-source
语义。

## 为什么 management 必须双栈

仅有 IPv4 management 默认路由时，未绑定 IPv6 会首次选择 CERNET。它与显式绑定
CERNET IPv6 的连接具有相同的源地址和出口接口，OUTPUT 无法再区分二者，海外 IPv6
会绕过默认拒绝。

management 因此必须拥有独立的静态 IPv6 地址和真实 IPv6 默认路由。不能用 dummy
interface、不可达网关或假默认路由代替：nftables 未加载时，本机仍必须保有基础网络。
routing realm 也不作为此判据；此前对相关内核重路由路径的检查表明，它不能可靠承载
这里所需的“首次自动选源”状态。

## 分类链顺序

`egress-classify` 按以下顺序处理，顺序不可随意交换：

1. 从非零 conntrack mark 恢复 packet mark 并返回。
2. 未记录出口的 established/related 回复流量返回。
3. 已有 packet mark 的流量返回。
4. 本机目的地址返回。
5. Nylon 和 Tailscale 的 UDP transport 源端口返回。
6. 执行主机声明的 `classification.extraRules`。
7. 按顺序匹配 `destinationAddressSetRules`，设置 packet/conntrack mark 并返回。
8. 私有目的地址返回。
9. 其余 IPv4 选择 `wg-iplc`。
10. 其余公网 IPv6：ICMPv6 返回，TCP reset，其他协议返回 no-route。

转发流量不经过 OUTPUT 判据。来自内部接口和声明的额外 ingress 接口的流量在
PREROUTING 无条件进入同一分类链；WLT 已设置的 mark 由步骤 3 保留。

## 回复流量

WAN PREROUTING 根据入站目的地址记录 conntrack mark。静态 WAN 地址产生的本机回复
通常已由 pref 300 选回原 WAN；需要重新选择出口的回复在分类链步骤 1 恢复 conntrack
mark。两条路径都必须保持入站与回复出口一致。

## 源地址转换

分类后的本机连接最初使用 management 地址。带静态 WAN mark 的流量必须在
POSTROUTING 无条件 SNAT 为该 WAN 地址，不能只匹配私有源地址；management IPv6 是
公网地址，但改走 CERNET 时仍必须转换为 CERNET IPv6，否则回包会在错误接口上进行
邻居发现。

显式绑定 WAN 地址的连接没有分类 mark，保持绑定地址，不触发上述 marked-WAN SNAT。
`wg-iplc` 继续按其 mark masquerade。

## 故障行为

- nftables 未加载：自动选源连接仍使用真实 management 默认路由；显式绑定静态 WAN
  地址仍由 pref 300 选择对应 WAN。
- policy-routing 服务未加载：main 默认路由仍可提供基础网络，但 bind-source 和 mark
  选出口语义不成立。
- management 失效：main 可回退到 metric 200 的 CERNET 默认路由；此时流量不会经过
  management OUTPUT 入口，出口分类策略不再保证，只保留基础连通性。

## 修改与验收

修改 OUTPUT、RPDB、默认路由或 SNAT 时，至少验证：

```text
ip rule：pref 200 fwmark 位于 pref 300 WAN source rule 之前
ip route get <public destination>：未指定 source 时首次走 management
ip route get <public destination> from <WAN address>：走对应 WAN table
nft egress-output：仅 oifname management 跳转到 egress-classify
```

集成测试还必须覆盖：显式绑定 CERNET IPv6 可以发出、未绑定海外 IPv6 被拒绝、分类后
IPv6 SNAT 为 CERNET 地址，以及 nftables 缺失时使用的 management 默认路由是真实路由。

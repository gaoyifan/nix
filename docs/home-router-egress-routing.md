# Home Router 出口路由

本文定义 Home Router 对本机和转发流量的出口选择语义。具体 mark
编码由 [`policy-routing-marks.md`](policy-routing-marks.md) 负责，RPDB 阶段顺序由
[`policy-routing-priorities.md`](policy-routing-priorities.md) 负责，本机 OUTPUT 的
分类边界由 [`home-router-output-classification.md`](home-router-output-classification.md)
定义。

## 语义

Home Router 将 main 表视为自动选源流量的兜底路由：

- 带有出口 mark 的流量使用该 mark 对应的 WAN 路由表。
- 没有 mark、但显式绑定了已声明静态 WAN 地址的流量使用该 WAN 的路由表；只有
  `wans.<name>.addresses` 中具有专用路由表的地址享有该语义，DHCP、PPPoE 等运行时
  地址不在此契约内。
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

## 方案演进与取舍

本节只保留会影响未来修改的设计取舍，不记录部署过程和一次性诊断细节。

### 源地址规则的两种角色

讨论最初混合了两类不同规则。nftables 的源地址规则在 OUTPUT 中执行 `return` 或设置
mark；RPDB source rule 则在路由查询时执行 `from <address> lookup <table>`。前者不能
证明源地址来自显式 bind，后者也只有放在正确的优先级上才能与目的地址分类共存。

重构前的 `el`/`el2` 只让管理地址跳过分类，并为 chinanet、cmcc 源地址设置对应 mark；
cernet 自动选源地址仍会继续按目的地址分类。重构时把它泛化成“所有 WAN 源地址均
`return`”，普通连接首次路由后自动取得 cernet 地址也会命中，于是 Diverge 的境外
DoH 没有获得 `wg-iplc` mark。该泛化不是旧行为的等价迁移，最终实现不再在 OUTPUT
通过 `ip saddr` 判断 bind-source。

把无 mark 限制的 WAN source rule 提到 fwmark rule 之前也不能解决问题。分类器设置
mark 后会触发第二次路由查询；如果 source rule 先运行，当前源地址会把连接抢回原 WAN。
最终顺序因此必须是 pref 200 fwmark rule 在前、pref 300 WAN source rule 在后。

### 直接识别显式 bind

内核以 `SOCK_BINDADDR_LOCK` 区分显式 `bind(source address)` 与自动选源，但现有
nftables socket 表达式不暴露该状态；`socket wildcard` 在自动选源完成后也无法区分
两者。扩展内核/nftables 可以提供直接判据，但会把本仓库的路由语义依赖到自定义内核
接口，讨论中没有采用。

另一条思路是要求调用方使用 `SO_MARK`、`SO_BINDTODEVICE` 或 cgroup 明确选择出口。
这能避免推断 bind 状态，其中 `SO_MARK` 可以选择逻辑 WAN；但
`SO_BINDTODEVICE` 只能约束物理接口，无法区分共用同一接口的 chinanet 与 cmcc。
讨论中曾一度接受“放弃 bind-source”以换取简单实现，后来确认这破坏了既有的静态 WAN
地址选择语义，因此没有成为最终契约。

### `fwmark 0` 与 route realm

曾尝试让 source rule 只匹配 `fwmark 0/0xffffffff`，再通过 route realm/
`rt classid` 把首次路由结果传给 nftables。realm 本身并非完全无效：单次路由查询的
ping 或部分 UDP 路径可以携带并匹配该值。问题在于 TCP `connect()` 和连接式 UDP
可能先自动选源，再以非零源地址、零 mark 查询一次；第二次查询与显式 bind 具有相同
输入，仍会命中 source rule。前置 main 具体路由也可能在 realm 规则之前结束查询。

因此该方案只能覆盖部分路径，不能作为本机连接的统一判据。后续针对 route hook
重路由的检查也未证明 realm 能可靠保存所需状态，最终实现没有使用 `fwmark 0` 或 realm
区分自动选源。

### 为自动选源提供独立身份

中性 loopback 地址方案把一个仅配置在 `lo` 的地址设为 main 默认路由的 preferred
source。隔离实验确认：该地址不必配置在 cernet 接口上，报文仍可从 cernet 发出；经过
SNAT 后 TCP 能正常往返。完全没有 nftables/NAT 时，报文也能发出，但上游通常无法回程
该中性地址。该方案还会改变 `getsockname()` 所见地址，并为 IPv6 引入 NAT66 问题，
因此未采用。

随后验证了“第二个真实 CERNET IPv4 地址”方案：一个地址保留给显式 bind，另一个合法
地址专供 main 自动选源。隔离实验中即使没有 nftables 和 NAT 也能完成 TCP 往返；代价
是额外上游地址，以及长期维护“显式地址/自动地址”、保护集合和跨 WAN SNAT 三组语义。
该候选因复杂度被放弃。

讨论还回顾过用 dummy 接口、不可达网关或假默认路由作为分类入口。dummy 设备在实验
中也用于构造测试拓扑，但没有成为生产实现。此类默认路径在 nftables 未加载时不提供
真实连通性，会把分类器故障扩大成本机基础网络故障，因此被排除。

这里的“第二个真实 CERNET IPv4 地址”候选不能与最终 management IPv6 混为一谈。
前者计划在 WAN 身份内部区分两类源地址；后者是在独立 management 接口上配置真实全局
IPv6 地址和默认路由，使自动选源 IPv6 与原 CERNET WAN 地址产生不同的首次路由结果。

### management 默认路由的两次迭代

management 首先以 IPv4 真实默认路由落地：main 优先选择低 metric 的 management，
cernet 保留较高 metric 的备用路由；只有首次输出接口是 management 的本机流量进入
目的地址分类。它相比中性地址和 dummy 的关键优势是，nftables 未加载时路由器本机仍有
真实、可回程的默认路径。

第一版同时采用了当时的“放弃 bind-source”结论，删除了 Home Router 的 WAN source
rules，而且 management 只有 IPv4。部署后，默认双栈请求的 IPv6 首次选择 cernet，
从而绕过只匹配 management 的 OUTPUT 分类。运行时把所有 OUTPUT 无条件送入分类链能
立即拒绝海外 IPv6并让请求回退 IPv4，但显式 bind WAN 地址的新连接也会被重分类；该
规则只用作诊断热修复。共享模块仍允许不需要 `el`/`el2` bind-source 判别的其他主机
选择无条件 OUTPUT，否决的是在 `el`/`el2` 上使用它。

随后重新核对历史和需求，确认删除 WAN source rules 是回归。最终恢复静态 WAN IPv4
`/32`、IPv6 `/128` 的 pref 300 source rules，但没有恢复旧的 management 专用 source
rule 或 management 路由表；management 继续由 main 默认路由负责。这样显式 bind 静态
WAN 地址的首次查询直接进入对应 WAN 表，自动选源连接才会首次走 management。

为补齐 IPv6，同一上游 CERNET `/64` 中的另一个真实全局 IPv6 地址被配置在 management
接口上，并配套真实的 metric 100 默认路由；原 CERNET IPv6 地址和 metric 200 默认路由
保留在 WAN 接口。这一地址确实也是“另一个真实 CERNET 地址”，但它属于最终双栈
management 方案，不是前述被放弃的双 CERNET IPv4 自动选源方案。

### marked-WAN SNAT

路由判别正确还不够。自动选源连接最初携带 management 地址，分类并改走静态 WAN 后，
必须把源地址转换成该 WAN 的地址。重构前 `el` 的 IPv4 规则已经按输出接口和 mark
转换任意源地址；统一重构后的 marked-WAN SNAT 一度改成只匹配私有源地址。这对私有
management IPv4 有效，却不匹配真实的全局 management IPv6，可能使回包在错误接口上
进行邻居发现。最终方案恢复了旧 IPv4 规则不限制原源地址的性质，并将它扩展到 IPv6。

最终规则以输出接口和静态 WAN mark 为条件，对 IPv4、IPv6 都执行对应 WAN 地址的
SNAT，不再要求原源地址属于私网。未预设出口 mark 的显式 bind WAN 连接通过 pref 300
直接选择 WAN，因而保持绑定地址；如果 socket 同时设置 `SO_MARK`，pref 200 mark rule
优先，并可能触发目标 WAN 的 SNAT。`wg-iplc` 继续按自己的 mark 单独 masquerade。

### 最终组合

最终设计不是单一规则，而是以下条件共同成立：

- 只有声明了专用路由表的静态 WAN 地址生成精确 source rule。
- pref 200 fwmark rule 先于 pref 300 WAN source rule。
- `el`/`el2` 的 management 提供真实可用的 IPv4、IPv6 地址和默认路由，cernet 只作
  较高 metric 的基础回退。
- `el`/`el2` 的 OUTPUT 只分类首次路由到 management 的流量；其他主机可按自身拓扑
  选择无条件分类。
- 目的地址分类前先从非零 conntrack mark 恢复 packet mark，并保留已有 packet mark；
  已作出的出口决定不能被后续目的地址规则覆盖。
- 分类同时保存 packet mark 和 conntrack mark，第二次查询由 fwmark 选择最终出口。
- 带静态 WAN mark 并从该 WAN 离开的 IPv4、IPv6 流量执行对应地址的 SNAT。
- 修改默认路由身份时必须检查并清理旧路由，否则旧的低 metric 路由会破坏首次出口
  判据。

缺少其中任一项，都会分别破坏 bind-source、分类后的重路由、IPv6 自动选源、回复路径
一致性、源地址归属或热切换后的实际数据路径。

## 本机 OUTPUT 分类

本机分类的完整契约由
[`home-router-output-classification.md`](home-router-output-classification.md) 定义，包括
bind-source 边界、双栈 management 默认路由、分类链顺序、回复流量和 marked-WAN
SNAT；本文只负责 RPDB、出口表和 POSTROUTING 的整体关系。

## 转发流量

来自内部接口和 `classification.extraIngressInterfaces` 的转发流量在 PREROUTING
进入相同的目的地址分类，不使用 output 分类入口接口。guest LAN 等显式源路由策略
继续由各自模块拥有，不属于 WAN 源地址选择语义。

## POSTROUTING

出口路由和源地址转换是两个独立阶段：

- 带 mark 的静态 WAN 流量转换为该 WAN 的地址。
- 私有 IPv4 或 IPv6 源地址从普通 WAN 或额外 masquerade 接口离开时执行
  masquerade。
- wgIplc 流量按其出口 mark 执行 masquerade。
- 主机特有的 `masquerade.extraRules` 在上述规则之后按配置顺序执行。

在 `el` 和 `el2` 上，本机普通连接首次使用管理地址。目的地址分类选择公网 WAN 后，
带 mark 的 SNAT 规则将 IPv4 或 IPv6 管理地址转换为所选 WAN 地址；没有 mark 时则
继续使用管理默认出口。本机自动选源流量不需要为 management 额外 masquerade；如果
转发的私有源地址也可能从 management 离开，由主机通过 `masquerade.extraInterfaces`
声明该需求。

## 故障行为

如果进入目的地址分类的本机流量没有设置 mark，它继续使用首次默认路由。对于 `el` 和
`el2`，IPv4 和 IPv6 都因此继续通过管理网联网。

如果整个 nftables 配置没有加载，路由器本机仍可使用 management 的真实默认出口；
显式绑定的静态 WAN 地址也仍由 source rule 选择对应出口。转发流量不享有相同保证，
因为 nftables 同时提供 LAN masquerade；缺少 NAT 时，上游通常无法返回内部源地址。

management 默认路由被内核移除或判定不可用时，main 表可使用更高 metric 的 cernet
默认路由。metric 本身不探测网关或上游健康状态；该回退只负责基础路由，不替代目的
地址分类、NAT 或健康检查。

## 热切换与旧路由

修改默认路由的 metric、table、gateway 等路由身份后，热切换可能同时留下旧、新两条
静态默认路由。Home Router 设置 `ManageForeignRoutes=false`，以免 networkd 删除
Tailscale、Nylon 等其他组件管理的路由；networkd 重启后也因此可能无法认领并清理旧
路由。旧的低 metric 路由会绕过 management OUTPUT 分类入口，使声明式配置与实际
数据路径不一致。

涉及路由身份变化的部署必须在切换后检查 IPv4、IPv6 main 表的默认路由，确认不存在
未声明的旧路由。该检查是迁移要求，不属于正常稳态的出口选择语义。

```bash
ip -4 route show table main default
ip -6 route show table main default
```

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

- 未显式绑定源地址且无 mark 的 `el`、`el2` 本机 IPv4 和 IPv6 流量首先选择管理默认
  路由。
- 未绑定源地址的本机海外 IPv6 必须进入分类并被默认拒绝。
- 带 cernet、chinanet、cmcc 或 wgIplc mark 的流量选择对应出口。
- 显式绑定静态 WAN IPv4 或 IPv6 地址的流量跳过分类并选择该 WAN。
- Home Router 为静态 WAN 地址生成 pref 300 的 `from ... lookup ...` 规则。
- management 的 IPv4 和 IPv6 默认路由都必须真实可用；防火墙未加载时不能依赖假路由。
- 修改静态默认路由身份后，main 表中不得残留未声明或更低 metric 的旧默认路由。
- Nylon 和 Tailscale UDP 传输流量不被重新分类。
- 内部接口和声明的额外 ingress 接口仍按目的地址分类，并在选定出口执行 NAT。
- 五台 Home Router 的配置均可求值，Home Router 集成测试通过。

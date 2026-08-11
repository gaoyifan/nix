# Tailscale DERP 与独立 STUN 的耦合和 DERPMap 建模

> 调查日期：2026-08-11。结论对照 Tailscale 官方文档和调查时
> `tailscale/tailscale` `main` (`d2c5166298f5fd25773b729227d93f5a5f098ee3`)；源码链接固定到该 commit。

## 结论

`derper` 的内置 STUN 与 DERP relay **没有协议或运行时状态耦合**。可以让
`derper --stun=false` 只提供 relay，再用一个或多个按具体地址绑定的官方 `stund`
提供 STUN。`derper` 和 `stund` 都直接创建同一个 `net/stunserver` 实现；后者只从 UDP
请求中读取客户端地址并返回 STUN response，不访问 DERP server、密钥、mesh 或客户端
认证状态
([`derper` 开关与启动逻辑](https://github.com/tailscale/tailscale/blob/d2c5166298f5fd25773b729227d93f5a5f098ee3/cmd/derper/derper.go#L56-L71),
[`derper` 创建 STUN server](https://github.com/tailscale/tailscale/blob/d2c5166298f5fd25773b729227d93f5a5f098ee3/cmd/derper/derper.go#L178-L186),
[`stund`](https://github.com/tailscale/tailscale/blob/d2c5166298f5fd25773b729227d93f5a5f098ee3/cmd/stund/stund.go#L4-L40),
[`stunserver`](https://github.com/tailscale/tailscale/blob/d2c5166298f5fd25773b729227d93f5a5f098ee3/net/stunserver/stunserver.go#L34-L113))。

进程拆分不等于 DERPMap 节点也必须拆分：

- 如果 standalone `stund` 仍在 relay 对外公布的同一个 IP、同一个 STUN 端口上，**继续使用
  一个普通 `DERPNode` 最简单也最准确**。不要把 `STUNPort` 设为 `-1`；map 应继续告诉
  客户端该逻辑节点的 STUN 在 `IP:3478`，客户端不知道响应它的是 `derper` 还是另一个进程。
- 只有 standalone STUN 使用不同 IP/hostname，或者确实要禁止探测 relay 的地址时，才需要
  把 relay 设为 `STUNPort: -1`，并在**同一个 region** 增加 `STUNOnly: true` 节点。
- 不要创建只有 STUNOnly 节点的独立 region。当前 netcheck 会把它的 STUN RTT 当作该 region
  的 DERP latency，甚至可将其选为 home DERP；实际 DERP 拨号随后却找不到 relay。

STUN 与 relay 在源码层面不要求同一进程。拆成两个逻辑节点后，也不要求同一 IP 或 hostname；
但 STUN RTT 被用来代表整个 region 的 relay RTT，所以两个端点的网络路径应足够接近。这是由
客户端选择算法得出的运行要求，而不是服务端协议约束。

## DERPMap 字段的精确语义

官方 `DERPNode` 定义说明：

- `HostName` 必填但不要求唯一；显式 `IPv4`/`IPv6` 可以覆盖 DNS；
- `STUNPort = 0` 表示默认 UDP 3478；`-1` 表示不在该 node 上探测 STUN；
- `STUNOnly = true` 表示该 node 只有 STUN、不能作为 DERP relay；
- `DERPPort` 是独立的 relay TLS 端口，`0` 表示 443。

来源：[`tailcfg.DERPNode`](https://github.com/tailscale/tailscale/blob/d2c5166298f5fd25773b729227d93f5a5f098ee3/tailcfg/derpmap.go#L143-L208)。
官方 custom DERP 文档也把 HTTPS 与 STUN 端口作为两个独立端口，并分别指向
`DERPPort` 与 `STUNPort`
([required ports](https://tailscale.com/docs/reference/derp-servers/custom-derp-servers#required-ports))。

`derper --stun=false` 不会向 control plane 或 DERPMap 自动发布任何状态。因此，
`STUNPort: -1` 描述的是“客户端不要查询这个逻辑 node 的 STUN”，不是“提供 relay 的那个
OS 进程没有内置 STUN”。这正是同地址 standalone `stund` 应保留普通 node `STUNPort`
的原因。

## 两种正确建模方式

### 1. STUN 和 relay 对外地址相同

服务进程可以是：

```text
derper --stun=false -a :10000
stund --stun 202.141.162.72:3478
```

DERPMap 仍只需要一个 node：

```json
{
  "Name": "hfe0",
  "RegionID": 900,
  "HostName": "el2-chinanet.gaof.net",
  "IPv4": "202.141.162.72",
  "DERPPort": 10000,
  "STUNPort": 3478
}
```

如果同一 wildcard relay 在多个公网地址上可达，并希望按各 WAN 的路径分别度量和选择，
可以为各地址建立各自的 region/node；每个逻辑 node 仍同时描述该地址上的 DERPPort 与
外置 STUNPort。`HostName` 可以复用，也可以用 `CertName` 把拨号名称与证书名分开；字段模型
明确允许 hostname 不唯一
([字段定义](https://github.com/tailscale/tailscale/blob/d2c5166298f5fd25773b729227d93f5a5f098ee3/tailcfg/derpmap.go#L155-L185))。

这种模型避免引入同 region 多 node 的 probe 顺序问题，也确保 STUN RTT 恰好量到 relay
所公布的地址路径。

### 2. STUN 和 relay 使用不同地址

此时可在同一 region 中明确分开：

```json
{
  "RegionID": 900,
  "Nodes": [
    {
      "Name": "hfe0-stun",
      "RegionID": 900,
      "HostName": "stun-hfe0.example.net",
      "IPv4": "203.0.113.20",
      "IPv6": "2001:db8::20",
      "STUNPort": 3478,
      "STUNOnly": true
    },
    {
      "Name": "hfe0-relay",
      "RegionID": 900,
      "HostName": "derp-hfe0.example.net",
      "IPv4": "203.0.113.21",
      "IPv6": "2001:db8::21",
      "DERPPort": 10000,
      "STUNPort": -1
    }
  ]
}
```

对当前客户端，**STUNOnly node 应放在 Nodes 首位**。probe planner 通过
`reg.Nodes[try % len(reg.Nodes)]` 轮询节点；增量 netcheck 对非最快、非 home 的 region
默认只有一次 `try`。如果首个 node 是 `STUNPort: -1` 的 relay，这一轮会生成一个随后被
`nodeAddrPort` 拒绝的 probe，可能完全没有向真正的 STUNOnly node 发包
([增量 probe 计划](https://github.com/tailscale/tailscale/blob/d2c5166298f5fd25773b729227d93f5a5f098ee3/net/netcheck/netcheck.go#L455-L556),
[初始 probe 轮询](https://github.com/tailscale/tailscale/blob/d2c5166298f5fd25773b729227d93f5a5f098ee3/net/netcheck/netcheck.go#L559-L575),
[`STUNPort < 0` 的处理](https://github.com/tailscale/tailscale/blob/d2c5166298f5fd25773b729227d93f5a5f098ee3/net/netcheck/netcheck.go#L1592-L1601),
[`nodeAddrPort`](https://github.com/tailscale/tailscale/blob/d2c5166298f5fd25773b729227d93f5a5f098ee3/net/netcheck/netcheck.go#L1647-L1661))。

把 STUNOnly 放首位不会影响 relay 拨号：DERP client 会顺序跳过所有 `STUNOnly` node，
再拨普通 node
([`dialRegion`](https://github.com/tailscale/tailscale/blob/d2c5166298f5fd25773b729227d93f5a5f098ee3/derp/derphttp/derphttp_client.go#L633-L656))。

## netcheck 与 home DERP 选择

客户端没有把 STUN 与某个 DERP TCP 连接做服务端身份关联：

1. probe 根据 node 的 `IPv4`/`IPv6`、`STUNPort` 直接发送 UDP；收到 response 后，把 RTT
   写入 `RegionLatency[node.RegionID]`
   ([probe response](https://github.com/tailscale/tailscale/blob/d2c5166298f5fd25773b729227d93f5a5f098ee3/net/netcheck/netcheck.go#L1597-L1612),
   [region latency aggregation](https://github.com/tailscale/tailscale/blob/d2c5166298f5fd25773b729227d93f5a5f098ee3/net/netcheck/netcheck.go#L683-L705))。
2. home DERP 选择遍历当前 report 的 `RegionLatency`，从近期最低 RTT 的 region 中选
   `PreferredDERP`；这段选择没有检查 region 是否存在非-STUNOnly node
   ([selection](https://github.com/tailscale/tailscale/blob/d2c5166298f5fd25773b729227d93f5a5f098ee3/net/netcheck/netcheck.go#L1413-L1464))。
3. magicsock 将该 region 设为 home 并启动 DERP 连接；实际拨号时才跳过 STUNOnly node
   ([home selection handoff](https://github.com/tailscale/tailscale/blob/d2c5166298f5fd25773b729227d93f5a5f098ee3/wgengine/magicsock/derp.go#L197-L213),
   [connect start](https://github.com/tailscale/tailscale/blob/d2c5166298f5fd25773b729227d93f5a5f098ee3/wgengine/magicsock/derp.go#L251-L295))。

上游单测也直接构造了“每个 region 只有一个 `STUNOnly` node”的 map，并断言一次 STUN
response 会得到 `RegionLatency[1]` 和 `PreferredDERP = 1`
([map fixture](https://github.com/tailscale/tailscale/blob/d2c5166298f5fd25773b729227d93f5a5f098ee3/net/stun/stuntest/stuntest.go#L95-L137),
[assertion](https://github.com/tailscale/tailscale/blob/d2c5166298f5fd25773b729227d93f5a5f098ee3/net/netcheck/netcheck_test.go#L39-L72))。
这证明 STUNOnly-only region 不是一个安全的 standalone-STUN 建模方式：它可用于 netcheck
测试，但没有可连接的 relay。

由于 `RegionLatency` 来自 STUN endpoint，而官方文档说明客户端正是根据 latency 信息选择
home DERP
([DERP server locations and selection](https://tailscale.com/docs/reference/derp-servers#derp-server-locations))，
将不同网络路径的 STUN 与 relay 放入同一个 region 会让客户端用前者错误代表后者。
“同一网络位置/路径”是准确选择的要求；“同一 IP、hostname 或进程”不是协议要求。

## 对 el2 方案的直接含义

将 wildcard `derper -a :10000 --stun=false` 与四个按地址绑定的 `stund :3478` 配合是可行的。
如果 DERPMap 仍把 Chinanet、CMCC、CERNET 和 IPv6 地址分别表示为各自的逻辑 DERP
region/node，那么各 node 应继续公布对应地址的 `STUNPort: 3478`；无需额外创建
`STUNOnly` node，也不应因为 `derper` 关闭内置 STUN而设置 `STUNPort: -1`。

这样既固定每个 UDP socket 的出站地址，又让每条 STUN 测量与同一个地址上的 wildcard
relay 路径对应。只有 DERPMap 中的 STUN endpoint 与 relay endpoint 确实不同，才应用
上面的双-node 建模，并把 STUNOnly node 排在首位。

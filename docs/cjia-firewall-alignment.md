# cjia 防火墙与 el/el2 对齐方案

本文记录 cjia 防火墙与 el/el2 对齐时已经确认的设计决策，供后续实现参考。

## 目标

cjia 不复刻原 Armbian 防火墙，而是采用与 el/el2 共享的 `edge-filter`
default-deny 结构。三台主机应尽量共享 input/forward 过滤逻辑，同时分别保留与实际
拓扑有关的出口分类、NAT、DNAT 和服务端口。

## 已确认的信任边界

cjia 的可信接口为：

- LAN：`br-core.651`
- `tailscale0`
- `nylon0`
- loopback 单独放行

cjia 的非可信接口为：

- PPPoE 公网接口 `ppp0`
- 管理接口 `end0`（`192.168.125.254/24`）
- 海外出口 `wg-iplc`
- 其他未明确列入可信集合的接口

已经确认的访问语义：

- `end0` 比照 el 的管理接口处理，只能访问 ICMP 和公开端口，不能向其他网络转发。
- `nylon0` 比照 el 作为可信接口，允许 Nylon 节点主动访问 cjia LAN。
- `wg-iplc` 只作为出口，不允许对端访问全部本机服务或主动转发到 LAN。
- el 和 el2 的 `wg-iplc` 也应统一视为非可信接口。

## cjia input 链

将当前 `policy accept` 加 `ppp0` 特判的结构改为 default-deny：

```nft
chain input {
  type filter hook input priority filter; policy drop;
  ct state established,related accept
  iifname "lo" accept
  ip protocol icmp accept
  meta l4proto ipv6-icmp accept

  iifname { "br-core.651", "tailscale0", "nylon0" } accept
  tcp dport { 22, 5201 } accept
  udp dport { 5201, 6622, 6627, 61001-61999 } accept
}
```

公开端口规则对所有非可信接口生效，因此管理网和 `wg-iplc` 对端仍可使用 SSH、
iperf3、Nylon、Tailscale 和 tsshd 的公开端口，但不能访问 Homebridge、dnsmasq、
Grafana 等内部服务。

cjia 应启用 fail2ban，与 el 的公网 SSH 防护保持一致。现有 Grafana 3001 独立限制
规则继续保留，仅允许 LAN、loopback 和 Tailscale 访问。

## cjia forward 链

使用与 el 相同的 default-deny 骨架：

```nft
chain forward {
  type filter hook forward priority filter; policy drop;
  ct state established,related accept
  iifname { "br-core.651", "tailscale0", "nylon0" } accept
}
```

这允许 LAN、Tailscale 和 Nylon 主动访问其他网络，同时禁止 `ppp0`、`end0` 和
`wg-iplc` 主动转发到 LAN 或其他网络。当前针对 `ppp0`、`wg-iplc`、`nylon0` 到 LAN
的两条特殊规则应删除，因为 default-deny 已覆盖这些情况。

cjia 当前没有 DNAT，不加入无实际作用的 `ct status dnat accept`。以后增加真实 DNAT
规则时再配套放行。

## el 与 el2

重构前，el 通过以下配置额外信任 `wg-iplc`：

```nix
trustedInterfaces = ["wg-iplc"];
```

该配置已删除。`wg-iplc` 仍能访问 el 声明的公开端口，但不能访问全部本机服务或
主动转发。

el2 当前没有把 `wg-iplc` 加入可信接口；其 `extraTrustedInterfaces = ["wg0"]` 是另一条
独立的信任关系，本次不删除。

## 保持主机差异的规则

以下规则不属于通用 input/forward 过滤，不应为了形式一致而复制：

- cjia 保留 PPPoE NAT、`wg-iplc` masquerade、Nylon NAT 和 cjia 自己的出口分类。
- cjia 的 USTC 流量继续使用 mark `0x200` 进入 el2 的 CERNET Nylon 出口；不恢复 `wg-el`。
- el/el2 保留各自的 CERNET、China Telecom、China Mobile 固定 SNAT 和多 WAN 分类。
- cjia 不复制 el 的 UDP 2197 DNAT、light-server 端口或服务端口范围。
- WLT、Nylon MSS/exit 和 homeRouter MSS 等共享规则继续由原模块生成。
- Tailscale 继续使用 `--netfilter-mode=off`，其访问控制由上述 nftables 规则负责。

## 代码结构

`nixos/optional/edge-firewall.nix` 只负责 input/forward，并提供共享的运维基线：

- 信任已启用的 Tailscale 和 Nylon 接口
- 信任已启用 homeRouter 的所有内部接口
- 开放已启用的 OpenSSH、Tailscale 和 Nylon 端口
- 开放 TCP/UDP 5201 和 UDP 61001–61999
- 从网络配置和 homeRouter LAN 自动生成 DHCP 客户端与服务器规则

主机通过 `extraTrustedInterfaces`、`extraPublicTcpPorts`、`extraPublicUdpPorts` 及确有
需要的 `extraInputRules`/`extraForwardRules` 扩展该基线。

el、el2 和 cjia 共用该模块；`el-router.nix` 继续负责 el 和 el2 的 GNet 多 WAN 出口
分类、SNAT 和 Nylon exits。不要把 cjia 的 PPPoE 或 USTC/Nylon 分类塞入通用防火墙
模块。

实施后应检查三台主机生成的完整 nftables ruleset，并至少验证：

- 非可信接口无法访问未公开的本机端口。
- 管理网不能经路由器转发到 LAN。
- Nylon 可以主动访问 cjia LAN。
- `wg-iplc` 不能主动访问三台主机的内部网络。
- 三台主机的公开服务端口仍可用。
- cjia 的 USTC、国内、海外出口选择没有被过滤规则改变。

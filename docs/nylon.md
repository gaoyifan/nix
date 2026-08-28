# Nylon 声明与运维参考

Nylon 的唯一声明源位于本仓库。不要在其他仓库维护成员列表、central config、出口目录、
WLT 路由或 `ny.gaof.net` 的 A/AAAA desired state。

## 所有权边界

- [`nixos/nylon/mesh.nix`](../nixos/nylon/mesh.nix) 定义全网默认值、保留的 numeric ID、
  DNS 控制面和 fleet 不变量。
- [`nixos/nylon/nodes/default.nix`](../nixos/nylon/nodes/default.nix) 枚举成员；同目录逐机文件
  定义公开 identity、underlay、出口和 selector 角色。
- [`nixos/nylon/compile.nix`](../nixos/nylon/compile.nix) 是纯 compiler，派生 central、逐机
  public node config、出口 datapath、WLT/RPDB projection、DNS snapshot 和 manifest；公开
  manifest 由 `self.lib.nylonManifest` 暴露。
- [`nixos/nylon/fleet.nix`](../nixos/nylon/fleet.nix) 把逐机 projection 接入 NixOS 与 agenix，
  并仅在 DNS controller 上提供手动 PowerDNS plan/apply units。
- [`nixos/nylon/module.nix`](../nixos/nylon/module.nix) 负责 runtime secret assembly、服务、
  MPLS/tc/nftables、WARP 和 selector reconciliation。

成员私钥、WARP 私钥和 PowerDNS API key 的 recipient rules 位于 secrets submodule 的
`secrets.nix`；密文由逐机 `age.secrets` 消费。私钥不得进入 topology、Nix store、命令行或
日志。

## 修改与部署

修改 topology 后先运行：

```sh
nix eval --json .#lib.nylonManifest.value.counts
nix build \
  .#checks.x86_64-linux.nylon-topology \
  .#checks.x86_64-linux.nylon-runtime-module \
  .#checks.x86_64-linux.nylon-config-parser \
  .#checks.x86_64-linux.nylon-wlt-parser \
  .#checks.x86_64-linux.nylon-health-runner \
  --no-link
nix build \
  '.?submodules=1#checks.x86_64-linux.nylon-production-secrets' \
  --no-link
```

从 topology 输出读取成员数、出口数、selector 数和 central hash，不在长期文档中复制这些
易变值。部署使用：

```sh
just sync-and-rebuild <host>
```

该命令在目标就是本机时自动执行本地 switch。成员删除或 identity/graph 变化必须使用
expand/contract：先让接收方兼容新旧状态，再移除 selector datapath，最后停止旧成员；
不能把局部 `--limit` 结果当作全网 central config。

## PowerDNS

DNS controller 的 Nix generation 提供 desired snapshot，但不会自动写 PowerDNS。先生成并
审核 plan：

```sh
sudo systemctl start nylon-powerdns-plan
sudo jq . /var/lib/nylon-powerdns/plan.json
```

只有 `changes` 精确符合已批准的 topology diff 时才应用：

```sh
sudo systemctl start nylon-powerdns-apply
```

apply 会重新检查 preimage，并在写入后读取 zone 验证 desired digest。随后再次运行 plan；
`changes` 必须为空，且 `preimage_digest` 与 `desired_digest` 必须相同。

## 运行时验收

在 Linux 控制机从同一 public manifest 运行有界 fleet 检查；若控制机本身是 manifest
成员，该成员会按仓库规则在本地通过 `sudo` 检查，不会 SSH 回自己：

```sh
nylon_manifest=$(mktemp)
trap 'rm -f "$nylon_manifest"' EXIT
nix eval --raw .#lib.nylonManifest.text > "$nylon_manifest"
nix run .#nylon-health -- validate-manifest "$nylon_manifest"
nix run .#nylon-health -- check "$nylon_manifest"
```

`check` 只读取 central digest、runtime identity/neighbours/routes、最近的 dispatch 日志，并做
overlay 双栈探测；它不部署配置、不写远端状态，也不替代出口 SNAT/WARP 的针对性验收。

逐机至少检查：

```sh
sha256sum /etc/nylon/central.yaml /run/nylon/central.yaml
nylon verify /etc/nylon/central.yaml --node /run/nylon/node.yaml
systemctl is-active nylon nylon-routes
```

有出口的节点还需检查 `nylon-exit`；WARP 节点检查 `nylon-warp-reconfigure` 和
`wg-cloudflare`；selector 检查 `policy-routing`、`wlt`、priority 200 rules 及 compiler-owned
routing tables。删除成员后同时证明其 WLT outlet、mark、table、MPLS selector 和 DNS
A/AAAA 均不存在。

PowerDNS API key 的轮换是独立维护任务；不要把 topology 变更与 credential rotation 合并。

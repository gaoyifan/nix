# Nylon 迁移后审查修复计划

> 状态：已完成
>
> 日期：2026-08-28
>
> 完成日期：2026-08-28
>
> 来源：对 Nix、secrets submodule 和 `server-maintenance` 未提交迁移差异的并行
> Standards/Spec review，以及主审查对 findings 的复核。

本工作单修复 Nylon Nix 原生迁移中已证实的契约和可维护性缺口。当前 15 节点生产 mesh
健康，本次只修改并验证仓库，不重新部署全网，也不重新运行已完成的远端 fleet regression。

## 目标

- 让 topology 输入真正封闭，错误字段和畸形 IP 在 evaluation 阶段失败；
- 保证 Nix activation 不会因 `RESTART_REQUIRED` 留下声明与 daemon 运行态分裂；
- 恢复无 private secrets submodule 的公共/CI evaluation；
- 让公共端口、manifest 和 secret inventory 各有一个明确权威来源；
- 用轻量、manifest-driven 的检查替代已删除 maintenance regression 的核心能力；
- 修正 package layout、历史记录和长期文档中的失效入口；
- 保持 PowerDNS adapter 只拥有 A/AAAA，不因无关 zone 变化增加错误冲突。

## 已批准修复

### P0：正确性与 CI

1. `centralStore` 变化在 Nix activation 中触发逐机 restart，不为 reload fallback 创建新的
   orchestration layer；手工 reload 仍可用于 daemon 明确接受的 central 变化。
2. compiler 使用 pinned nixpkgs 已有的 IPv6 parser，不自行实现完整 IPv6 grammar；IPv4
   继续使用现有严格 octet 检查。
3. node、selector、underlay、exit、presentation、WARP 输入全部使用 closed schema；未知
   字段、任何层级的 secret-like 字段和 caller-authored projection 字段必须 evaluation
   失败。
4. `nylon-runtime-module` check 改为使用仓库内 fixture，不依赖 production
   `services.secrets.hasRealFiles`；带和不带 `?submodules=1` 都必须能 evaluation。

### P1：契约、检查与运维

1. `services.nylon.udpPort` 从 compiled public node 派生，不再复制 mesh 默认端口。
2. 增加低成本离线检查：generated central/public node 的 `nylon verify` fixture，以及 WLT
   TOML parse。复杂 kernel datapath 不塞入这一检查。
3. 在 flake integration 层增加 production-only secret inventory check：有 private
   submodule 时验证成员、WARP 和 PowerDNS ciphertext/recipient rule；pure compiler 不读取
   secret registry，public fallback 不伪造 ciphertext。
4. 将现有 public manifest 作为稳定 flake output 暴露；不把 rollout wave、closure、线上
   generation 或 rollback generation 塞进纯 compiler。
5. 在 Nix 仓库提供一个小型 manifest-driven health runner，只覆盖 central digest/member、
   neighbour、overlay 双栈和明显 dispatch/unreachable 故障；不迁移 RTT comparison、pprof
   或通用部署框架。
6. 自定义 PowerDNS package 使用 `pkgs/<name>.nix` 入口，源码和 tests 仍放子目录。
7. 恢复 maintenance log 对旧 playbook、inventory 和明文 secret path 的真实历史描述；
   更新长期 policy-routing 文档，不再指向已删除 playbook。

### P2：有界清理

- 删除 runtime projection 中未消费的 `binds`、`underlays`、selector catalog 等字段；保留
  runtime 真正使用的数据并使用明确类型。
- 在修改相邻代码时顺手使用 evaluator builtins、消除完全重复的 namespace cleanup、改进
  误导性名称；不为单纯命名另起大范围重构。
- 所有修复完成后，将一次性迁移工作单移入 `docs/archive/`，长期入口继续是
  [`docs/nylon.md`](../nylon.md)。

## 明确不做

- 不实现 rollout planner、fleet transaction、closure/rollback-generation manifest；
- 不增加完整 MPLS/tc/WARP 多机 VM matrix；只有在不扩张接口的前提下，才考虑一个聚焦
  secret assembly/key mismatch/restart 的单机 test；
- 不为已经人工清理并验证、且 rollback window 已关闭的 `google`/`oracle` 永久保留一次性
  transitional cleanup unit；若未来恢复旧 generation，按 rollback runbook 重新执行精确
  清理；
- 不把 PowerDNS preimage 扩大为完整 zone。并发保护只覆盖 owned A/AAAA projection，以及
  DELETE 会影响的 comments；无关 SOA/NS/TXT 变化不应阻塞 Nylon reconcile；
- 不在 NixOS option 层复制完整 compiler schema，也不为当前没有消费者的抽象增加接口；
- 不轮换 Nylon、WARP 或 PowerDNS key。

## PowerDNS 契约修订

PowerDNS `REPLACE` 只有在请求携带 `comments` 时才替换 comments；`DELETE` 会删除对应
comments。当前 adapter 不在 `REPLACE` 中发送 comments，并会拒绝删除带 comments 的
RRset。因此保留 managed-projection compare-and-apply，并增加“无关 TXT/SOA 变化不冲突”
测试；原迁移工作单中笼统的“zone 发生变化”改为“owned projection 或待删除 comments
发生变化”。

参考：<https://doc.powerdns.com/authoritative/http-api/zone.html>

## 实施顺序

1. 先补 compiler/CI 负向测试并完成 P0；
2. 再收窄 runtime projection、修复端口派生和离线 checks；
3. 加 production secret invariant、manifest output 和核心 health runner；
4. 修正 PowerDNS/package/docs/maintenance；
5. 格式化并运行所有本地门槛；
6. 归档原迁移工作单，将本文状态改为完成。

## 验收门槛

- malformed IPv4/IPv6、未知 schema 字段和 secret-like 字段的 negative tests 均失败于
  evaluation；现有 15/23/5/30 topology 与 central digest 不变；
- `nix eval .#checks.x86_64-linux.nylon-runtime-module.drvPath` 在没有 submodule query 时成功；
- targeted topology、runtime、PowerDNS、config parser 和 production secret checks 通过；
- manifest flake output 可直接 `nix eval` 或 `nix build`；health runner 的 `--help` 和离线
  manifest validation 不访问远端；
- `just fmt`、`git diff --check`、`nix flake check --all-systems --no-build` 通过；需要 private
  secret 的门槛另用 `.?submodules=1` 运行；
- `server-maintenance` inventory 仍无 `nylon_nodes`，且没有恢复任何可执行 Nylon ownership；
- 不创建提交、不推送、不部署，除非操作员另行要求。

## 完成记录

### 已验证事实

- compiler 现在使用 pinned nixpkgs IPv6 parser，并对 node、selector、underlay、endpoint、
  exit、families、presentation 和 WARP 执行 closed-schema/secret-like-field 检查；30 个
  negative cases 全部通过。
- 最终 topology 仍为 15 peers、23 exits、5 selectors、30 个 DNS RRsets；central
  SHA-256 保持
  `bfc095f5c9b347a554a453ad45991e33ce00922d3b4f8b0c0f8c95a8cfd5fd3c`。
- `centralStore` 和 public node artifact 均进入 `restartTriggers`；`reloadTriggers` 为空，
  `ExecReload` 只保留为手工 central-only 操作。`udpPort` 直接来自 compiled public node。
- plain flake input 可以 evaluation `nylon-runtime-module`；private submodule 可用时额外检查
  15 个 Nylon key、3 个 WARP key 和 1 个 PowerDNS key，共 19 个 ciphertext/recipient
  rules。
- generated central/public node 的 `nylon verify`、WLT TOML parse、runtime route/restart
  assertions、9 个 health runner package tests 和 12 个 PowerDNS adapter package tests
  均通过。PowerDNS 测试证明无关 TXT/SOA/serial 变化不阻塞 owned A/AAAA apply。
- `nix run .#nylon-health -- validate-manifest` 对真实 public manifest 的离线验证通过；该
  runner 对本机直接执行只读 probe，对其余节点使用有界并发/超时 SSH。
- `just fmt-check`、三个 worktree 的 `git diff --check`、
  `nix flake check --all-systems --no-build` 和
  `nix flake check --all-systems --no-build '.?submodules=1'` 全部通过。
- `server-maintenance` active inventory/playbooks/templates/tools/skills 中没有 `nylon_nodes`
  或可执行 Nylon ownership；保留的 `ns/maintenance-log.md` 没有为追求零文本命中而改写。

### 有意保持的边界

- 没有引入通用 rollout planner、fleet transaction 或完整多机 VM matrix；现有
  static/fixture/package tests 已覆盖本次证实的 failure modes，继续扩张会显著增加长期
  接口和维护复杂度。
- 按操作员指示，没有重新运行远端 fleet regression；本次没有远程写入、部署、提交或
  推送。
- PowerDNS API key 原值继续由 agenix 管理，本次没有轮换；轮换仍是未来独立待办。

原一次性迁移工作单已归档到
[`docs/archive/nylon-nix-native-migration.md`](nylon-nix-native-migration.md)；长期操作
入口继续是 [`docs/nylon.md`](../nylon.md)。

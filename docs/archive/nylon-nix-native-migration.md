# Nylon Nix 原生重构与 google/los6 退役计划

> 状态：已完成
>
> 批准日期：2026-08-28
>
> 完成日期：2026-08-28
>
> 责任：记录本次重构的目标架构、迁移顺序、回滚条件和验收门槛。

本文是已执行的一次性迁移工作单。长期架构与操作入口见 [`docs/nylon.md`](../nylon.md)；
运行时状态必须由生成的 manifest、Nix evaluation 和线上检查读取，不能以本文的日期快照
代替。

## 目标

把 Nylon 集群的完整期望状态迁入 `~/nix`，使纯 Nix 声明成为唯一权威来源，并从集群中
移除 `google` 和 `los6`。最终状态满足：

- 集群只包含 15 台 deploy-rs 管理的 NixOS 主机；
- `google` 因资源与构建性能不足退出 Nylon，但其 NixOS 主机及其他服务不在本次删除范围内；
- `los6` 不再运行 Nylon，但其 Debian/Tailscale 主机及其他服务不在本次删除范围内；
- 全网 central config、逐机 node config、出口 datapath、WLT outlet、策略路由和
  `ny.gaof.net` DNS desired state 均由同一份类型化 topology 生成；
- Nylon 私钥、WARP 私钥和 PowerDNS API 密钥由 agenix 管理，明文不进入 Nix store；
- `~/tmp/server-maintenance` 不再包含或执行 Nylon 部署、路由、WLT、DNS 或回归逻辑；
- 现有 Nylon 节点身份继续使用，不进行 keypair rotation；
- PowerDNS 使用当前 API 密钥直接迁入 agenix，本次不轮换。轮换记录为未来待办。

这不是把 Jinja/YAML 逐字改写成 Nix，而是收回 topology 的所有权并消除派生状态的重复
声明。

## 实施前已验证事实

### 成员与角色

迁移前生产 inventory 有 17 个 Nylon 节点：16 台 NixOS 和 Debian `los6`。实施期间的
本地/远端构建证明 `google` 的 960 MiB 内存和整体性能不足以继续承担 Nylon；操作员据此
明确批准将其移出集群。最终目标成员及 numeric ID 为：

| 节点 | Numeric ID |
| --- | ---: |
| `blog` | 16 |
| `cjia` | 17 |
| `ali-sg` | 18 |
| `el` | 19 |
| `el2` | 20 |
| `misc1-sz` | 23 |
| `misc1-sh` | 24 |
| `oracle3` | 25 |
| `oracle2` | 26 |
| `somo-minisforum` | 28 |
| `xtom-hkg` | 29 |
| `xtom-sjc` | 30 |
| `xtom-syd` | 31 |
| `somo-nanopi-r4s` | 32 |
| `misc0-jp` | 33 |

`google` 原使用 numeric ID 21 并发布一个双栈出口；`los6` 使用 numeric ID 27，并发布
三个出口。21 和 27 删除后均不得复用，22 也继续为已退役的 `hetzner0` 保留。

实际有五台 WLT selector：

- `cjia`；
- `el`；
- `el2`；
- `somo-minisforum`；
- `somo-nanopi-r4s`。

旧文档只列四台并遗漏 `el`，但 `el` 的 WLT 和 Nylon route unit 实际处于活动状态。本次
以五台为目标，不再从“是否启用 WLT”之类的旁路配置猜测 selector 身份。

维护仓库还声明了 `el/tun-lugi`、label 103，但线上 `el` 没有该接口，FRR 未运行，Nix
datapath 也只实现 labels 100、101、102。该项是失效的 selector catalog 条目，不迁入
最终 topology。

因此目标状态是：

- 15 个节点；
- 23 个与 Nix datapath 一致的出口；
- 5 台 selector；
- 不包含 `los6` 的三个出口；
- 不包含失效的 `el/tun-lugi` label 103。

这些数量是修订后的迁移验收常量。`google` 的移除已由操作员在实施过程中明确批准并写入
本文。

### 当前所有权分裂

迁移前，`nixos/optional/nylon.nix` 管理 binary、内核/MPLS、
systemd、firewall 和本机出口 datapath；`server-maintenance` 管理：

- Nylon keypair；
- `/etc/nylon/central.yaml` 和 `/etc/nylon/node.yaml`；
- WLT Nylon TOML；
- RPDB rules 和 MPLS route batches；
- PowerDNS A/AAAA 同步；
- 全网回归工具。

这使同一个出口同时存在于 host vars、Jinja、NixOS host config 和 WLT 生成逻辑中。
此外，现有 central template 从 `ansible_play_hosts_all` 生成；对 playbook 使用 `--limit`
会把全网 central config 错误裁成局部成员。

### 已发现的线上漂移

- `oracle` 不在当前生产 inventory，却仍运行旧的 Nylon service，并加载一份旧的
  12-router central config；它不属于目标 topology，需单独停止遗留 service。
- 15 个目标 NixOS host 均已在 flake/deploy-rs inventory 中；`google` 仍是 deployable
  NixOS host 但不再是 Nylon member；`el2-install` 只是安装
  configuration，不得成为 mesh member。
- 当前所有 17 个 inventory 节点加载同一个 central config，但这一事实只能作为迁移前
  baseline，不能写成长期架构事实。
- 五台 selector 仍有指向 `los6` 的 route/mark/table；四台最近生成的 selector 还含有
  `19/103` 失效项。
- 现有 route batch 主要使用 replace/add，删除 topology 项时不能保证旧 route、rule 和
  tc filter 被清理。新实现必须做精确 reconciliation。

### Secrets 与外部状态

- 现有 agenix registry 在迁移前尚无 Nylon 节点私钥；最终只保留 15 个成员的 ciphertext
  与 recipient rule，`google` 的导入副本在退出后删除。
- Nylon upstream 的 node config 只接受内嵌 `key`，没有 `key_file`；私钥不能直接进入
  Nix 生成的 store artifact。
- `misc1-sh` 的 WARP 私钥已由 agenix 管理；`ali-sg` 和 `oracle2` 仍引用
  `/var/lib/wireguard/wg-cloudflare-private-key`，需在本次重构中一并迁移。
- `server-maintenance/ns/passphrase.txt` 当前保存 PowerDNS API 密钥。按已批准决策，本次
  直接把当前值加密进 agenix，不调用 PowerDNS 创建或撤销 key；明文文件在新 adapter
  切换并验证后删除。
- PowerDNS primary 是远程可变系统。Nix 可以声明 DNS desired state，但仍需一个明确、
  幂等、可测试的 HTTP reconciliation adapter。

## 已批准的设计决策

### 采用 typed node manifests + fleet compiler

目标目录：

```text
nixos/nylon/
├── mesh.nix
├── nodes/
│   └── <host>.nix
├── compile.nix
├── module.nix
└── tests/
```

数据流只能沿一个方向：

```text
typed node manifests
        │
        ▼
pure fleet compiler
        │
        ├── shared central config
        ├── per-host NixOS modules and public node fragments
        ├── WLT outlet catalog and policy routes
        ├── PowerDNS desired RRsets
        ├── public rollout/health manifest
        └── evaluation, package and VM checks
```

禁止从最终 `nixosConfigurations.<host>.config` 反向聚合 topology。最终配置一旦依赖聚合
结果，这种设计会产生求值递归、双重 evaluation 和难以定位的跨主机耦合。

### Interface

`mesh.nix` 只保存全网协议默认值和明确的 fleet policy，例如公共 port、MTU、overlay
prefix、默认 cost、full-mesh graph policy、DNS zone 和保留 numeric IDs。

每个 `nodes/<host>.nix` 是该节点所有 Nylon 非秘密事实的唯一声明位置。建议的概念接口
如下；具体 Nix option 名可以在实现时按同一语义微调，但不得重新暴露派生值：

```nix
{
  numericId = 23;
  publicKey = "<existing Nylon public key>";

  underlays = {
    alvidi = {
      interface = "eth0";
      endpoint.ipv4 = "58.84.55.69";
      bindSource = true;

      exit = {
        label = 100;
        families = {
          ipv4 = true;
          ipv6 = false;
        };
        gateway4 = "58.84.55.65";
        presentation = {
          location = "HK,香港";
          operator = "ALVIDI";
        };
      };
    };
  };

  selector = {
    enable = false;
    ipv6 = true;
  };
}
```

一个 underlay 可以只有 endpoint/bind、只有本地 exit datapath，或同时具备两者。私钥
路径不属于 public topology；每台主机使用约定的 agenix secret 名称。

调用者不得手写或覆盖：

- Nylon node ID；它固定等于 topology attr/文件名；
- overlay IPv4/IPv6；它们从 numeric ID 和 mesh prefix 派生；
- endpoint port 和 IPv6 bracket formatting；
- `advertise_exit_node`；它从非空 exits 派生；
- full-mesh central graph；
- WLT mark、routing table 和 route/rule 文件路径；
- central/node YAML、WLT TOML 或 route batch；
- `managed_by_nix`、`frr_skip` 等迁移期标志。

### 编译器 invariants

evaluation/build 必须在以下情况失败：

- member 不在 deployable NixOS host inventory，或误包含 `google`、`los6`、`oracle`、
  `el2-install`；
- node name、numeric ID、overlay address 或 public key 重复；
- host directory/name、NixOS hostname 和 Nylon node ID 不一致；
- endpoint 不是显式 IP literal，或 endpoint/bind 冲突；
- 需要 bind 的节点没有可绑定的本机 source/interface；
- exit name 与本地 datapath 不对应，或同一节点 label 重复；
- selector 使用无法编码的 numeric ID/exit label；
- 生成的 mark、routing table 或 MPLS selector 冲突；
- 缺少对应的 age ciphertext 声明；
- WLT 直接引用未由 compiler 生成的 outlet。

WLT mark/table 编码继续遵守
[`docs/policy-routing-marks.md`](../policy-routing-marks.md) 的契约；本计划不建立第二份编码
规范。

### 生成物与生命周期

Compiler 应生成确定性、按名称排序的公共 artifact：

- 所有主机共用且内容相同的 central config；
- 每台主机不含私钥的 public node fragment；
- 每台 selector 的 WLT TOML、policy rules 和 MPLS routes；
- 预期 PowerDNS A/AAAA RRsets；
- 不含秘密的 topology/health manifest；
- 静态 assertions 和 tests。

公共 key、endpoint、overlay 和 central graph 可以进入 Nix store。每个 node private key
由 agenix 解密到运行时路径，通过 systemd credential 交给 `ExecStartPre`，并在
`/run/nylon/` 中以 `0600` 原子生成完整 node config。启动前必须：

1. 检查 private key 格式；
2. 派生 public key 并与 node manifest 比较；
3. 对 runtime node config 和 shared central config 执行 `nylon verify`；
4. 只有全部成功才替换运行时文件并启动 service。

central、node-local config、private key 和 binary 变化都通过
`systemd.services.nylon.restartTriggers` 触发 restart，避免 daemon 返回
`RESTART_REQUIRED` 后让声明态与运行态分裂。`ExecReload` 只保留给操作员手工应用 daemon
明确接受的 central-only 变化，并在拒绝时恢复旧文件。当前固定的 agenix 0.15.0 没有
`age.secrets.<name>.restartUnits` option；WARP 是 networkd netdev，也没有可引用的专用 WARP
unit，secret 更新必须走同一条受测 activation 路径。

WLT TOML 由 immutable store directory 提供给
[`nixos/optional/home-router/wlt.nix`](../../nixos/optional/home-router/wlt.nix)。Policy routing
直接消费生成的字符串，不再读取 `/var/lib/nylon/policy-routing/*.batch`。退出旧 generation
或删除出口时，service 必须清除上一代所拥有的 routes、rules、tables、tc filters 和
nftables state，不能只执行 `replace`。

### 真实 dependency seams

| 依赖 | 分类 | 处理方式 |
| --- | --- | --- |
| topology normalization、central/WLT/route 生成 | in-process | 纯 Nix 函数和静态测试，不创建 adapter |
| Nix store artifacts、systemd、MPLS、nft/tc | local/substitutable | NixOS module 和 VM tests |
| 节点及 WARP 私钥 | local/substitutable secret | agenix production input；fixture key 用于 VM test |
| 远程 NixOS activation | remote but owned | 现有 deploy-rs/SSH；按 wave 执行 |
| PowerDNS | true external | 小型 HTTP reconcile adapter；fixture/in-memory zone 测试 |
| Tailscale | external transport | 只作为 deploy/health transport，不参与 topology 推导 |

不创建通用 plugin、provider 或 cluster transaction framework。15 台独立主机无法实现
真正的 fleet-wide atomic commit；本计划依赖单机 generation 原子性、分 wave 停止、
mixed-generation 兼容和显式 rollback。

## 未采用的方案

### 保留 Ansible/YAML 作为 source of truth

让 Nix 继续消费 Ansible 生成物的迁移成本最低，但保留两套 ownership，并继续存在
`--limit` 裁短 central config、WLT 与本地 datapath 漂移等失败模式，不满足目标。

### 把完整 YAML 加密进 agenix

完整 node config 大部分不是秘密。把它们分别加密成 15 个 ciphertext 会隐藏 MTU、bind、
ID 和 endpoint 等应当可审查的行为，同时重复全网 topology，不能获得 Nix evaluation 的
类型和一致性检查。

### 单一巨型 topology 文件

把所有公共和本地 datapath facts 放进一个 `topology.nix` 能保证一致性，但单机修改需要在
大文件中定位，且会重复主机网络配置。逐节点 manifest 保留同一 compiler 和全局视图，
同时提供更好的 locality。

### 聚合最终 NixOS configurations

先评估所有 host config，再从 `nixosConfigurations` 收集 Nylon options，看似可自动复用
主机网络字段；但 compiled topology 又是这些 host config 的输入，形成递归。为少量静态
地址减少重复不值得引入双重 evaluation 和跨 fleet 求值耦合。

## 仓库变更范围

### `~/nix`

1. 新增 `nixos/nylon/` typed manifests、compiler、NixOS module 和 tests。
2. 将旧 `nixos/optional/nylon.nix` 中仍有价值的 binary、systemd、MPLS 和 exit datapath
   收入新 module；删除 Ansible ownership、
   `ConditionPathExists=/etc/nylon/...` 和可变配置假设。
3. 最终删除或内联只作为旧调用入口的
   `nixos/optional/nylon-public-exit.nix`，各 host 不再分别声明 Nylon label。
4. 把 [`nixos/optional/policy-routing.nix`](../../nixos/optional/policy-routing.nix) 的 Nylon
   消费者改为静态 strings；确认无其他 file consumer 后移除 `{ file = ...; }` 形式。
5. 让 WLT 消费 compiler 生成的 immutable config directory；保留
   `/var/lib/wlt/persist` 的用户选择状态，但 topology 不再存于该目录。
6. 在 flake 中暴露 topology manifest/checks，并让 15 个 deployable host 消费各自的
   compiled module。不得让 `oracle` 或 installer configurations 隐式 enable Nylon。
7. 增加最少量的 `just`/flake 运维入口用于 build、inspect、verify 和 DNS reconcile；
   继续使用现有 `just deploy <target>`/deploy-rs 做 host activation，不实现新的通用
   rollout framework。
8. 新增 15 个 node private-key age secrets；把 `ali-sg`、`oracle2` 的 WARP key 迁入
   agenix，保留 `misc1-sh` 已有声明。
9. 新增 PowerDNS API key age secret 及其 adapter consumer。Secret 声明与 consumer 放在
   一起，并遵守 [`docs/secrets.md`](../secrets.md) 的 recipient/activation 规则。
10. 把仍有价值的 Nylon runbook 和 regression checks 迁到本仓库，并改为消费 compiler
    生成的 manifest，不再解析 Ansible inventory/host vars。

### `~/tmp/server-maintenance`

只有在 Nix 实现、全网切换和 rollback window 均完成后，才删除旧 ownership：

- `.agents/skills/deploy-nylon/`；
- `playbooks/nylon-deploy.yml`；
- `playbooks/nylon-dns-sync.yml`；
- `playbooks/nylon-wlt-deploy.yml`；
- `playbooks/frr-deploy.yml`；
- `playbooks/exit-snat-deploy.yml`；
- `templates/nylon-*.j2`、`templates/wlt-nylon.toml.j2` 和仅供 Nylon 使用的 FRR
  templates；
- `tools/exit-snat/`；
- `tools/exit-discovery/` 中只服务 Nylon inventory/host vars 的实现；
- `nylon/regression/`，前提是等价检查已迁入 Nix；
- `nylon/runbook.md`、`nylon/cloudflare-warp-exit.md` 中的活跃说明，迁入 Nix 后删除
  旧副本；maintenance log 只保留于 Git 历史或迁入 `docs/archive/`；
- `inventory/tailscale.py` 的 `NYLON_HOSTS` 和 `nylon_nodes` group；保留通用 Tailscale、
  NixOS 和 SSH inventory；
- 所有 `host_vars/*.yml` 中的 `nylon_*`、`exits`、`frr_skip`、`wlt_enable_v6` 等 Nylon
  字段；变空的文件删除；
- `ns/passphrase.txt`，仅在 agenix consumer 已切换并通过 DNS read-back 后删除。

已知需要保留的非 Nylon host vars 包括：

- `oracle2` 的 `ansible_host`；
- `xtom-hkg` 的 `ansible_host`；
- `xtom-sjc` 的 `ansible_host` 和 transfer method；
- `xtom-syd` 的 `ansible_host`。

删除 FRR、exit discovery、Hetzner firewall 或其他混合文件中的 Nylon 代码前，必须用
consumer search 证明没有非 Nylon 使用者；只删除已证明归 Nylon 所有的部分。历史文档中
描述已完成事件的文字不需要为达到 `rg nylon == 0` 而改写。

`users.los6` 等 secrets recipient 可能还服务非 Nylon secrets，不因移除 Nylon member 而
自动删除。

## PowerDNS API 密钥决策

本次迁移执行以下固定策略：

1. 使用当前 `server-maintenance/ns/passphrase.txt` 的有效值；
2. 不创建新 API key、不撤销当前 key、不修改 PowerDNS server authentication；
3. 通过不落额外明文副本的管道，把当前值写入 private secrets submodule 中的 age
   ciphertext；
4. adapter 只通过 agenix runtime path/credential 读取 key，不通过 argv、environment、
   Nix string 或 log 传递；
5. 用当前 key 完成 read-only API probe，再在 fixture/in-memory zone 验证 adapter；
6. 正式 reconcile 后 read back `ny.gaof.net` owned RRsets；
7. 只有 adapter 已稳定读取 age secret 后，才从 maintenance working tree 删除
   `ns/passphrase.txt`。

接受的残余风险：当前 key 已存在于 Git 历史，直接迁入 agenix 不会消除该暴露面。按用户
决定，本次不把轮换放进关键路径。

未来待办：在本次迁移稳定后另开维护窗口，创建新 PowerDNS API key，更新 age secret，
验证新 key，再撤销旧 key。该待办不得在本次实施中顺手执行。

## 分阶段迁移

### 阶段 0：冻结与 baseline

1. 本计划进入 `docs/` 后，暂停使用 maintenance Nylon playbooks 修改 topology。
2. 重新采集 17 个现役节点的 service、binary、central hash、node identity、listener、
   route model 和 dispatch 状态。
3. 采集五台 selector 的 WLT config、marks、rules、tables、MPLS routes 和 tc filters。
4. 保存 PowerDNS zone preimage，明确 adapter 只拥有 `ny.gaof.net` 的 A/AAAA；SOA、NS、
   TXT 和其他 types 不在删除范围内。
5. 记录每台目标主机当前 Nix generation 和 rollback generation。
6. 如果 member、identity、exit 或 selector 与本文验收常量不同，停止并更新计划。

### 阶段 1：实现 compiler，不改变线上行为

1. 建立 15 个目标 node manifests、mesh defaults、normalizer 和 compiler；`google` 明确
   列入 forbidden members，numeric ID 21 列入 reserved IDs。
2. 增加临时、内部的 `migrationPeers.los6` public declaration，使第一代 central config
   仍包含 los6 及其三个 WLT 出口和 A/AAAA DNS records，但不能为它生成 NixOS host
   module、datapath 或 secret requirement。
3. `oracle` 和 `el2-install` 不进入 migration peer 或最终 member set。
4. 生成第一代 WLT registry 时删除已证实无 datapath 的 `el/tun-lugi` 103；这是第一代
   唯一允许的 topology 清理，需单独比较和验证。
5. 实现 runtime node config assembly、public-key preflight、central reload 和 local
   restart behavior。
6. 实现 WLT/policy route 生成及精确 removal reconciliation。
7. 实现 PowerDNS desired manifest 和 fixture adapter；此阶段不修改真实 zone。
8. 把现有回归能力迁为 manifest-driven checks。

临时 `migrationPeers` 是本次 expand/contract 所需的兼容输入，最终必须删除，不能成为
长期 public interface。

### 阶段 2：Secrets shadow migration

1. 从 15 台目标主机逐台读取现有 `/etc/nylon/private.key`，通过 SSH stdout 到 age stdin
   直接加密，控制机磁盘不保存新的 plaintext copy。
2. 从每个 private key 派生 public key，与 node manifest 和当前 central config 三方
   比较。任一不一致都停止该节点迁移；不自动生成或替换 keypair。
3. 先只部署 agenix ciphertext、runtime path 和 preflight unit，不切换当前 Nylon
   service ownership。
4. 迁移 `ali-sg`、`oracle2` 的 WARP key，并重新验证已有 `misc1-sh` secret consumer。
5. 按上一节的固定策略把当前 PowerDNS API key 直接迁入 agenix，不轮换。
6. 导入时直接调用 `age` 并从 `secrets.nix` 求出 public recipients；不能使用当前
   `agenix -e`/`--rekey`，因为 agenix 0.15.0 会在 `mktemp` 目录创建 cleartext。
7. 确认所有 decrypted runtime files 的 owner/mode、systemd restart triggers 和日志
   行为；检查 Nix closure 不含 secret plaintext。

旧 `/etc/nylon/private.key` 在 rollback window 结束前不提前清除；新 service 切换后它们
只作为受控回滚材料，不能继续作为 active input。PowerDNS 使用的是同一个 key，回滚不
依赖旧明文文件；agenix consumer 验证后应按既定策略删除 `ns/passphrase.txt`。

### 阶段 3：离线门槛

进入任何 service 切换前必须全部通过：

- topology evaluation 和 invariants；
- `git add -N` 覆盖所有新 `.nix` 文件；
- `just fmt`、`just check` 及新增的 Nylon checks；
- 15 个 production Nylon host closures 和 `google` 的非成员 deconfiguration closure
  全部构建，覆盖 x86_64 和 aarch64；
- `el2-install` 可以 evaluation，但不成为 Nylon member；
- 第一代 16-router central artifact 对所有 15 个 managed host 完全一致；
- 第一代 migration artifact 精确为 16 peers、26 exits、5 selectors 和 32 个 A/AAAA
  RRsets；最终 artifact 精确为 15/23/5/30；
- 15 个 identity preflight 全部通过；
- `nylon verify` 能解析 generated central 和 fixture/runtime node config；
- WLT TOML parse、mark/table uniqueness 和 route snapshot tests；
- 聚焦 fixture checks 覆盖 secret-independent runtime evaluation、key assembly/verify、
  reload/restart contract、selector route rendering 和 WLT parse；kernel datapath 由 canary
  与线上针对性验收覆盖，不建立完整多机 VM matrix；
- PowerDNS fixture tests 覆盖 add/update/delete、幂等、owned A/AAAA projection 与待删除
  comments 的 preimage race、read-back，以及保留非 owned RR types；
- public manifest 明确成员、projection 和 target central digest；wave 与回滚 generation
  记录在本工作单并由操作员逐次批准，不建立通用 rollout planner。

### 阶段 4：第一代所有权切换，保留 los6 membership

本阶段把 15 台目标 NixOS 的 active Nylon ownership 从 Ansible 切到 Nix；central
membership 仍包含 los6。`google` 在本阶段先从 compiler/DNS projection 删除并部署一个
禁用 Nylon 的本地构建代际，使资源不足节点不再参与后续 rollout。

1. 先部署一个普通 x86 leaf canary（`misc0-jp`）。
2. 再部署 established aarch64 selector canary（`somo-nanopi-r4s`）。
3. 两台 canary 均验证 runtime identity、central digest、overlay 双栈、出口/selector 和
   stale-state cleanup。
4. 把已部署 canary 更新到不含 `google` 的 16-peer migration artifact，再将其余普通
   节点和 exit nodes 分小批部署；每 wave 后验证新旧 generation 之间互通。
5. 剩余四台 selector 逐台部署，不并发切换关键 selector。
6. 完成后要求 15 台 managed host 都从 Nix runtime config 启动、使用同一 16-router
   central artifact；los6 仍运行原配置。
7. 停止所有 maintenance Nylon playbook 的执行入口，但暂不删除文件。

任何 wave 失败都停止后续部署；已经成功的主机可以保持新 generation，因为此阶段 member
和 identity 未变化。

### 阶段 5：收缩为最终 15 节点 topology

1. 从 compiler input 删除临时 `migrationPeers.los6`，生成最终 15-node topology。
2. 先把最终 generation 逐台部署到五台 selector，使它们撤销 los6 的三个 outlet、marks、
   rules、tables 和 routes，同时确认 `el/103` 也不存在。
3. 五台 selector 全部验证不再选择或展示 los6 后，在 `los6` 停止并禁用
   `nylon.service`。
4. 在 los6 确认 UDP 6622 不再监听、`nylon0` 不再承载角色；不删除 Tailscale machine，
   不停止其他服务。
5. 把最终 generation 分 wave 部署到其余 10 台 NixOS 节点。
6. 每 wave 核验 central digest、identity、service、listener、overlay connectivity、route
   model 和 dispatch 状态。
7. 全部 15 台收敛前不复用 numeric ID 21 或 27，也不删除 los6 回滚材料。

阶段 5 的 member diff 只是删除 los6；`google` 已在阶段 4 单独删除。旧 generation 可能
继续尝试已退出的 los6，新 generation 不再接受它，但其余 15 个 identity 不变，因此允许
短暂 mixed-generation。key rotation、
numeric ID 复用或 graph partition 不具备这一性质，未来必须另做 expand/contract 设计。

### 阶段 6：DNS 与遗留 oracle

只有 mesh 已收敛并通过初步验证后才修改外部 DNS：

1. 从 compiler 生成最终 15 个 A 和 15 个 AAAA desired RRsets；
2. 用保存的 owned A/AAAA projection 及 DELETE 会影响的 comments preimage 做
   compare-and-apply；如果 owned projection 或待删除 comments 在 plan/apply 间变化，
   adapter 必须拒绝写入并重新 plan；
3. 删除 `google.ny.gaof.net` 与 `los6.ny.gaof.net` 的 A/AAAA，保留非 owned RR types；
4. read back primary/API 和 authoritative responses；考虑现有 TTL 后再检查 recursive
   resolver；
5. DNS reconcile 失败时单独重试或应用 inverse patch，不自动回滚已经健康的 mesh；
6. 在 `oracle` 停止并禁用遗留 Nylon service，确认其旧 central config、`nylon0` 和
   listener 不再活动；不因该操作删除 oracle 主机的其他服务。

### 阶段 7：最终验收和 maintenance 清理

完成下述最终验收后，由操作员显式关闭 rollback window：

- 15/15 节点运行目标 Nix generation 和 Nix store Nylon binary；
- 15 台 runtime private key 派生的 public key 与 topology 一致；
- 所有节点 central semantic digest 相同，router set 精确为 15；
- overlay IPv4/IPv6 全矩阵可达，无 unreachable route 或 dispatch-full；
- 23 个出口按声明的 family、SNAT 和 source routing 分别探测；
- 五台 selector 的 WLT catalog、marks、rules、tables 和 MPLS routes 一致；
- 不存在 los6 的 `0x270..0x272`、tables `5270..5272` 或 routes `27/100..102`；
- 不存在失效 `el/103`、mark `0x193` 或 table `5193`；
- PowerDNS owned records 精确为目标 15 组 A/AAAA，google/los6 A/AAAA 不存在；
- google、los6 和 oracle 的 Nylon service inactive/disabled；
- secret plaintext 不在 Nix closure、argv、environment 或 logs；
- failed units 和相关 error logs 无新异常。

随后：

1. 删除 maintenance 中上一节列出的全部 Nylon ownership；
2. 删除目标机旧的 mutable central/node/WLT/route batch 输入和 legacy units；
3. 保留 Nix 生成的 runtime/state paths及 WLT selection persistence；
4. 再次运行两个仓库的 consumer search，确认 maintenance 无可执行 Nylon 逻辑；
5. 运行 Nix formatting/evaluation/build 和迁移后的 regression；
6. 将稳定架构契约写入长期 Nylon reference，把本文移入 `docs/archive/`；
7. 单独创建 PowerDNS API key rotation 待办，不在本次清理中执行。

## 回滚

### Secrets shadow 阶段

Secret migration 尚未接管 service 时没有运行时变化。任一 identity 或权限检查失败都停止，
删除错误 ciphertext/声明并继续使用现有 `/etc/nylon`；不得生成新 keypair 掩盖问题。

### 第一代所有权切换

单机 activation 失败时回到该机记录的旧 Nix generation，并停止当前 wave。由于第一代仍
包含 los6 且 identity 不变，已经成功的节点无需为了一个局部失败立即整体回滚。

如果决定全量回滚第一代：

1. 按反向 wave 将 15 台目标成员恢复到旧 generation；不把 `google` 重新纳入 Nylon；
2. 验证旧 `/etc/nylon`、WLT 和 routes 重新成为 active input；
3. 在恢复 maintenance playbook 前确认 inventory 精确为 15 个目标成员加 `los6`，并明确
   排除 `google`；禁止使用 `--limit` 渲染 central config。

### 最终 member contraction

如果在停止 los6 前失败，只需把已切 selector 回滚到第一代并检查 los6 仍健康。

如果 los6 已停止且需要恢复：

1. 先把需要接收 los6 的 NixOS nodes 和五台 selector 恢复到包含 los6 的第一代 central
   与 WLT registry；
2. 验证 common 15-node mesh 和 selector routes；
3. 再启用并启动 los6 Nylon；
4. 验证 los6 identity、overlay 和三个出口；
5. 如果 DNS 已修改，用保存的 zone preimage/inverse patch 恢复 los6 A/AAAA，并
   read back。

不能先启动 los6、再希望尚未恢复的 final-generation peers 自动接受它。

PowerDNS reconcile 失败与 mesh health 解耦。DNS 写入失败不应触发 15 台主机回滚；保留
zone preimage，修复 adapter 或 API 问题后幂等重试。

## 非目标与未来待办

本次明确不做：

- 删除 los6 Debian/Tailscale 主机或其非 Nylon 服务；
- 删除 google NixOS 主机或其非 Nylon 服务；
- 删除可能仍服务其他 secrets 的 los6 recipient；
- 轮换任何 Nylon node keypair；
- 轮换 PowerDNS API key；
- 修改 Nylon upstream 增加 `key_file`；运行时 credential assembly 足以完成本次迁移；
- 构建通用 orchestration/plugin/provider framework；
- 清理与 Nylon 没有已证明 ownership 关系的 maintenance 历史或基础设施代码。

未来待办：

- 在独立维护窗口轮换已迁入 agenix 的 PowerDNS API key；
- 评估在 owned Nylon fork 中增加 `key_file`，仅当它能实质简化 runtime secret lifecycle；
- 根据实际使用决定是否继续维护 `ny.gaof.net`；本次默认保留；
- 为未来 key rotation、numeric ID 复用和 graph 变化增加明确的 expand/contract planner，
  不把本次“删除单一 member”的兼容结论泛化。

## 完成定义

只有同时满足以下条件，本迁移才算完成：

- 最终 15-node topology 是 Nylon 所有公共和本地行为的唯一声明来源；
- 15 台主机、23 个出口、5 台 selector 和 DNS desired state 全部由 compiler 派生；
- 所有 runtime secrets 由 agenix 提供，PowerDNS 使用迁入的当前 key；
- google、los6 与 zombie oracle 已退出 Nylon，且未误删其其他服务；
- Nix static/fixture checks、两架构 closures、分 wave runtime checks 和最终 fleet regression
  全部通过；
- `server-maintenance` 不再拥有或执行 Nylon 代码，必要的 runbook/checks 已迁入 Nix；
- rollback window 已由操作员明确关闭，旧 active inputs 和临时 `migrationPeers` 已删除；
- PowerDNS key rotation 作为独立未来待办被保留，没有在本次迁移中执行。

## 实施记录

### 2026-08-28：阶段 0 baseline

- 两个仓库在开始实施时均无既有未提交源码变更；Nix 仓库只有本文档，随后实施产生的
  变更均属于本工作单。
- 动态 inventory 仍为本文批准的 17 个节点；16 台目标 NixOS 和 los6 的
  `nylon.service` 全部 active。
- 17 个 inventory 节点的 `/etc/nylon/central.yaml` SHA-256 均为
  `7e45a9bf20425f28124bd895af2e04ff5513f5bbe6b8e7f224da8ddc60f753be`。
- 控制机是 `el2`，其 baseline 在本机直接采集；其他节点才通过 Ansible/SSH 检查。
- 17×17 IPv4 overlay 探测无全丢包；少量长途链路出现 10%–20% 瞬时丢包。
- 不含本机的 16-node route snapshot 有 240 条 route、0 unreachable、2 条瞬时
  shortest-path mismatch；这是迁移前已有抖动，最终验收不能把“没有新增问题”等同于
  “精确最短路径已经证明”。
- 所有采样节点的 dispatch-full 为 0。
- 五台 selector 的 `wlt.service` 和 `nylon-routes.service` 均 active；每台配置含三个
  los6 outlet。除旧配置的 `el` 外，其余四台含 `19/103`；本机 `el2` 仍有
  `0x270`、`0x272`、`0x193` 及对应 tables/routes。
- `oracle` 遗留 Nylon 仍 active，central SHA-256 为
  `5539434c1d5fa115ce1486b1bd5995d19e6433d64688d8e4b7f402ecfa80d678`，状态显示 11 个
  neighbours。
- PowerDNS zone `ny.gaof.net.` baseline serial 为 `2026082801`，完整 API response 的
  canonical SHA-256 为
  `b97e439c2f7d6baa3cec566cebcb0d5e4a4657417ec4be1a8be982f19c8ba1fd`；共有 35 个
  RRsets，其中 34 个 A/AAAA，los6 A/AAAA 分别指向 `10.250.10.27` 和
  `fd10:250:10::27`。

### 2026-08-28：阶段 1–4 实施与计划修订

- topology compiler、NixOS runtime adapter、PowerDNS plan/apply adapter、agenix secret
  assembly 和 checks 已实现；全平台 `nix flake check --all-systems --no-build` 通过。
- 现有 16 个 NixOS identity 曾逐一导入并验证。操作员随后因 `google` 性能不足决定将其
  退出 Nylon；其 topology manifest、agenix rule 和本次导入的 ciphertext 已删除，旧
  generation/Nix store 仍提供受控回滚材料。最终保留 15 个 identity。
- `misc0-jp` x86 leaf canary 已切到 Nix-owned runtime，17-peer 双栈 overlay 34/34 可达。
- `somo-nanopi-r4s` aarch64 selector canary 暴露出生成 shell 管道只安装每个地址族最后一张
  route table 的缺陷；实现改为逐条执行声明路由并新增 generated-script 回归检查。重部署
  后 24 个 IPv4、12 个 IPv6 selector tables 全部存在，WLT/出口 datapath 正常，34/34
  overlay 探测通过。
- `blog`、`misc1-sz` 已切换到最初的 17-peer Nix generation。`google` 的远端构建因 960
  MiB 内存和依赖获取过慢被取消；遗留远端 rebuild 经精确 PID/命令行核验后终止，随后
  按操作员要求改为本地构建并成功激活。该代际只作为立即 deconfigure 的过渡状态。
- 从本条修订开始，Generation A 的常量改为 15 个 NixOS 成员加 `los6`：16 peers、26
  exits、5 selectors、32 个 A/AAAA RRsets；最终常量为 15/23/5/30。所有已迁移节点必须
  更新到该 16-peer artifact，`google` 必须部署非成员代际并保持 Nylon inactive/disabled。

### 2026-08-28：阶段 4 Generation A 收敛

- 15 台目标 NixOS 主机和 `los6` 全部加载同一份 16-peer central config；其 SHA-256 为
  `b0655f2271d1dc5034e56219b55ebba9422b431f77adfa99a4a18dc0a3012159`。
- 从 `el2` 对 16 个 peer 的 overlay IPv4/IPv6 探测为 32/32 可达；逐机 runtime identity、
  `nylon verify`、服务 ownership、出口 projection 和 selector projection 均通过。
- 三个 WARP 出口 `ali-sg`、`misc1-sh`、`oracle2` 均由 agenix key consumer 接管，并通过
  `ping -I wg-cloudflare 1.1.1.1` 的实际流量检查。
- `google` 已部署非成员 Nix generation：Nylon unit inactive/disabled，UDP 6622、
  `nylon0`、MPLS state 和 Nylon secret consumer 均不存在；Tailscale 及其他主机职责保留。
- 运行中偶见低频 FakeTCP/dispatch warning，但没有持续 control-plane、邻居或可达性故障，
  因此未把它们误判为阻塞迁移的回归。

### 2026-08-28：阶段 5–6 最终 topology、主机退役与 DNS

- 删除临时 `migrationPeers.los6` 后，compiler 直接产出唯一的最终 topology：15 peers、
  23 exits、5 selectors、30 个 DNS RRsets；保留 numeric IDs 21、22、27，禁止复用。
- 最终 central config SHA-256 为
  `bfc095f5c9b347a554a453ad45991e33ce00922d3b4f8b0c0f8c95a8cfd5fd3c`。先并行切换五台
  selector，再并行切换其余十台成员；15/15 主机的 `/etc`、`/run` 摘要和目标 generation
  一致，`nylon verify` 均通过，每台精确看到 14 个 neighbours。
- 五台 selector 已删除 `google`/`los6` 的 marks `0x210`、`0x270..0x272`、tables
  `5210`、`5270..5272`、MPLS routes 和 WLT outlets；失效的 `el/103` 也不存在。
  `el2` 曾短暂保留两条 userspace Babel withdrawal tombstone，但没有对应 kernel datapath，
  属于有界的撤销确认状态而非遗留路由。
- 最终从 `el2` 对 15 个成员的 overlay IPv4/IPv6 探测为 30/30 可达；三个 WARP 出口再次
  通过真实 source-interface 流量检查。稳定等待后只在 `oracle3`、`xtom-sjc` 偶见单条
  FakeTCP warning，没有持续故障；按操作员指示不再追加无必要的全量回归。
- 在确认目标身份后，`los6` 仅退役 Nylon-owned service、FRR、SNAT/forward unit、
  `inet nylon_exit`、MPLS/tc state 和 nft include。HE IPv6、WARP、gost、named、Docker、
  exim4、Tailscale 及现有 containers 均保留且健康；原配置备份为
  `/etc/nftables.conf.pre-nylon-retire-20260828`，被动 unit/config 仍可用于受控回滚。
- 遗留 `oracle` 已部署不再导入 Nylon 且不开放 UDP 57175 的 Nix generation，并精确删除
  旧的 `ens3` tc/MPLS state。UDP 3334、Tailscale、SSH、fail2ban 及非 Nylon firewall
  state 均保留且健康。
- PowerDNS plan 精确包含四项删除：`google.ny.gaof.net` 和 `los6.ny.gaof.net` 的 A/AAAA。
  apply 共执行 4 项变更，preimage digest 为
  `38f745d0f7207a54c406803414a20056697409d06e26bc78d08b3f17641055dc`，read-back/desired
  digest 为 `1e5c59a62e415bd19991a4e24cf013d56d2d95d42a607beffd95383d83c6968c`；第二次 plan
  为空且两个 digest 相同。可达的 authoritative nameserver 均确认这四条记录不存在，
  `misc1-sz` 的目标记录正确；本地 recursive resolver 的短暂旧缓存不属于 authoritative
  漂移。
- 当前 PowerDNS API key 已原值迁入 agenix，未创建、撤销或轮换 key；明文
  `server-maintenance/ns/passphrase.txt` 仅在 read-back 成功后删除。轮换仍是独立未来待办。

### 2026-08-28：阶段 7 清理与最终验收

- `~/tmp/server-maintenance` 已删除 Nylon deploy skill、全部 `nylon/` 活跃资料、五个相关
  playbook、FRR/Nylon/WLT templates、exit discovery/SNAT tools、纯 Nylon host vars 和
  inventory 的 `nylon_nodes` projection；混合 host vars 只保留 SSH inventory 字段。
- 最后一个非文档 consumer，即 `hetzner0` firewall 中旧 Nylon NAT 规则，也在证明无其他
  使用者后删除；Tailscale NAT/firewall 保留。清理共涉及 67 个文件，净删除 6730 行。
  consumer search 余下命中均为历史说明或仍有效的 Nix-owned 架构文档，没有可执行的
  maintenance Nylon ownership。
- 动态 inventory 的最终 JSON 只暴露 `linux_online` 和 `linux_offline` children，不再有
  `nylon_nodes`；两个仓库的 whitespace/diff checks 均通过。
- topology evaluation 得到 15/23/5/30，30 个 negative invariant cases 全部通过；
  topology、runtime、config/WLT parser、PowerDNS、production secret inventory 和 health
  runner targeted checks 构建通过，最终
  `nix flake check --all-systems --no-build '.?submodules=1'` 也通过。
- 最终公共架构与操作入口已写入 [`docs/nylon.md`](../nylon.md)。临时 migration compiler
  interface、旧 mutable inputs 和 maintenance 活跃 ownership 均已删除，本工作单关闭。

### 2026-08-28：迁移后审查

- 独立 Standards/Spec review 提出的建议已按风险与复杂度重新筛选；已证实的 compiler、
  runtime、CI、secret inventory、PowerDNS 和运维检查缺口均已修复。
- 修复范围、取舍和验证证据见
  [`docs/archive/nylon-post-migration-review-fixes.md`](nylon-post-migration-review-fixes.md)。
- 未引入通用 rollout planner 或完整多机 VM matrix；这些改动缺少当前需求，不值得扩大
  长期接口与维护面。

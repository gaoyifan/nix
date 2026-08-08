# Codex v0.147 paginated fork 与 sessions 软链接的上游现状

> 调查日期：2026-08-08。通过 GitHub REST API 核对了 `openai/codex` 的 issue、PR、
> review/comment、release、commit 和 Discussion 本文，并对照 `rust-v0.146.0`、
> `rust-v0.147.0` 与调查时 `main` (`936f5eb3`) 的源码。本文只使用 OpenAI 官方
> 仓库和官方文档作为事实来源。

## 结论

截至 2026-08-08，**没有找到与本机错误完全相同的公开 issue、PR 或 Discussion**：

```text
rollout path `...` must be in Codex home directory
```

精确短语在 issue/PR 本文和评论中的搜索结果为 0；`sessions` 软链接 + paginated
`thread/fork` 的组合也没有公开报告。因而当前没有上游确认的修复版本、负责人或
发布时间。可复核搜索：
[exact error](https://github.com/openai/codex/issues?q=%22must+be+in+Codex+home+directory%22)、
[symlink fork](https://github.com/openai/codex/issues?q=symlink+fork+CODEX_HOME)。

但上游源码和相邻报告足以确认这是一个真实的 v0.147 行为交叉点，而不是惰性安装
wrapper 引起的：

1. [PR #36950](https://github.com/openai/codex/pull/36950) 于 2026-08-04 合并，
   并进入 2026-08-07 发布的
   [v0.147.0](https://github.com/openai/codex/releases/tag/rust-v0.147.0)。该 PR 让 TUI
   resume、fork、retry 和 prompt-edit 使用分页历史；更关键的是 v0.147 源码对所有
   非 ephemeral 的 TUI 新线程直接设置
   [`history_mode = Paginated`](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/tui/src/app_server_session.rs#L1693-L1728)。
   v0.146 同一构造器没有这个字段。
2. paginated fork 来自 2026-07-24 合并的
   [PR #35220](https://github.com/openai/codex/pull/35220)：子 rollout 不再复制完整父历史，
   而是用 `history_base` 引用被冻结的父历史前缀。准备引用时，代码先把 rollout
   交给 `scoped_rollout_path(codex_home, ..., "Codex home")`
   [做范围检查](https://github.com/openai/codex/blob/936f5eb3ee223ab34dcb221fa7c5f9943c8092bd/codex-rs/thread-store/src/local/rollout_lineage.rs#L75-L96)。
3. `scoped_rollout_path` 会分别 canonicalize 根目录和 rollout，再要求后者
   `starts_with` 前者；否则就产生本机看到的错误
   ([源码](https://github.com/openai/codex/blob/936f5eb3ee223ab34dcb221fa7c5f9943c8092bd/codex-rs/thread-store/src/local/helpers.rs#L31-L60))。
   因此 `~/.codex/sessions -> ~/.syncd-dotfiles/.codex/sessions` 会让 rollout 的真实路径
   落到 canonical `~/.codex` 外。调查时的 `main` 仍是这段实现，尚无修复。

## 精确匹配与相关证据

| 级别 | 上游项目 | 状态（2026-08-08） | 与本问题的关系 |
|---|---|---|---|
| 精确 | `must be in Codex home directory` + paginated fork + `sessions` 软链接 | 未找到公开报告 | 没有 maintainer 回复、workaround 或计划修复。 |
| 直接触发 | [PR #36950](https://github.com/openai/codex/pull/36950)，2026-08-04 合并 | 已发布于 v0.147.0 | TUI 开始为非 ephemeral 新会话请求 paginated，并让 fork/backtrack 走分页历史。 |
| 实现前提 | [PR #35220](https://github.com/openai/codex/pull/35220)，2026-07-24 合并 | 已合并 | paginated fork 以 rollout lineage 引用父历史，并在建立引用前执行 Codex-home containment 检查。 |
| 同类软链接问题 | [Issue #21898](https://github.com/openai/codex/issues/21898)，2026-05-09 创建 | Open | `thread/resume` 把软链接路径和 realpath 当成不同 rollout；2026-05-20 评论还给出整个 `~/.codex` 为软链接时的第一方 Desktop 复现。它是 raw path equality 问题，不是本次 canonical containment。 |
| 同一错误族 | [Issue #33815](https://github.com/openai/codex/issues/33815)，2026-07-17 创建 | Open | 切换 `CODEX_HOME` 后 archive 旧 home 的 rollout，报 `must be in sessions directory`；明确点名 `scoped_rollout_path`。它是跨 home archive，不是 fork。 |
| 旧版近似错误 | [Issue #5290](https://github.com/openai/codex/issues/5290)，2025-10-17 创建 | 2025-11-25 closed/completed | Windows 上合法 rollout 被误判为不在 sessions；维护者只说“早已修好”，没有关联到 v0.147 或软链接 fork。 |
| 同版本 fork 回归 | [Issue #37421](https://github.com/openai/codex/issues/37421)，2026-08-07 创建 | Open | v0.147 Esc-Esc branch 报 selected prompt not found；评论将其联系到 #36950。它确认 paginated TUI fork 另有回归，但错误和根因均不同。 |

## 上游意图与 containment 检查

公开材料没有维护者明确说明“禁止 `sessions` 目录指向 `CODEX_HOME` 外部”的安全理由，
所以不能把它说成已确认的安全政策。能够确认的是：

- `scoped_rollout_path` 最初随 2026-04-15 的
  [PR #17892](https://github.com/openai/codex/pull/17892) 进入 thread store，用于 archive/
  unarchive 的路径校验；这些路径随后会被 rename。它同时核对 canonical 根目录、
  canonical rollout 和带 thread id 的文件名。把它理解为防止文件操作越出存储根的
  containment/integrity guard 是**源码推断**，不是维护者原话。
- [PR #35220](https://github.com/openai/codex/pull/35220) 把同一 helper 用到 paginated
  fork，因为 fork 会持久引用父 rollout，并明确要求在成为引用前 materialize 压缩文件、
  与 archive/delete 协调。这里检查的是整个 `CODEX_HOME`，以同时容纳 active 与 archived
  lineage；顶层 `sessions` 单独跳出 home 因而失败。
- 维护者在另一个问题中明确表示不同的 `CODEX_HOME` 按设计是“不同且独立”的 Codex home，
  不打算让 auth 在 homes 间隐式共享
  ([#15410 maintainer comment](https://github.com/openai/codex/issues/15410#issuecomment-4104131307))。
  这支持“rollout 属于一个 home”的总体模型，但没有直接回答子目录软链接是否应受支持。

## 是否能关闭 paginated history

普通 TUI 没有公开的 config 或 CLI 开关。v0.147 的 app-server 协议仍允许调用方显式请求
`historyMode: legacy`，并且 store 在调用方不指定且历史没有已持久化模式时仍默认 legacy
([枚举默认值](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/protocol/src/protocol.rs#L697-L704)，
[store 默认值](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/thread-store/src/store.rs#L51-L57))；
但官方 TUI 的新线程构造器硬编码 paginated，没有把这个选择暴露给用户。因此：

- app-server 第三方客户端理论上可继续显式创建 legacy thread；
- 官方 TUI 用户无法靠 `config.toml` 恢复 legacy 新会话；
- 已写成 paginated 的 rollout 不会因为降级 CLI 自动变回 legacy。

上游方向也不是回退：v0.147 同时包含把 legacy rollout 单向转换为 paginated 的
[PR #37175](https://github.com/openai/codex/pull/37175)。随后 2026-08-07 合并、尚未进入
v0.147 tag 的 [PR #37348](https://github.com/openai/codex/pull/37348) 又加入手工迁移命令和
**默认关闭**的后台迁移 feature。它没有改 containment 检查，也不是本问题的计划修复。

## 只同步 JSONL 时的跨机器 resume

以下结论针对 `rust-v0.147.0`：B 主机只把 `$CODEX_HOME/sessions` 下的 rollout JSONL
同步到 A 主机，A 保留自己的 SQLite。官方文档只承诺 `codex resume` 可以通过 UUID 或
session name 恢复，并没有描述 JSONL/SQLite 的恢复细节
([CLI reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli#codex-resume))；
下面的细节来自上游源码。

### 两类 SQLite 数据

v0.147 至少要区分两份数据库：

- `state_5.sqlite` 保存 thread metadata 和 rollout path，供 picker、按 cwd/provider/source
  过滤和名称查询使用；
- `thread_history_1.sqlite` 保存 paginated turns/items 及 projection checkpoint。源码明确将
  后者称为可重建的 paginated thread-history database
  ([filenames](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/state/src/sqlite.rs#L33-L34)，
  [runtime comment](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/state/src/runtime.rs#L318-L323))。

JSONL 仍是 canonical history。paginated 写入先落 JSONL，再增量投影到 SQLite；投影允许
落后，但不能领先 JSONL
([live writer](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/thread-store/src/local/live_writer.rs#L285-L318))。

### `codex resume` picker：会扫描，但不是每次都扫描

本地 picker 首先发送 `useStateDbOnly: true`，只查询 A 主机自己的 `state_5.sqlite`
([picker setup](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/tui/src/resume_picker.rs#L380-L399))。
只有初始 DB 页面出错或返回零行时，它才改用 store-default 的 scan-and-repair 路径；只要
SQLite 返回了任意行，SQLite pagination 就被视为 authoritative，不再扫描 sessions
([fallback condition](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/tui/src/resume_picker.rs#L1448-L1483))。

因此，新同步到 A 的 JSONL **不保证出现在无参数 `codex resume` 的列表中**：

- A 的 state DB 是刚创建的或 backfill 尚未完成时，startup backfill 会扫描 sessions，
  JSONL 通常会被索引并列出；
- A 的 backfill 已标记 complete 时，后续启动直接通过 gate，不会因为 Mutagen 新增了文件而
  再做全量 startup backfill
  ([backfill gate](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/rollout/src/state_db.rs#L130-L167))；
- 如果 picker 的 DB 首屏因当前 cwd/provider/source 过滤而为空，它会 fallback 扫描并 repair，
  此时同步来的 JSONL 可以被发现；如果 DB 首屏已有别的会话，则缺失行不会触发扫描；
- `--all` 只取消 cwd 范围限制，并不强制 filesystem scan。它反而更容易让 DB 首屏非空；
  `--last --all` 也先接受 DB 找到的第一个有效路径，不会比较一次 filesystem scan 是否有
  更新的外来 rollout
  ([latest lookup](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/tui/src/lib.rs#L662-L690))。

另外，默认 picker 会按当前 cwd 过滤。B 写入 JSONL 的 cwd 与 A 不同，即使它已经入库，也要
使用 `--all` 才容易看到；resume 后 TUI 会按 `tui.resume_cwd` 规则处理保存 cwd 与当前 cwd
的差异。

### `codex resume <session_id>`：DB miss 后会查 JSONL

UUID 路径与 picker 不同。TUI 对 UUID 直接调用 metadata-only `thread/read`
([UUID lookup](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/tui/src/lib.rs#L626-L657))。
local thread store 在 state DB 查不到 rollout path 时，会递归扫描 `sessions` 中带 UUID 的
rollout 文件名；找到后校验 session metadata，并用 rollout 内容 read-repair 缺失的
`state_5.sqlite` 行
([filesystem fallback](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/rollout/src/list.rs#L1332-L1493)，
[read-repair](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/rollout/src/state_db.rs#L594-L655))。

所以，只要同步已经完成、JSONL 位于当前 `CODEX_HOME/sessions`、文件名和 `session_meta.id`
正确，且不是 archived session，`codex resume <session_id>` 在 A 上应能定位它。成功一次后，
metadata row 已补入 A 的 state DB，之后更可能出现在 picker 中。

### paginated projection 如何恢复

对普通的 root paginated session（`history_base = None`），cold resume 读取 JSONL 来重建最新
model context；重新打开 writer 后，app-server 会执行一次 persist。若本机没有 projection
checkpoint，materializer 从 byte offset 0 读取完整 rollout 并重建当前 thread 的
`thread_history_1.sqlite`
([model-context scan](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/thread-store/src/local/model_context.rs#L26-L71)，
[materializer](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/thread-store/src/local/thread_history_materialization.rs#L19-L69))。
因此 root session 的 SQLite history projection 不需要跨机器同步。上游已有集成测试从一份
cold root paginated JSONL 开始，在新 app-server 中执行 `thread/resume`，随后成功通过
`thread/turns/list` 读出重建的 projection
([test](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/app-server/tests/suite/v2/thread_resume.rs#L2402-L2490))。

如果 A 已经投影过该 thread，之后同步来的 JSONL 只是对原文件追加了完整新行，重新 resume
仍会补上新对话。projection state 记录下一次读取的 byte offset 和 ordinal；materializer 从该
offset 读取当前 EOF 之间的完整行并推进 checkpoint，而不是因为 SQLite 已有记录就跳过 JSONL。
resume 打开 live writer 后还会先执行一次 persist/materialize，再从 SQLite 读取返回给 TUI 的
paginated turns
([incremental materializer](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/thread-store/src/local/thread_history_materialization.rs#L19-L69)，
[resume ordering](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/app-server/src/request_processors/thread_processor.rs#L3260-L3290))。
上游的 `next_write_catches_up_unprojected_durable_suffix` 测试直接覆盖了 checkpoint 落后于
durable JSONL suffix 的场景；本次调查在 v0.147.0 上单独运行该测试，结果为 1 passed
([test source](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/thread-store/src/local/thread_history_materialization_tests.rs#L1509-L1590))。

这个增量恢复以 rollout 保持 append-only 为前提。materializer 不会重新校验 checkpoint 之前
的内容：如果同步工具把既有前缀改写为另一条历史，即使文件长度没有变化，旧 SQLite 行也不会
被重建；如果文件长度小于 checkpoint，则会报 `durable rollout shrank before projection`；如果
新 suffix 的 ordinal 与 checkpoint 不连续，也会拒绝推进 projection。此时模型上下文仍可能
直接从当前 JSONL 读到新内容，而 TUI transcript 继续显示旧 SQLite 行，形成可见不一致。因此
跨机器切换必须是顺序 handoff，并保证 B 在 A 的完整最新 JSONL 上继续追加，不能让 A、B 从
同一旧前缀分别写出两条分支后再交给 Mutagen 合并或覆盖。

fork/branch 产生的 paginated child 不同。child JSONL 通过 `history_base` 指向父 rollout 的
线程、ordinal 和 byte offset，不是自包含历史。恢复最新 model context 时会解析整个 rollout
lineage 并直接反向扫描各段 JSONL，所以所有被引用的 ancestor rollout 都必须已同步到 A；
缺任一父文件会导致恢复失败
([lineage model scan](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/thread-store/src/local/model_context.rs#L61-L68)，
[lineage resolver](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/thread-store/src/local/rollout_lineage.rs#L57-L128))。

v0.147 的 cold-resume 路径会投影当前 child rollout，但没有看到它同时逐段 materialize 所有
ancestor rollout。由此推断：只同步 JSONL 后直接恢复 child，模型上下文可以从完整 lineage
重建，但 TUI 通过 `thread_history_1.sqlite` 分页展示的 inherited transcript 可能暂时缺少父段；
这是源码推断，现有跨-home 测试只覆盖 root paginated rollout，没有覆盖全新 SQLite 上的
fork lineage。执行非 latest 的 paginated fork 时，另一路代码会显式 materialize ancestor
segments，但不能把该行为外推为普通 resume 的保证
([fork preparation](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/thread-store/src/local/paginated_fork.rs#L18-L69))。

本次调查还在 `rust-v0.147.0` checkout 上运行了
`split_homes_support_backfill_listing_and_paginated_history`。该测试把 paginated JSONL 和
SQLite 放在不同 home，验证 fresh state DB 的 startup backfill 能索引 JSONL，并让
state-DB-only listing 与 paginated history 查询成功；结果为 1 passed。它直接覆盖 fresh DB
场景，但不覆盖 backfill 已 complete 后新同步文件的增量发现，也不覆盖 child lineage。

### 跨机器使用的边界

- 不要通过 Mutagen 同步 live SQLite/WAL 文件；当前设计把 history projection 当作可从 JSONL
  重建的本机视图。
- 必须同步完整 sessions tree，而不只是目标 child 文件，才能保留 paginated lineage。
- 应采用单写者 handoff：A、B 不要同时 resume 并追加同一个 rollout。writer lock 是每台主机
  本地的，不能跨 Mutagen 协调；并发追加会变成同步冲突，而不是安全的多主写入。
- paginated 的一部分 display metadata 是 SQLite-only；只同步 JSONL 可恢复 canonical 对话，
  但名称、section、recency、后续 metadata update 等不保证跨机器完整保留
  ([metadata comment](https://github.com/openai/codex/blob/rust-v0.147.0/codex-rs/rollout/src/metadata.rs#L270-L278))。

## 上游已有 workaround 与当前判断

精确 fork 错误没有上游发布的 workaround。最接近的是 #33815 对跨-home archive 的建议：
临时把 `CODEX_HOME` 恢复为 rollout 所属的旧 home，或仅对一次 `codex archive` 覆盖
`CODEX_HOME` ([issue 的 Workarounds](https://github.com/openai/codex/issues/33815))。
这与本机已验证的“让 `CODEX_HOME` 指向 sessions 实际父目录”原理相同，但上游只讨论了
archive，不能声称官方验证过 fork。

当前最可靠的判断是：

- v0.147 只是把既有的 paginated fork + containment 路径暴露给所有新 TUI 会话；
- 上游已知“软链接/realpath 等价性”和“rollout 在当前 home 外”的两类路径问题，但尚未把
  它们统一处理；
- 调查时 `main` 仍保留原检查，没有相关 open PR 或 maintainer 承诺；
- 若要提交上游 issue，应作为新的精确回归报告，引用 #36950、#35220、#21898 和 #33815，
  并强调“只有 `sessions` 子目录是软链接，canonical rollout 因而落在 canonical
  `CODEX_HOME` 外”，避免被误判为 #5290 或 #37421 的重复。

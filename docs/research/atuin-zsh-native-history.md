# zsh 传统 ↑/↓ 使用 Atuin history DB 的方案

> 调查日期：2026-07-31，2026-08-01 补充上下文历史验证。已通过 GitHub REST API 分页核对
> [`atuinsh/atuin#798`](https://github.com/atuinsh/atuin/issues/798)
> 的 issue 本文、40/40 条评论和 128 个 timeline 事件。源码结论同时对照了本仓库当前使用的
> Atuin 18.15.2 及调查时最新稳定版 18.18.1。

## 结论

若还要求 ↑/↓ 根据当前目录或 Git workspace 过滤，最佳方向不是启动时快照，而是
**每个 ZLE 导航周期首次按 ↑ 时，从 Atuin 批量查询一页上下文结果；本轮后续 ↑/↓
只在 zsh 数组中移动**。这保留了 Atuin DB 中的 cwd 与同步数据，也避免逐键启动
Atuin 进程。完整设计和验证见下文“上下文历史补充结论”。

对更窄的目标——“**保留 zsh 原生的行内 ↑/↓ 和编辑体验，但只要求启动时的全局
历史数据来自 Atuin DB**”——issue 后期的“启动时把 Atuin 快照导入 zsh 原生
history ring”仍是最简单的方案。对本仓库的 Atuin 18.15.2，应用
Atuin 18.5 后的 NUL 分隔输出保留多行 command，再用 zsh `print -S` 逐条加入原生
history：

```zsh
unset HISTFILE
eval "$(atuin init zsh --disable-up-arrow)"

while IFS= read -r -d $'\0' cmd; do
  print -S -- "$cmd"
done < <(
  atuin search \
    --cmd-only \
    --print0 \
    --filter-mode global \
    --include-duplicates \
    --author '$all-user' \
    --limit 10000
)
unset cmd
```

这是 [fyxw 的原始 `fc -R` 方案](https://github.com/atuinsh/atuin/issues/798#issuecomment-3262253321)
的无损多行版；原评论的核心三行是：

```zsh
unset HISTFILE
eval "$(atuin init zsh --disable-up-arrow)"
fc -R =(atuin search --cmd-only --limit 100)
```

[`--print0` 由 PR #2562 加入](https://github.com/atuinsh/atuin/pull/2562)，专门用于正确分隔
多行输出；[zsh `print -S` 的官方语义](https://zsh.sourceforge.io/Doc/Release/Shell-Builtin-Commands.html#index-print)
是把单个参数当作完整 shell command line 解析并放入 history list，所以比让
`fc -R` 把 command 内换行误认成记录边界更稳妥。建议先导入 10,000 条：
实测启动成本约 0.21 s，足以覆盖日常 ↑/↓ 使用；如果愿意承担更长启动时间，
可改为本仓库已设置的 `--limit "$SAVEHIST"` (`SAVEHIST=100000`)。原 issue 方案固定为 100。
[rseymour 后续确认](https://github.com/atuinsh/atuin/issues/798#issuecomment-3445678720)
↑/↓、Ctrl-P/N 和 Ctrl-A/E 都按预期工作。

关键在于职责分开：

- `--disable-up-arrow` 只阻止 Atuin 绑定 ↑，Ctrl-R 和 Atuin 的 `preexec`/`precmd`
  历史记录 hook 仍然存在。官方文档的配置就是
  [`atuin init zsh --disable-up-arrow`](https://docs.atuin.sh/main/configuration/key-binding/#disable-up-arrow)；
  18.15.2 源码也显示记录 hook 始终注册，只有按键绑定受开关影响
  ([zsh hook](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin/src/shell/atuin.zsh#L34-L52),
  [binding](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin/src/command/client/init/zsh.rs#L14-L38))。
- `atuin search` 在 DB 中先按 newest-first 选出最近 `N` 条
  ([database.rs](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin-client/src/database.rs#L487-L513))，
  非交互输出再把这批结果反转为 old-to-new
  ([search.rs](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin/src/command/client/search.rs#L292-L299),
  [history.rs](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin/src/command/client/history.rs#L185-L218))。
  这一顺序正好适合 zsh `fc -R` 按文件顺序追加历史；**不要加
  `--reverse`**，否则会变成选择整库最旧的 `N` 条。
- ↑/↓ 之后走的是 zsh 原生 widget，不需要再维护索引、Ctrl-C 重置、当前
  buffer 和多行光标等自定义 ZLE 状态。每个 shell 只在启动时查一次 Atuin，
  不会遇到大数据库中每按一次 ↑ 都启动查询的延迟。

这个方案的边界也很明确：

- 它是**启动时快照**。其他终端在本 shell 启动后新执行或新同步的命令，
  不会实时进入当前 zsh 的 ↑ 列表；当前 shell 自己后续执行的命令仍会自然
  加入 zsh 内存 history，并由 Atuin hook 写入 DB。
- `atuin search` 默认按 command **全局去重**；源码只有在 `--include-duplicates` 时才不
  `group by command`
  ([database.rs](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin-client/src/database.rs#L487-L502))。
  本仓库的 zsh `ignoreDups = true` 只忽略相邻重复，不等于 Atuin 的全局去重；
  为忠实保留 DB event stream，推荐版显式使用 `--include-duplicates`。
- Atuin DB 现在还可含有 agent-authored 历史，而传统 zsh history 的范围是人类用户
  在 shell 中执行的命令。`--author '$all-user'` 是 Atuin 的特殊 author filter，
  会排除已知 agent 名称；当前源码对 `$all-user`/`$all-agent` 的处理见
  [database.rs](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin-client/src/database.rs#L91-L120)。
- 原始 `fc -R` 一行版的 `--cmd-only` 用换行分隔记录，会把命令本身的换行错当成
  history event 边界。上面的 `--print0` + `read -d $'\0'` + `print -S` 正是
  对这一限制的改良；Atuin 选项源码见
  [search.rs](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin/src/command/client/search.rs#L92-L99)。
- `unset HISTFILE` 阻止当前 shell 继续使用 zsh 文件作为持久库，但不会删除
  已经读入 zsh 内存的历史。配置顺序应保证原生 history file 在此前没有被框架
  读入；否则当前列表是“旧 zsh history + Atuin 快照”，而不是 DB-only。

## 实测结果

除了读源码，调查还用隔离 Atuin DB 的 7+ 条构造样本和真实 zsh PTY 实测了两种导入法。
以下是本机实测，不是上游性能承诺：

- issue 原始 `fc -R` 的 old-to-new 导入顺序正确，真实 ↑/↓ 会先取最新记录再向旧记录移动；
- 原始 `fc -R` 会把一条构造的两行 command 拆成两个 history event；默认
  Atuin search 还会全局去重，并混入 agent-authored history；
- `--print0` + `print -S` 保住了多行，`--include-duplicates` 保住非相邻重复，
  `--author '$all-user'` 排除了 agent history；真实 PTY 中的 ↑/↓ 将该多行记录保留为
  一个可编辑 buffer；
- 当前真实 DB 上，逐键方案的 100 次单条查询共约 2.64 s，即约 26 ms/键；
  NUL 快照导入 10,000 条约 0.21 s，导入全部 44,552 条约 1.12 s。

实测同样确认了快照边界：外部会话在导入后新写入 Atuin DB 的命令，已打开
shell 的 ↑ 不可见；重新导入或新开 shell 后可见。tyalie widget 因为每键查 DB，可实时看到。

## 什么时候选实时 ZLE widget

只有当以下任一需求优先级高于延迟和简单性时，才建议使用
[tyalie 的改进 zsh widget](https://github.com/atuinsh/atuin/issues/798#issuecomment-1761546263)：

- 当前 shell 必须立刻看到其他终端/同步刚写入 Atuin DB 的命令；
- ↑ 需要以当前 buffer 为 prefix；
- 需要 Atuin 的 `directory`、`session` 等 filter mode；
- 必须无损返回多行 command buffer。

该 widget 是 Nezteb 早期脚本的完整化版：用上一个结果 buffer 检测 Ctrl-C
或用户编辑并重置 offset，先处理多行内的上下移动，再执行
`atuin search --limit 1 --offset N --search-mode prefix`。它默认是 `session`；要浏览
完整 Atuin DB，必须改成：

```zsh
ATUIN_HISTORY_SEARCH_FILTER_MODE=global
```

代价是每次 ↑/↓ 都启动一个 `atuin search` 进程。直接由这个 gist 引出的
[性能 issue #2367](https://github.com/atuinsh/atuin/issues/2367)
报告：约 24 万条历史时，空查询的单次查询约 250 ms，带前缀约 30 ms。
因此它是“实时/filter 语义优先”时的选择，不是默认最优解。

## 其他方案为何不是答案

| 方案 | 问题 |
|---|---|
| 只用 `atuin init zsh --disable-up-arrow` | ↑ 确实恢复 zsh 原生行为，但数据源是 zsh history，不是 Atuin DB；这是 issue 一开始就被反复纠正的误解。 |
| `inline_height = 1` 或很小的 inline height | 仍是 TUI，内容显示在 prompt 下一行，不是 zsh 原位替换 buffer。有用户实测 `1` 无特殊处理，`3` 只是少一些视觉干扰 ([`inline_height = 3`](https://github.com/atuinsh/atuin/issues/798#issuecomment-2727053776), [`inline_height = 1`](https://github.com/atuinsh/atuin/issues/798#issuecomment-2833409840))。 |
| `filter_mode_shell_up_key_binding` | 只影响 Atuin 的 ↑ TUI 调用，不会让 `--disable-up-arrow` 后的 zsh 原生 history 读 Atuin DB；[维护者已承认误读](https://github.com/atuinsh/atuin/issues/798#issuecomment-1964560600)。 |
| Nezteb 原始 zsh gist | 证明了 `--offset` 方向可行，但 Ctrl-C 重置失败、没有完整的 buffer/多行状态处理；tyalie 版已针对这些问题改进。 |
| `--reverse --offset ...` | `--reverse` 的官方语义是 oldest-first：[引入它的 PR #862](https://github.com/atuinsh/atuin/pull/862) 示例是查“最旧的 cargo 命令”。#798 中有一条 2023 评论将其示例解释为 last/second-to-last，与 PR 和当前源码不一致，不应照搬。 |
| 当前 TUI v2 PR | [PR #3796](https://github.com/atuinsh/atuin/pull/3796) 在 2026-07-30 把 #798 列入众多 goals，但它是 open draft，当前 diff 主体是新 TUI crate；不是已发布的 classic zsh cycling。 |

## 版本和本仓库现状

维护者 2023 年说过“不太可能进 v17，也许是 v18”
([ellie 的评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1767582886))，
但这是讨论意向，不是发布承诺。到 2026-07-31，#798 仍为 open；Atuin 18.15.2
和最新稳定版 18.18.1 的 zsh integration 仍然只提供打开 TUI 的
`atuin-up-search{,-viins,-vicmd}` widgets，没有 classic-inline widget。18.18.1 虽对 init
内部结构和 shell hook 有修改，但 ↑ 仍绑定到同一类 TUI widget
([18.18.1 binding 源码](https://github.com/atuinsh/atuin/blob/v18.18.1/crates/atuin/src/command/client/init/zsh.rs#L20-L37))。

本次修改前，本仓库的行为也不等于目标行为：

- `_atuin_smart_up` 第一次 ↑ 读取 zsh history，1 秒内再按才打开 Atuin TUI；
- Atuin 初始化不传 `--disable-up-arrow`，再由 smart widget 覆盖各 keymap。

本次修改将实现集中到独立的
[`atuin-context-history`](../../home-manager/zsh-custom/plugins/atuin-context-history/atuin-context-history.plugin.zsh)
插件。[`shell.nix`](../../home-manager/shell.nix) 仅在 zsh-vi-mode `after_init` 中依次执行
`atuin init zsh --disable-up-arrow` 和插件安装函数；通用 `keybind` 插件不再包含 Atuin
状态或绑定。插件先从 Atuin DB 批量查询 directory + prefix 结果，不足 200 条时再用
global + prefix 结果补足，在 vi/emacs keymap 内原位轮转，并在新 prompt、编辑、移动
光标、切换目录或进入 Ctrl-R TUI 时丢弃旧批次。

2026-03 有一位用户报告 Atuin Hex 会覆盖 `--disable-up-arrow`
([评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-4103348823))，
但 issue 内没有维护者确认、复现步骤或修复结论；对本仓库的 Atuin 18.15.2 配置不应
把这条单独报告当作已证实的阻断。

## 上下文历史补充结论（2026-08-01）

### 当前即可实现的最佳形状

首次 ↑ 固定当前的 `BUFFER`、`CURSOR`、`PWD` 和 `LBUFFER`，先执行：

```zsh
atuin search \
  --cmd-only \
  --print0 \
  --filter-mode directory \
  --search-mode prefix \
  --author '$all-user' \
  --limit 200 \
  -- "$LBUFFER"
```

如果结果不足 200 条，再用相同参数执行一次 `--filter-mode global` 查询。ZLE widget
按命令去重，用 global 结果补足总数至 200 条，并把 directory 结果放在轮转顺序之前。
↑ 先从最新的 directory 记录向前移动，再进入 global 记录；↓ 反向移动，越过最新记录
时逐字恢复原 `BUFFER` 和 `CURSOR`。用户编辑、移动光标、切换 `PWD`、接受或取消命令后
丢弃本轮数组。Ctrl-R 继续使用 Atuin TUI。

不要使用社区脚本常见的 `--offset N --limit 1` 逐键查询：每个按键都产生进程和 DB
延迟；同步插入新记录还会使 offset 发生位移。一次批量查询既保持本轮顺序稳定，也让
首次按键之后的导航成为纯 zsh 内存操作。

### 实际验证

使用独立 Atuin 数据目录建立了 Git repo root、repo 子目录和 repo 外目录三组历史：

- 从子目录用 `directory + prefix` 查询，只返回该子目录记录；
- 从子目录用 `global + prefix` 查询，返回上述三个目录的记录，与 Ctrl-R 的初始范围一致；
- 合并时先轮转完 directory 记录，再轮转去重后的 global 记录；directory 已返回 200 条时
  不执行 global 查询；
- `--print0` 可由 zsh `${(@0)...}` 无损解析，多行命令保持为一个数组元素。

首次 ↑ 付出最多两次批量查询成本，之后 ↑/↓ 不再查询。该结果也解释了为什么逐键
offset widget 手感不佳。选择 `directory` 和 `global` 还避免了 Atuin 18.15.2 将 Git
submodule 的相对 `.git` 指针解析为含 `..` 的 workspace 前缀、进而匹配不到规范化历史
路径的问题。

### 现有插件的边界

本仓库 2026-01-04 曾启用 `zsh-history-substring-search`，三天后在启用 Atuin ↑ 时移除。
它的状态机、多行和边界行为值得复用，但数据源硬编码为 zsh `$history`，没有 cwd、host、
session、workspace 或可替换 backend。`zsh-histdb` 与 `per-directory-history` 能保存本地
目录上下文，却会引入 Atuin 之外的第二套历史数据库/文件，不能直接消费 Atuin 的跨主机
同步。因此应写一个小型 Atuin-backed ZLE adapter，而不是叠加这些插件。

### Atuin 原生实现建议

第一版应增加一个显式模式，例如 `up_arrow_mode = "classic"`，并复用现有
`filter_mode_shell_up_key_binding` 与 `search_mode_shell_up_key_binding`。Rust 侧负责按当前
`Context` 查询、过滤 user-authored history、确定时间顺序，并以 NUL 协议一次返回最多
200 条；zsh 侧只负责 ZLE buffer、cursor、多行与数组索引。无需修改 daemon，也不应把
fuzzy/frecency daemon index 用作传统时间顺序历史。

当前 `directory` 是绝对 `cwd` 相等，`workspace` 是当前 Git root 的绝对路径前缀。
因此两台主机 checkout 路径不同时，同一 repo 的同步记录不会互相命中上下文过滤；它们
仍可由 global Ctrl-R 找到。真正的跨主机 workspace 上下文需要另一个同步数据功能：
为 history 增加稳定的 `workspace_id` 与 repo-relative directory。旧记录无法可靠反推该
身份，不应使用 basename 等猜测性匹配。

## #798 的40 条评论完整时序

| # | 日期 | 作者 | 内容与结论 |
|---:|---|---|---|
| 1 | 2023-03-22 | RafaelKr | 最初误解为“禁用 ↑”，指向 key-binding 配置。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1479277487) |
| 2 | 2023-03-22 | endigma | 纠正：`--disable-up-arrow` 会让 ↑ 不再使用 Atuin DB；要的是传统行内 ↑/↓，但历史源为 Atuin。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1479640988) |
| 3 | 2023-03-22 | conradludgate | 提到 #648 inline view，但它仍是搜索 UI。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1479677165) |
| 4 | 2023-03-22 | endigma | 再次澄清：不想显示/搜索历史，只想在 prompt 原位轮转命令。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1480230528) |
| 5 | 2023-03-22 | conradludgate | 确认理解，表示检查是否容易实现。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1480244126) |
| 6 | 2023-03-23 | RafaelKr | zsh + OMZ 下用 `--disable-up-arrow`，`.zsh_history` 和 DB 都记录，原生 ↑ 仍可用；但 ↑ 实际读的仍是 zsh history。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1480852365) |
| 7 | 2023-03-23 | endigma | 明确纠正：原生 ↑ 用 shell history，不是 Atuin DB。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1481083480) |
| 8 | 2023-03-30 | arcuru | #825 加入 `--offset` 后，shell script 已具备实现基础。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1490551240) |
| 9 | 2023-04-01 | endigma | 同意；难点是维护当前索引及 shell 内部状态，仍希望内建。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1492800134) |
| 10 | 2023-04-01 | arcuru | 提供 fish 原型；filter mode 是优势，但边角粗糙，建议先做自定义集成文档。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1493172263) |
| 11 | 2023-04-02 | endigma | 建议用 bind-r/bind-up 开关，并询问能否把当前 buffer 当查询。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1493410837) |
| 12 | 2023-04-02 | arcuru | 理想语义是按自定义 filter/search mode，以当前 buffer 为可选前缀轮转最近结果。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1493454863) |
| 13 | 2023-04-14 | ellie | 认可先写 custom shell integrations 文档；提到 #826 的 zsh 工作，未来或可正式集成。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1509159616) |
| 14 | 2023-04-15 | mentalisttraceur | 建议用负 offset 和计数器实现 ↑/↓，执行或 Ctrl-C 后重置；负 offset 后来并未实现。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1509494561) |
| 15 | 2023-05-05 | Nezteb | 发布首个 zsh 自定义实现，逐次查询 Atuin DB。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1535569798) |
| 16 | 2023-05-05 | takac | 说明负 offset 未实现，给出 `--reverse --offset` 示例；其对 last/second-to-last 的解释与 #862 及当前 oldest-first 语义冲突。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1535987198) |
| 17 | 2023-06-27 | ekristen | 支持内建，并希望用 config switch 控制。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1609835369) |
| 18 | 2023-08-09 | alextremblay | 提供 bash 版；空 buffer 轮转 Atuin history，非空时打开按前缀过滤的交互搜索。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1670582389) |
| 19 | 2023-10-13 | tyalie | 改进 Nezteb 脚本；保存上一结果 buffer 以检测 Ctrl-C/外部编辑后重置，并处理 multiline。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1761546263) |
| 20 | 2023-10-18 | ellie | 倾向正式加入并由配置控制，称“不太可能进 v17，也许 v18”；列出 zsh/fish/bash 社区实现并邀请贡献。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1767582886) |
| 21 | 2023-10-25 | arcuru | 当时 Nu 受 shell 能力限制；建议在现有 init script 内加函数后切换绑定；个人因 `enter_accept` 转而偏好 TUI。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1780143646) |
| 22 | 2023-11-02 | alextremblay | 计划把 tyalie 的 zsh 改进移植到 bash。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1790888026) |
| 23 | 2023-11-02 | alextremblay | 希望显式用 `classic_inline = true`，不要让 `inline_height = 1` 隐式触发。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1790892121) |
| 24 | 2024-02-26 | cohml | 指出 directory filter 用例；原生 shell ↑ 是 global，无法快速使用 Atuin 的目录过滤。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1964485526) |
| 25 | 2024-02-26 | ellie | 最初回答可用 `filter_mode_shell_up_key_binding = "session"`。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1964511976) |
| 26 | 2024-02-26 | cohml | 纠正：该设置只控制 ↑ 打开的 Atuin TUI，不控制 `--disable-up-arrow` 后的原生 ↑。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1964546446) |
| 27 | 2024-02-26 | ellie | 承认误读。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1964560600) |
| 28 | 2024-03-02 | remmycat | 讨论 Nushell 仍有 commandline 替换换行问题，长期或需 Nushell 提供外部 history API。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-1974773630) |
| 29 | 2024-06-20 | atuin-bot | 链接 Atuin Community 相关讨论。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-2181121591) |
| 30 | 2024-08-02 | GDYendell | 希望以光标左侧内容为前缀继续 ↑ 搜索，并分别配置 ↑ 与 Ctrl-R 的 inline height。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-2264926171) |
| 31 | 2024-08-26 | davidebenato | 认为传统单行方式更适合快速工作流，信息负担更小。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-2310239299) |
| 32 | 2024-09-08 | kboshold | 提供 fish 实现，明确称尚不最优。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-2336668026) |
| 33 | 2025-03-15 | maphew | 折中设置 `inline_height = 3` 减少视觉干扰；仍是 TUI。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-2727053776) |
| 34 | 2025-04-27 | laundmo | 确认 `inline_height = 1` 没有 native handling，命令仍显示在 prompt 下一行。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-2833409840) |
| 35 | 2025-09-06 | fyxw | 给出最简 zsh 方案：`unset HISTFILE`，禁用 Atuin ↑ 绑定，再用 `fc -R =(atuin search --cmd-only --limit 100)` 把 Atuin DB 快照读入 zsh history。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-3262253321) |
| 36 | 2025-09-19 | wak-google | 以 Elvish 为 UX 参照：Ctrl-R 用历史界面，↑ 原位替换 command line。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-3313599206) |
| 37 | 2025-10-25 | rseymour | 明确复验 fyxw 方案，称 ↑/↓、Ctrl-P/N、Ctrl-A/E 均正常。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-3445678720) |
| 38 | 2025-12-13 | nadeemkhedr | fish 中找不到类似 fyxw 的简单方案。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-3649782389) |
| 39 | 2025-12-22 | khimaros | 称 alextremblay 的 bash gist 是使用一年多后的最佳 bash 方案。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-3684564454) |
| 40 | 2026-03-21 | dmd | 报告 Atuin Hex 会覆盖或破坏 `--disable-up-arrow`；issue 内没有维护者确认或修复结论。[评论](https://github.com/atuinsh/atuin/issues/798#issuecomment-4103348823) |

## Timeline 中有实质意义的非评论事件

- 2023-10-18：维护者添加 `enhancement`、`help wanted`。
- 2023-12 至 2024-03：被 [#1464](https://github.com/atuinsh/atuin/issues/1464)、
  [#1639](https://github.com/atuinsh/atuin/issues/1639)、
  [#51](https://github.com/atuinsh/atuin/issues/51)、
  [#1769](https://github.com/atuinsh/atuin/issues/1769)、
  [#1833](https://github.com/atuinsh/atuin/issues/1833)
  和 [PR #1789](https://github.com/atuinsh/atuin/pull/1789) 交叉引用。#1789 建议重组
  keybinding 配置并预留 #798 开关，但 PR 已关闭、未合并。
- 2024-08-21：[性能 issue #2367](https://github.com/atuinsh/atuin/issues/2367)
  直接引用 tyalie 脚本，给出逐键空查询的延迟数据。
- 2026-07-30：移除 `help wanted`，但 issue 没有关闭。
- 2026-07-30：open draft [TUI v2 PR #3796](https://github.com/atuinsh/atuin/pull/3796)
  把 #798 列入 goals；不等于 classic zsh cycling 已实现。
- 2026-07-31：相关 open issue [#3610](https://github.com/atuinsh/atuin/issues/3610)
  交叉引用 #798，它讨论的是极小 TUI + `invert=true` 时的方向，仍不是原生 zsh history。

# Hermes / Honcho 回答效果评估与模型验证

**只考虑回答效果，建议保留 Honcho。** 在原生 Markdown 记忆和真实 session 检索都可用的基线上，增加 Honcho 后，11 项内容生成任务的事实与约束落实得分从 **61.4 提高到 79.2**，完整合格产出从 **4/11 增加到 6/11**。22 道历史问答也显示正增量；差异题复跑基本保持原方向。

它的收益集中在补回具体约定、规格和遗漏需求，也确实会带回旧方案或遗漏关键条件。本次结果支持保留这项补充能力，不支持每轮、每个实例都会变好的结论。

评估日期：2026-11-06。只评估最终回答；费用、延迟、token 数和工具调用次数不进入保留决策。

以上主评估的 Honcho 后端使用 `gpt-6-luna`。后续升级 `gpt-6.1-terra` 的部署与功能验证见文末；主评估分数不应解释为 Terra 的评测结果。

## 比较的两组

| 条件 | 原生 Markdown 记忆 | 原生 session 检索 | Honcho |
| --- | --- | --- | --- |
| 基线 | 完整 `MEMORY.md`、`USER.md` | 实际调用线上版本的 `session_search`，可搜索、浏览和读取历史 | 无 |
| 增加 Honcho | 与基线相同 | 与基线相同 | 用户与 AI 画像自动召回，加只读 `honcho_profile`、`honcho_context`、`honcho_search`、`honcho_reasoning` |

两组统一使用当前部署的默认模型 `gpt-6.1-sol`、`low` 推理等级，使用相同的新会话问题。两组都明确允许主动检索历史，原生记忆内容和检索实现保持一致。

评估脚本复用了 `honcho` 的 API Key，账本按 Key 归类，因此两组最终回答模型的 Sol 调用也显示在 `honcho` 名下。2026-11-06 11:22–12:06（UTC+8）的 220 次成功 Sol（low）调用，与保存的 219 次评估调用及 1 次接口预检完全对应；这些记录不代表当时 Honcho 的后台模型从 Luna 切成了 Sol。

每个实例的原生记忆文件和完整 SQLite 历史库在运行前复制并冻结。Honcho 的自动召回也预先保存；显式工具读取线上当前数据，返回内容全部存档。评估不创建 Honcho peer、会话或消息，不写记忆，不修改线上配置。

## 题目与评分

22 道事实回顾题覆盖全部 11 个有真实用户需求历史的实例，每个实例两题。另为每个实例增加一道内容生成任务，共 11 道，要求按既有约束写出可用的简介、任务单、需求说明、目录或交代消息。两类任务分别报告结果。

问题都是现在新问的，不向模型提供标准答案或来源消息。标准答案以实际用户消息为依据，排除了助手自行归纳及后台系统通知；实体名称接受历史工具结果已核实的纠错，不因用户原先的同音别字扣分。

另四个实例没有编造题目：canary 是人工测试实例；两个实例只有固定回复、模型身份或生图部署验证；一个实例没有对话历史。

题目侧重跨会话事实、后来纠正的决定和持续约束，也包含原生记忆可以直接回答的对照题。它们是特意选择的记忆需求题，不能当作自然消息的随机样本。内容生成任务复用其中部分历史素材，不能把两组加起来当作 33 个独立的记忆事件。

评分在查看答案前确定：

- 每项必要事实记为正确 `1`、部分正确 `0.5`、缺失或错误 `0`；先换算每题百分制，再对题目等权平均。
- “整题正确”要求全部必要事实正确，且没有与用户原始证据明确冲突的断言。
- 内容生成任务还要求实际交付可用正文或清单；只复述事实、承诺稍后执行或违背明确格式要求不算完整交付。对“不要使用旧团队”等限制，自然地省略即可，不要求在正文重复否定句。
- 两名独立 AI 评审分别看到独立随机排序的 A/B 最终回答、问题及用户原始证据；不提供实验组别和工具轨迹。
- 胜负只依据实质正确性、完整性和用户要求遵循。单纯更长、措辞不同或检索更少均不算获胜。
- 上游失败、未生成最终答案和达到工具循环上限单列，不把它们伪装成已完成回答；如少数差异决定结论，再复跑这些题检查稳定性，保留首次和复跑结果。

## 结果

33 个配对任务均已生成完整最终回答，并经两名 AI 独立盲评。主结果使用每组的首次有效回答；两个首次运行因上游 502 未完成，按原输入补跑。另有 7 个配对任务重复生成，用于检查稳定性。总计评分 80 份最终回答。

### 内容生成：是否帮助产出可用文本

| 内容生成任务指标 | 原生记忆＋session 检索 | 再增加 Honcho |
| --- | ---: | ---: |
| 两评审平均事实与约束落实得分，满分 100 | 61.4 | 79.2 |
| 完整且事实正确的合格产出，两评审一致 | 4/11 | 6/11 |
| 交付了具体正文或清单，允许其中仍有事实错误 | 9/11 | 10/11 |
| 与原始用户证据明确冲突的回答，两评审一致 | 2/11 | 2/11 |

两位评审在 11 项任务的胜负上全部一致：**Honcho 4 胜、3 负、4 平**。平均得分增加 **17.8 分**，严格合格产出多 **2 项**。

收益较大的任务是材料纠错消息、产品打样说明和日志采集需求：增加 Honcho 后，具体材料名、配比与用途、存储规格和待比较工具更完整。负面任务包括把旧技术路线带回简介、误写已确定的模型口径，以及遗漏投资协议起草交代中的重要条件。

两组也有共同失败：工艺确认消息都未给出足够具体的工艺和颜色。这样的泛化文本不计为完成交付；不能只因已经生成文字便判定有效。

### 历史问答：能否正确恢复既有事实

| 事实回顾题指标 | 原生记忆＋session 检索 | 再增加 Honcho |
| --- | ---: | ---: |
| 两评审平均事实得分，满分 100 | 87.2 | 93.8 |
| 两评审均判定整题正确 | 13/22 | 17/22 |
| 与原始用户证据明确冲突的回答，两评审一致 | 6/22 | 2/22 |

两评审一致判定 Honcho 获胜 5 题、基线获胜 2 题、持平 12 题，另有 3 题在胜负上存在分歧。两位评审各自的 Honcho 胜／平／负分别为 `7/12/3` 和 `5/15/2`。这里的得分是必要事实完成度，不是对所有日常回答准确率的估计。

### 重复生成：差异能否重现

选择首次两位评审都判出实质胜负的 7 道历史问答，按相同输入重新生成两组答案；重新随机隐藏组别，再独立评分。

| 差异题复跑指标 | 原生记忆＋session 检索 | 再增加 Honcho |
| --- | ---: | ---: |
| 两评审平均事实得分 | 79.2 | 87.5 |
| 两评审均判定整题正确 | 2/7 | 5/7 |

复跑为 **Honcho 4 胜、2 负、1 平**，两位评审全部一致。**6/7 保持原胜负，1/7 从 Honcho 获胜变为持平，没有反向翻转。** 该子集专为复核原差异选择，不用于重新估计总体提升率，也没有取两次中表现较好的一次替换主结果。

## 结论的适用范围

这是使用真实原生检索实现和真实 Honcho 读取接口的受控工具循环，不是完整 Hermes 运行时。它直接比较最终回答，但不覆盖浏览网页、生成图片、编辑文档等完整任务。

现有 Markdown 记忆和历史消息可能已经包含过去使用 Honcho 的影响。本评估回答的是：在这些现有信息仍然保留时，**继续提供 Honcho 是否还能改善回答**，不是从零开始、长期使用与从未使用 Honcho 的因果实验。

为排除速度因素，Honcho 画像提前取好，不受线上首轮短等待窗口限制。因此这是对其可用记忆能力的充分利用；不能把观测结果直接视为线上每一轮都能兑现的收益。各原生快照已冻结，Honcho 显式工具读取期间仍可能有正常使用带来的更新。

## 接入机制与版本

本次核对的 Hermes 为 `v0.22.7`，提交 `b200f5bc60e31588ba2cb60e288029c4a54ba5fa`；Honcho 插件固定在 `e2d2aba182862deeb846e5cd4a30a41bce0ed82a`，已核对线上插件核心文件与该提交一致。部署使用 `memory.provider=honcho`，各实例独立 workspace、固定用户 peer，默认 dialectic 推理等级为 `high`。[插件打包](../../pkgs/honcho-plugin.nix)、[实例配置](../../nixos/optional/hermes-nspawn.nix)、[Guest 配置](../../nixos/optional/hermes-nspawn/guest.nix)

Hermes 原生 `MEMORY.md`、`USER.md` 由 `MemoryStore` 独立加载，Honcho 在其旁边增加外部记忆能力。`session_search` 直接查询本地 SQLite 历史，支持 FTS5 搜索、浏览和会话读取。因此，有效基线应保留原生记忆和历史检索。[初始化源码](https://github.com/NousResearch/hermes-agent/blob/b200f5bc60e31588ba2cb60e288029c4a54ba5fa/agent/agent_init.py#L1210-L1284)、[检索工具](https://github.com/NousResearch/hermes-agent/blob/b200f5bc60e31588ba2cb60e288029c4a54ba5fa/tools/session_search_tool.py#L665-L725)

Honcho 默认采用 `hybrid` 模式：自动召回加 `honcho_profile`、`honcho_search`、`honcho_context`、`honcho_reasoning`、`honcho_conclude` 五个工具。自动召回可包含会话摘要、用户与 AI 的画像和 card，以及异步 dialectic 补充；基础画像检索使用当前问题作为 `search_query`。本次评估只开放前四个读取工具。[召回实现](https://github.com/plastic-labs/honcho/blob/e2d2aba182862deeb846e5cd4a30a41bce0ed82a/hermes-plugin-honcho/session_context.py#L139-L197)、[工具定义](https://github.com/plastic-labs/honcho/blob/e2d2aba182862deeb846e5cd4a30a41bce0ed82a/hermes-plugin-honcho/tool_schemas.py)

解释历史数据时，有四个关键边界：

- system prompt 中的 `# Honcho Memory` 仅是静态说明；真正逐轮召回在 user 消息的 `<memory-context>` 中，字符串消息通过 `api_content` 保存实际发送文本。该块含有将记忆视为权威参考的提示，因此错误画像也可能影响回答。[消息组合与持久化](https://github.com/NousResearch/hermes-agent/blob/b200f5bc60e31588ba2cb60e288029c4a54ba5fa/agent/turn_context.py#L997-L1065)、[封装提示](https://github.com/NousResearch/hermes-agent/blob/b200f5bc60e31588ba2cb60e288029c4a54ba5fa/agent/memory_context.py#L193)
- 默认自动 dialectic 使用通用用户画像或会话提示，基础检索和推理补充的相关性应分别判断。后续轮次消费异步结果，可能落后当前话题；默认 600 字符只限制 dialectic 补充，基础画像的 `contextTokens` 默认未设上限。[dialectic 提示](https://github.com/plastic-labs/honcho/blob/e2d2aba182862deeb846e5cd4a30a41bce0ed82a/hermes-plugin-honcho/dialectic.py#L125-L187)、[配置默认值](https://github.com/plastic-labs/honcho/blob/e2d2aba182862deeb846e5cd4a30a41bce0ed82a/hermes-plugin-honcho/client.py#L296-L338)
- 带 `prefetch output truncated`、头尾预览和文件路径的消息，实际注入的是预览；磁盘完整版需要模型另行读取。当前固定版本在未启用 `memory.prefetch_spill_enabled` 时将阈值提高至至少 100000 字符，显式启用时默认阈值为 10000 字符，历史尺寸差异可能来自版本或配置变化。[截断阈值](https://github.com/NousResearch/hermes-agent/blob/b200f5bc60e31588ba2cb60e288029c4a54ba5fa/agent/memory_manager.py#L289-L299)、[落盘与预览](https://github.com/NousResearch/hermes-agent/blob/b200f5bc60e31588ba2cb60e288029c4a54ba5fa/tools/hook_output_spill.py#L24-L116)
- `sessions.system_prompt_hash` 是会话最近保存的快照，会被更新，不能据此证明逐轮的原生记忆状态。重放旧问题还可能受后续画像及先前助手回答影响。本次采用冻结原生记忆与历史后提出新问题的方式，测量当前状态下继续提供 Honcho 的增量。[快照更新](https://github.com/NousResearch/hermes-agent/blob/b200f5bc60e31588ba2cb60e288029c4a54ba5fa/hermes_state_sessions.py#L695-L704)

插件有默认关闭的注入日志，可通过 `logging=true` 或 `HONCHO_LOGGING=true` 记录完整召回、空结果原因与会话信息；本次未开启该线上日志。[注入审计实现](https://github.com/plastic-labs/honcho/blob/e2d2aba182862deeb846e5cd4a30a41bce0ed82a/hermes-plugin-honcho/__init__.py#L458-L490)

## 证据与复现

原始问题、用户证据、记忆快照、完整工具轨迹和回答含有私人对话，保存在宿主私有目录 `/home/yifan/.local/state/honcho-eval/2026-11-06/`，不进入仓库。逐题可阅读对照为该目录的 `answer-comparison.md`。

目录内有题库 `memory-benchmark.json`、执行脚本 `memory-benchmark-run.py`、执行协议 `memory-benchmark-protocol.json`、预先确定的评分规则 `scoring-protocol.json` 和逐次结果 `memory-benchmark-results.jsonl`。`quality-tasks/` 保存内容生成任务，`memory-stability-*` 保存独立复跑。三个汇总分别为 `recall-score-summary.json`、`quality-tasks/task-score-summary.json`、`stability-score-summary.json`；原生快照保存 SHA-256，金标准澄清保留 `gold-revision-log.json`。

## 后续模型升级：gpt-6.1-terra

2026-11-06 将 [Honcho 配置](../../nixos/optional/hermes-nspawn/honcho.nix) 中的统一模型从 `gpt-6-luna` 改为 `gpt-6.1-terra`，通过宿主 `just nixos` 部署。`just fmt`、`just check` 和实际系统切换均通过。

| 验证 | 结果 |
| --- | --- |
| API、deriver 实际容器环境 | 各 9 项 LLM 配置均为 Terra：提炼、五档 dialectic、摘要、两类梦境推理 |
| 实际后端请求 | 验证开始后 8 次 Honcho 请求均为 `gpt-6.1-terra`，全部完成 |
| API 健康及 Hermes 服务 | API healthy；15 个实例的 30 个 Gateway / Dashboard 服务均 active |
| 新记忆提炼与向量入库 | 独立测试工作区的 13 条合成消息产生 48 条观察，48 条均有 embedding；队列无错误 |
| 摘要与跨会话召回 | 新摘要生成成功；新会话正确恢复项目码、发货码、45 个模型且不重算、材料纠正、FCD、25 kg、1:1 和备案条件 |
| 历史问题回归 | M005 的模型决定、M013 的配方与用途、M015 的备案条件，三条 Honcho 推理回答的关键约束均正确 |

这些是新记忆链路与 Honcho 推理端的功能回归，未重新进行上面的 33 组 Hermes 最终回答对照。既有用户记忆没有因切换模型而批量重算。

新验证证据保存在本机私有目录 `/home/yifan/.local/state/honcho-eval/2026-11-06-terra/`，包括 `runtime-verification.json`、`manifest.json`、`new-memory-context.json`、`new-memory-recall.json` 和 `historical-regression.json`。

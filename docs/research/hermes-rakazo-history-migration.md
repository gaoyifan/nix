# Hermes 历史迁移到 Rakazo

调查日期为 2026-11-10。以当前部署的 Hermes `v0.23.0` / `2bd378ed1b8d6bf2192cb26e0a55ff3091e6bd19`、Rakazo `46e95fa8314324cbcf6e4e33c7ed06dbbc68b923` 为准。另读取 Rakazo 上游 `c76070c83a40f655fef2e298c43941f249407512` 的相关差异，Hermes 导入仍限于配置、记忆和技能。

## 现成入口

Rakazo 的 Settings → General → Import an agent 已支持 Hermes 文件夹及 ZIP、tar.gz。它识别指令、`memories/MEMORY.md`、`memories/USER.md`、自定义技能及部分设置，然后新建 Bot。候选文件白名单排除了 `state.db` 和 session 历史。技能配套文件仅收集名称以提示缺失，不能据此认为 Python 脚本等资源已随技能迁移。[官方说明](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/docs/import-an-agent.md)、[候选文件过滤](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/core/src/agent-import/index.ts#L63-L79)、[Hermes 解析](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/core/src/agent-import/hermes.ts)、[配套文件处理](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/core/src/agent-import/index.ts#L170-L190)

Hermes 的完整历史源是每个 profile 的 SQLite `state.db`。官方 `hermes sessions export` 支持 JSONL、Markdown、QMD、HTML、trace，并支持按会话、时间等筛选。Markdown/QMD 可用 `--lineage logical` 将压缩轮换产生的多个 session 拼成逻辑对话。[存储格式](https://github.com/NousResearch/hermes-agent/blob/2bd378ed1b8d6bf2192cb26e0a55ff3091e6bd19/website/docs/developer-guide/session-storage.md#L1-L39)、[导出参数](https://github.com/NousResearch/hermes-agent/blob/2bd378ed1b8d6bf2192cb26e0a55ff3091e6bd19/hermes_cli/subcommands/sessions.py#L100-L130)、[Markdown 导出](https://github.com/NousResearch/hermes-agent/blob/2bd378ed1b8d6bf2192cb26e0a55ff3091e6bd19/hermes_cli/sessions_cmd.py#L554-L575)

## 可选路径

| 路径 | 用户体验 | 实现与维护成本 | 主要边界 |
| --- | --- | --- | --- |
| 原生记忆导入，复用 Honcho | 新任务可以召回既有偏好和经验 | 低，主要是配置及记忆核对 | 逐字原文和附件仍需另存 |
| 历史文件放入 Bot 工作目录 | Bot 可搜索、读取旧对话及工具记录 | 低，一次性导出与文件索引 | 旧消息通过文件读取，聊天列表需另做原生导入 |
| 转成 Rakazo 账户 ZIP，再用 Import data | 旧消息进入原生聊天界面，可关联附件 | 中，需要格式转换器 | 导入创建新 Space，不能合并进现有 helper |
| 一次性应用层迁移到现有 Bot | 当前 helper 的聊天时间线含旧消息 | 高，需要正确处理现有线程和内容加密等 | 缺少现成的外部历史合并入口 |

上述成本是根据源码作出的工程判断。实际实施采用了记忆导入、独立 Honcho 和文件归档的组合。

### 记忆与 Honcho

本仓库的 Hermes 部署已启用 Honcho，并按用户隔离 workspace、固定用户 peer。Rakazo 原生 Honcho provider 接受已有 workspace 和 User peer，读取旧用户画像，同时向自己的 Bot/shared peers 写入新事实。因此可以复用原服务里的用户记忆。Hermes AI peer 内单独保存的信息是否仍有需要，应另行核验。[本地隔离配置](../../nixos/optional/hermes-nspawn.nix)、[Rakazo 记忆文档](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/docs/memory.md)、[已有用户 peer 的只读召回](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/adapters/src/honcho-memory-provider.ts#L268-L319)

若继续使用现有 helper，应核对并合并其记忆。官方 Import an agent 会新建 Bot。已有移植技能应逐项去重，避免导入旧 Hermes 工具协议覆盖当前适配。[导入说明](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/docs/import-an-agent.md)

### 工作目录中的历史档案

可将按逻辑会话导出的 Markdown、完整 JSONL、必要附件及路径清单放到目标 Bot 的持久化工作目录，索引保留会话 ID、时间、平台、标题与文件路径。只需给 Bot 一个查阅入口说明，复用已有 shell 和文件工具即可搜索原文。完整工具参数与输出保存在原始档中，常规搜索投影采用用户可见历史。

已通过一次性转换将历史放入现有 Computer 的持久目录，并以网页端真实提问验证文件检索。iMessage 入口尚未进行端到端验收。[Computer 与文件能力](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/docs/computer.md)

### 原生账户 ZIP

Rakazo 有独立的 `rakazo-account-export` v1 格式，支持 Bot、thread、message、memory、artifact 与工作文件。可以编写一次性转换器生成这种 ZIP，交给已有 `/api/account/import`。这是利用公开源码格式的可行设计，官方尚未提供 Hermes 聊天转换器。[格式定义](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/contracts/src/account-export.ts)、[导入入口](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/apps/api/src/account-import.ts#L1064-L1145)

当前版本有几项直接影响方案选择的约束。

- 每次账户导入都会创建新 Space，各条记录取得新 ID。它没有合并进当前 Space、当前 helper 的选项，重复上传也应在操作层避免重复导入。[Space 创建](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/apps/api/src/account-import.ts#L479-L500)
- 每个普通 Bot 只有一个主 thread。Hermes 的许多 session 需要合并成带会话分隔的时间线，或拆成多个 Bot。按 session 新建 Bot 会增加聊天列表数量。[线程模型](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/db/prisma/schema.prisma#L1052-L1062)、[导入线程映射](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/apps/api/src/account-import.ts#L593-L612)
- `search_history` 的 `my_chats` 只搜索当前 Space 中未归档的 Bot/群聊，而且要求应用内直接用户请求。外部消息及后台运行不能取得该跨聊天授权。因此把记录放到另一个 Space，并不能让现有 helper 自动检索它们。[检索范围](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/db/src/history-retrieval.ts#L124-L146)、[入口授权](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/adapters/src/run-tools-memory.ts#L15-L26)
- 默认历史检索只读取聊天正文、部分协作文本和附件名，工具轨迹不进入该文本投影。保留 Hermes 的工具证据需要附带原始 JSONL/trace 文件，不能仅检查聊天气泡。[文本投影](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/db/src/history-text.ts#L11-L45)
- 当前上传 ZIP 上限为 4 GiB，解压累计 16 GiB，工作目录单文件 8 MiB，artifact 按部署附件上限限制。原 SQLite 体积含索引，不能直接据此判断 ZIP 是否超限。[导入限制](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/apps/api/src/account-import.ts#L44-L58)、[工作文件限制](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/contracts/src/account-export.ts#L23-L27)

### 合并进当前 helper

若明确要求当前 helper 保留原生旧消息，可写一次性应用层迁移程序，复用 Rakazo 的 Prisma、租户上下文和内容加密机制。应维护源 session/message ID 到目标 ID 的映射，保留时间顺序，分配线程序号，迁移附件并处理现有任务与历史压缩边界。原始工具调用仍单独归档。此路径需要在测试副本中覆盖重试、去重与历史检索，工程量高于账户 ZIP。[消息与线程结构](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/db/prisma/schema.prisma#L1052-L1115)、[原生批量消息导入](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/apps/api/src/account-import.ts#L880-L935)

## 保真规则

1. 保存恢复用快照和用户可见历史两份投影。JSONL 快照包含 inactive 行，用户曾 Undo/Rewind 的内容也可能在其中。可检索历史应采用 Hermes 的展示投影，保留压缩前仍可见的消息，排除撤销内容并去重。[导出投影](https://github.com/NousResearch/hermes-agent/blob/2bd378ed1b8d6bf2192cb26e0a55ff3091e6bd19/hermes_cli/session_export.py#L213-L225)、[展示读取](https://github.com/NousResearch/hermes-agent/blob/2bd378ed1b8d6bf2192cb26e0a55ff3091e6bd19/hermes_state_messages.py#L1365-L1405)
2. 保留 compression lineage 和原始 segment ID，防止一次逻辑对话被拆碎。[lineage 导出](https://github.com/NousResearch/hermes-agent/blob/2bd378ed1b8d6bf2192cb26e0a55ff3091e6bd19/hermes_state_portability.py#L347-L379)
3. 附件、图片和工作文件需单独迁移并修正引用。Honcho 状态也由其独立服务保存。只拷贝 SQLite 无法包含这些数据。[存储范围](https://github.com/NousResearch/hermes-agent/blob/2bd378ed1b8d6bf2192cb26e0a55ff3091e6bd19/website/docs/developer-guide/session-storage.md)、[现有 Honcho 部署](../../nixos/optional/hermes-nspawn.nix)

## 建议路径与验收

若目标是继续使用现有 helper，同时能找回旧讨论，优先组合原生记忆、已有 Honcho 用户记忆与工作目录历史档案。这样可保留逐字证据，改动集中在一次性数据转换和查阅说明。若要求旧消息出现在原生聊天界面，再考虑账户 ZIP 或合并程序。

先对单一用户做试迁移，按原隔离边界保存数据。核对会话与展示消息数量、lineage、首末时间、附件哈希，再通过简短的真实回忆问题验证旧决定、后续纠正、工具证据和附件读取。入口覆盖网页和实际使用的消息渠道。确认后再推广到其他用户。

调查阶段只核对源码与线上元数据。后续实施已取得快照、导入原生记忆、部署独立 Honcho，并导出及校验两份历史档案。

## 已选方向的实施设计

用户选择原生记忆导入、在目标主机复制独立 Honcho、历史文件归档。迁移包含两个独立用户，第一位进入已有 helper，第二位创建独立账号、Space 和 Bot。各自的原生记忆、Honcho workspace、用户 peer 和历史目录分别绑定到对应目标。目标仅需部署一套 Honcho，保留两人的 workspace。实施沿用此隔离边界。

### 原生记忆

将 Hermes 的两个记忆文件转换成 helper 的 Bot scope `MEMORY.md` 与 `USER.md` 文档，沿用官方 Hermes parser 的 `§` 分隔归一化。通过原生 MemoryStore 提交并保留修订，按实际内容核对 helper 已有记忆。Bot scope 的所有文档和 Space scope 文档都会参与上下文构建，总注入预算为 32 KiB，迁移后调用原生 budget 入口确认完整进入上下文。[原生记忆提交](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/memory/src/index.ts)、[上下文构建与预算](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/adapters/src/memory-context.ts#L1-L138)

### 独立 Honcho

目标部署复用主机现有 PostgreSQL 16，新增独立 Honcho 数据库与角色、pgvector 扩展、Honcho API 和 deriver。先用源端 v3.0.12 镜像恢复并裁剪数据库，核对内容摘要，再将目标升级到固定的 v3.2.2。Rakazo 的 `forget_memory` 读取单条 conclusion，要求 Honcho ≥3.2，v3.0.12 会返回 405。embedding 模型及 4096 维配置保持一致。[Conclusion API 版本要求](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/adapters/src/honcho-client.ts#L217-L247)、[Honcho v3.2.2 更新记录](https://github.com/plastic-labs/honcho/blob/06ed1929cf017c333a87c41d130bb6a0605d91c0/CHANGELOG.md)

将已有 Honcho Nix 声明中的启动、初始化、镜像和健康检查抽出成小型共用模块，两台主机各自提供连接与运行时环境。源端 PostgreSQL 15 与目标 PostgreSQL 16 之间使用逻辑备份恢复。[PostgreSQL 逻辑备份](https://www.postgresql.org/docs/16/app-pgdump.html)

目标可采用 Honcho 默认进程内缓存。Redis 存储的是缓存及临时协调信息，持久消息、向量、结论及队列位于 PostgreSQL。[默认缓存配置](https://github.com/plastic-labs/honcho/blob/93dcf59c4a4225bb020b20c628799737fefae318/src/config.py#L1253-L1257)、[缓存实现](https://github.com/plastic-labs/honcho/blob/93dcf59c4a4225bb020b20c628799737fefae318/src/cache/client.py#L126-L136)、[持久数据模型](https://github.com/plastic-labs/honcho/blob/93dcf59c4a4225bb020b20c628799737fefae318/src/models.py)

完整复制采用以下顺序。

1. `pg_dump -Fc` 获取源 Honcho 的一致性快照。
2. 在目标离线数据库中恢复，初始化默认进程内缓存，再调用同版本上游 `crud.delete_workspace` 裁剪其他 workspace，核对只剩两位目标用户数据。两人共用一次数据库快照和恢复过程。完整恢复备份会短暂包含其他用户数据，应放在权限受限的运维区，最终保留仅含目标 workspace 的恢复备份。
3. 清除副本中的旧 worker 占用记录，保留持久任务队列，使用目标独立 JWT 密钥与认证 token 启动服务。目标使用 PostgreSQL 向量存储。
4. Rakazo 通过原生 Local Honcho 配置指向目标地址、原 workspace 和用户 peer。旧用户 peer 只读召回，新事实写入 Rakazo 自己的 peers。

上游删除 CRUD 已实现跨表清理，适合离线副本裁剪。当前版本的 workspace 完整导出/导入尚缺少现成接口，消息 API 重放还会重新派生状态。逻辑备份保留现有结论和向量，减少自制格式转换。[上游裁剪实现](https://github.com/plastic-labs/honcho/blob/93dcf59c4a4225bb020b20c628799737fefae318/src/crud/workspace.py#L309-L490)、[占用回收](https://github.com/plastic-labs/honcho/blob/93dcf59c4a4225bb020b20c628799737fefae318/src/deriver/queue_manager.py#L301-L328)、[迁移功能讨论](https://github.com/plastic-labs/honcho/issues/721)

Rakazo 的 Local memory provider 入口需要部署端启用 `MCP_ALLOW_PRIVATE_ENDPOINT`，同时要求 Space owner 操作。当前实现的 provider 配置属于整个 Space，实施时应核对目标成员及 Bot 范围。备份可采用 NixOS 原生 PostgreSQL 备份能力，落盘到现有加密 ZFS 备份范围。[本地服务准入](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/apps/api/src/memory-provider-config.ts#L35-L83)

### 历史归档与分叉点

在 helper 持久化工作目录保存按逻辑会话导出的 Markdown、对应展示投影 JSONL、原附件与轻量 manifest。Markdown 用于搜索阅读，JSONL 保留工具调用参数等结构字段。只读恢复快照放入权限受限的运维备份区，Bot 检索范围采用已过滤撤销行的展示历史。可整体归档该用户的附件目录，减少自制附件引用解析。只在记忆中添加一条档案目录与查阅方法。

要取得清晰的业务分叉点，可短暂停止两位来源用户的 Hermes 入口，等待两个 workspace 的派生队列完成，然后分别取得 SQLite 在线备份、记忆与附件快照，以及共用的 Honcho 逻辑快照。来源服务恢复后两端各自写入，迁移程序只执行一次。SQLite 使用自身备份接口生成快照，避免遗漏 WAL 中的已提交消息。

验收包含原生记忆 budget、逻辑会话及消息清单、附件哈希、Honcho peers/messages/documents/embeddings 计数与校验，以及新 Honcho 独立写入。通过网页和实际消息渠道向 helper 发送简短回忆问题，检查原文、工具证据与附件读取。文件摘要、SQLite 完整性、原生记忆预算、租户隔离、Honcho 分叉读写和删除、目标备份恢复已完成核验。网页端通过简短提问找回旧讨论，并交付与源附件 SHA-256 相同的 PDF。初次泛指附件时出现来源混淆，补充附件索引及来源说明后，同句复测找到了 Hermes 原件。第二位用户的 Bot 模型授权仍待确定，iMessage 入口验收尚未进行。
## 实施注意事项

- 共用的 Honcho 服务声明位于 [honcho.nix](../../nixos/optional/honcho.nix)，目标主机的模型、内网监听、凭据和备份配置位于 [目标配置](../../nixos/hosts/el2/services/honcho.nix)。推理请求通过本机 `127.0.0.1:3003` 的 codex-api，embedding 通过本机 `127.0.0.1:9000` 的 New API 调用 SiliconFlow。
- 本机 codex-api 通过 systemd `LoadCredential` 读取用户提供的 `~/.codex-api/auth.json` 初始凭据，刷新后的令牌及额度记录保存在加密 services 数据集中的 SQLite。服务配置位于 [codex-api.nix](../../nixos/hosts/el2/services/codex-api.nix)。
- 转录备用节点由本机 [whisper-server.nix](../../nixos/hosts/el2/services/whisper-server.nix) 提供，使用 CPU 和 `large-v3-turbo` 模型。Rakazo Computer 镜像将转录脚本的备用地址设为 `100.64.2.254:8178`。
- 原生记忆通过 MemoryStore 提交，保留修订并校验完整进入上下文。某个来源的 `MEMORY.md` 超过 Rakazo 主记忆文件的 4 KiB 编辑限制，全文放入同一 Bot 的原生 `Hermes/MEMORY.md` 文档，主文件保留索引和档案入口。原生上下文构建会读取所有 Bot 记忆文档，已核验全文进入 32 KiB 注入预算，主文件有空间继续积累记忆。
- `history/hermes/README.md` 是每个 Bot 的历史入口，`sessions/` 同时保存 Markdown 和展示投影 JSONL，配套目录保存旧附件。恢复用 SQLite 快照保存在私有运维备份区。
- 迁移程序使用来源版本的 Hermes 导出逻辑。SQLite 快照通过备份 API 取得，校验和清单排除临时 `-wal` 与 `-shm` 文件，并验证裸数据库的完整性及消息数量。
- PostgreSQL 原生定时备份保存目标数据库，位置位于加密 ZFS services 数据集。Honcho 在手动解锁完成的服务 target 下启动。

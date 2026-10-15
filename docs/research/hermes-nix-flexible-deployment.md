# Hermes Nix 灵活部署与用户自助 MCP

调查日期：2026-09-29。核对本仓库锁定的 `v2026.9.24` / `f97608f178d1ffeca59860195ab7da295f7c8e5f`；联网取得上游 main 当时的 `bca2e3c5a486a7cb85a7721af937b7f9b614f131`，其中 `nix/nixosModules.nix` 与 pinned 内容相同。

## 实现与维护

共享 [`guest.nix`](../../nixos/optional/hermes-nspawn/guest.nix) 使用上游 managed scope：

- `/run/hermes-secrets/`：宿主生成的运行时凭据目录在容器内的只读挂载点；宿主源目录仍是 `/run/hermes-nix-<user>-secrets`。保留整目录挂载，宿主原子替换 `.env` 时容器仍能读到新文件。
- `/etc/hermes/config.yaml`：Nix 生成的只读部署基线，不含 `mcp_servers`，使用官方默认 managed scope 目录。修改此文件的 Nix 定义会触发 Gateway 和 Dashboard 重启。
- `/etc/hermes/.env`：指向 `/run/hermes-secrets/.env` 的符号链接，复用宿主注入的凭据及原有权限，不将凭据复制到 Nix store。Honcho 也直接链接运行时目录中的 `honcho.json`。
- `$HERMES_HOME/config.yaml`、`.env` 和 `mcp-tokens/`：用户配置与认证状态，沿用现有备份范围。Gateway、Dashboard 与交互 CLI 均设置 `HERMES_MANAGED=false`，无需设置 `HERMES_MANAGED_DIR`。
- 原有 Notion 定义留在用户文件中，新实例由用户在 Desktop 添加 `https://mcp.notion.com/mcp`，选择 OAuth；需要延长授权等待时在 MCP JSON 中设置 `connect_timeout: 315`。Nix 不会恢复被用户删除的 server。
- Gateway、Dashboard 和交互 shell 均提供 `uvx`、`npx`。stdio 在 nspawn 的 `agent` 权限下运行；在 terminal 沙箱内安装的依赖不等于安装到 MCP 运行环境。

Desktop 保存后使用其原生 MCP reload。Messaging Gateway 是另一进程，使用聊天中的 `/reload-mcp`，或由管理员重启 `hermes-agent.service`。本实现没有增加文件监视、配置同步或自动重启组件。

canary 已验证真实 Dashboard API 的 HTTP/stdio server 添加、探测、删除，bearer 凭据写入，整表编辑与 OAuth 定义保存。再次激活 NixOS 配置并重启 Gateway/Dashboard 后，新增配置、Notion 删除和个人凭据均保留，CLI 与 Dashboard 读取一致；尝试修改固定的 provider/terminal 字段不会覆盖管理员值。测试结束后恢复 canary 原有配置并删除测试数据。未代替用户完成外部 OAuth 授权。

2026-09-29 已通过 `just fmt`、`just check`、canary 与宿主完整构建，并通过 `just nixos` 部署到全部 15 个实例。部署后 30 个 Hermes 服务均为 active，15 个 Dashboard 接口均正常；逐实例比对部署前后的 MCP 定义、个人 `.env` 与 `mcp-tokens/*.json` 指纹，内容全部保持不变。宿主没有失败服务。

官方将 `/etc/hermes` 定义为管理员配置层，并没有要求在这里挂载凭据源目录。上游 Nix 模块的 `environmentFiles` 则在激活时重新生成 `$HERMES_HOME/.env`，会覆盖用户在同一文件中的写入，因此本部署不使用该选项注入管理员凭据；保留 systemd `EnvironmentFile` 与 managed scope 的只读链接。迁移挂载点后，canary 已验证在没有 `HERMES_MANAGED_DIR` 的情况下读取默认目录、用户 MCP/key 写入、管理员字段覆盖和 Honcho 链接。[官方目录约定](https://hermes-agent.nousresearch.com/docs/user-guide/managed-scope/)、[上游环境文件生成器](https://github.com/NousResearch/hermes-agent/blob/f97608f178d1ffeca59860195ab7da295f7c8e5f/nix/moduleCommon.nix#L733-L764)、[激活时写入用户文件](https://github.com/NousResearch/hermes-agent/blob/f97608f178d1ffeca59860195ab7da295f7c8e5f/nix/moduleCommon.nix#L860-L863)

目录调整也已推广到全部 15 个实例：两个服务进程均不再设置 `HERMES_MANAGED_DIR`，旧 `/etc/hermes-managed/config.yaml` 已清理，运行时凭据挂载保持只读及 `root:agent 0640` 权限。服务、Dashboard 和用户数据指纹检查全部通过。

## STT 与插件启用列表的后续调整

按用户最终决策，主模型、标题模型、压缩阈值和 Exa 搜索后端继续由平台固定；标题模型改为 `gpt-6-luna`。`stt.enabled` 与 `plugins.enabled` 已从 managed scope 移除，由用户管理。

新实例仅在默认 Profile 的 `config.yaml` 不存在时安装 `hermes-initial-user-config.yaml`：`stt.enabled=false`，`plugins.enabled=[newapi-codex, weixin-channel]`。该 activation 在上游 `hermes-agent-setup` 前执行。已有文件不被补写，因此显式禁用插件（包括空列表）和开启语音转写都能跨 rebuild 保留；这不是持续合并的低优先级平台默认层。插件文件仍由 Nix 安装，用户主动停用插件会停用对应功能。额外 Profile 继续遵循上游创建流程，不经过此实例初始化脚本。

最初在 canary 中备份并移走用户配置后执行初始化脚本，验证了初始值与插件加载；随后将 STT 改为 true、插件列表改为空，完整 reactivation 后仍保留用户选择。该测试模拟首次配置，不能单独证明全新实例的首次启动顺序。

## Honcho 的 Nix 依赖管理（2026-10-14）

Hermes 已升级到官方 `v0.21.7`，Honcho 使用官方目录插件和 `honcho-ai 2.5.1`。插件提交与 SDK wheel 的哈希分别固定在 [`honcho-plugin.nix`](../../pkgs/honcho-plugin.nix) 和 [`honcho-ai.nix`](../../pkgs/honcho-ai.nix)，无需 Hermes fork 或源码补丁。

SDK 通过上游 `extraPythonPackages` 包覆盖接口加入 Gateway、Dashboard 和 CLI 共用的包，并使用 Hermes 的 Python 解释器。SDK 复用 Hermes 已锁定的 httpx/pydantic，构建时执行依赖版本检查和导入检查。打包时在插件清单中声明上游支持的 `python_runtime: external`，由 Nix 负责依赖，PM 与 Dashboard 不再要求另建 PM 环境；插件 Python 代码不作修改。Honcho 插件通过 tmpfiles 链接到 `$HERMES_HOME/plugins/honcho`：上游 `extraPlugins` 会添加 `nix-managed-` 前缀，而记忆提供者按目录名查找。`memory.provider=honcho` 和运行时凭据链接保持原有约定。

Python 依赖由 Nix 管理，`security.allow_lazy_installs=false` 关闭自动依赖安装。新增或升级需要 Python 依赖的插件应修改 Nix 配置并 rebuild；用户 MCP 配置、凭据及插件启用列表仍由用户管理。Honcho 的插件和 SDK 必须一起验证升级。[上游 Nix 插件接口](https://github.com/NousResearch/hermes-agent/blob/v0.21.7/website/docs/getting-started/nix-setup.md#combining-both)

canary 已验证空测试目录的 SDK 加载、依赖版本约束、提供者加载、Honcho 元数据写入/独立读取/恢复、Dashboard 就绪状态及服务重启，未创建 PM Python 环境。随后通过 `just nixos` 部署到 somo-minisforum 的全部 15 个实例：30 个服务 active，15 个 Dashboard 的 Honcho 均为 `ready`，SDK、Honcho API 和用户 MCP API 检查通过。部署前后所有实例的 MCP 定义、个人 `.env`、MCP 认证文件、STT 与插件开关指纹一致。`just fmt`、`just fmt-check`、`just check` 和完整宿主构建通过。

上游启动检查报告现有 Nixpkgs 的 SQLite 3.51.2 处于 WAL-reset bug 的受影响版本范围。此依赖升级需要另行跟进。[SQLite 官方说明](https://sqlite.org/wal.html#walresetbug)

## 原生图片接口（2026-10-15）

图片插件沿用 `newapi-codex` 标识，保留用户已有的启用状态和模型档位选择；实际请求已迁移至 `codex-api`，不再经过 New API 或依赖外层聊天模型。宿主在运行时 `.env` 中注入 `CODEX_API_BASE_URL=http://198.18.255.254:3002/v1`，鉴权继续使用两个服务共享的每用户 `NEWAPI_API_KEY`。

插件直接请求 `/v1/images/generations`；有参考图时，将图片转为内联 data URL 后请求 JSON 格式的 `/v1/images/edits`。`codex-api` 复用现有 API key 鉴权和上游 OAuth 凭据刷新，不对图片请求检查额度或写入用量账本；聊天的额度逻辑保持不变。上游不一定遵守请求的质量和尺寸，插件在 `reported_quality` 和 `reported_size` 中返回实际报告值，不能仅凭 `model` 档位判断实际输出。

先在 canary 通过已安装插件验证生图及参考图编辑，再推广到全部 15 个实例；30 个 Hermes 服务均正常，用户配置文件指纹保持不变。生图与编辑分别约 17 秒和 18 秒，参考图中的蓝色圆形成功变为红色。实现入口见[图片插件](../../nixos/optional/hermes-nspawn/newapi-codex/__init__.py)和[运行时环境注入](../../nixos/optional/hermes-nspawn.nix)。

## 对当前需求的结论

用户的主要需求是每人自行添加、修改、删除 MCP。适合保留现有 NixOS nspawn、Nix Hermes 包、gateway 和 dashboard，调整配置的管理边界；无需为此迁入另一层 Ubuntu OCI 容器。

迁移前，`guest.nix` 为交互环境与 dashboard 显式设置 `HERMES_MANAGED=true`，上游 NixOS module 也给 gateway 设置该值，导致配置保存接口整体拒绝写入。现已在三个入口显式覆盖为 false。这个开关与只读 Nix 程序包是不同机制。

**最小的解除方案是显式设置 `HERMES_MANAGED="false"`，而不是仅删除变量。** pinned 的 `get_managed_system()` 优先读取非空环境变量；`false`、`0`、`no`、`off` 都表示关闭。只有环境变量为空才检查 `$HERMES_HOME/.managed`，所以不需要删除 marker 或修改上游 activation。需要覆盖 gateway、dashboard 和交互 CLI 三个入口，避免行为不一致。[判断源码](https://github.com/NousResearch/hermes-agent/blob/f97608f178d1ffeca59860195ab7da295f7c8e5f/hermes_constants.py#L1088-L1112)

此处修正旧研究中“必须同时移除 `.managed`”的表述：**仅 unset 不够，显式 false 足够。** Hermes 代码及依赖仍在只读 Nix store；此设置允许配置写入，并不能让 `pip` 改写该包。

## MCP 自助保存为什么可行

Dashboard MCP 添加接口和 OAuth 完成处理使用与 CLI 相同的 `_save_mcp_server()`，最终调用 `save_config()`。后者首先检查粗粒度 managed lock；解除后正常写入用户配置，同时剥除管理员 managed scope 锁定的叶子字段。因此不在管理员配置里声明 `mcp_servers`，用户就可以自行管理此部分。[Dashboard 路由](https://github.com/NousResearch/hermes-agent/blob/f97608f178d1ffeca59860195ab7da295f7c8e5f/hermes_cli/web_routers/mcp.py#L112-L140)、[MCP 保存](https://github.com/NousResearch/hermes-agent/blob/f97608f178d1ffeca59860195ab7da295f7c8e5f/hermes_cli/mcp_config.py#L232-L243)、[配置保存与管理员字段过滤](https://github.com/NousResearch/hermes-agent/blob/f97608f178d1ffeca59860195ab7da295f7c8e5f/hermes_cli/config.py#L2380-L2425)

Nix activation 会递归合并 settings 到用户 `config.yaml`：Nix 声明的叶子覆盖用户值，未声明的用户键保留。原来的 `mcpServers.notion` 声明已移除，避免用户删除或修改它后被 rebuild 恢复。已有 Notion 项保留为用户配置；新实例不自动添加，由用户自行配置。[合并实现](https://github.com/NousResearch/hermes-agent/blob/f97608f178d1ffeca59860195ab7da295f7c8e5f/nix/configMergeScript.nix)、[本地 guest 配置](../../nixos/optional/hermes-nspawn/guest.nix)

迁移后检查发现，各实例的用户配置仍含 32 个与 managed scope 相同的基线叶子，以及 4 个被覆盖的旧值（`skills.external_dirs`、`terminal.cwd`、`terminal.docker_image`、`terminal.docker_volumes`）。它们不改变当前有效配置；Hermes 的原生 `save_config()` 会剥离被管理员固定的字段，因此不增加批量迁移或持续清理脚本。上游 Nix 模块仍会在 activation 时写入默认 `terminal.cwd`，无需为了消除这一无效重复维护上游补丁。

如果还需固定 provider、terminal 隔离参数，可用独立的 **managed scope**：root 管理 `/etc/hermes/config.yaml` 和 `/etc/hermes/.env`，Hermes 读取时逐叶覆盖用户配置，其他字段仍归用户。它与 `HERMES_MANAGED` 的整体写锁独立；支持 `HERMES_MANAGED_DIR` 指定位置。初始部署的只读 `/etc/hermes` secret 挂载已移到 `/run/hermes-secrets`，让默认 managed scope 目录由 Nix 管理。[managed scope 实现](https://github.com/NousResearch/hermes-agent/blob/f97608f178d1ffeca59860195ab7da295f7c8e5f/hermes_cli/managed_scope.py#L1-L8)、[目录与覆盖逻辑](https://github.com/NousResearch/hermes-agent/blob/f97608f178d1ffeca59860195ab7da295f7c8e5f/hermes_cli/managed_scope.py#L45-L157)

managed scope 是应用配置策略：依赖文件权限，配置损坏时会告警并忽略该文件，不是隔离任意用户代码的安全边界。若需要强制资源/网络隔离，仍应由 nspawn、容器 runtime 和宿主机实现。[错误处理](https://github.com/NousResearch/hermes-agent/blob/f97608f178d1ffeca59860195ab7da295f7c8e5f/hermes_cli/managed_scope.py#L73-L103)

MCP 的协议也影响环境需求：HTTP/OAuth MCP 不需要本地 server 依赖；stdio MCP 启动在 Hermes 进程的环境内，不自动使用 `terminal.backend=docker` 的工具容器。当前 gateway、dashboard 与交互 shell 均提供 uv/npm 工具，用户 home 可写且纳入现有备份。连接探测已在 canary 验证；两个服务的 MCP 重载仍分别使用各自的原生机制。

## 最终采用的维护边界

用户通常只需要 URL MCP，并优先考虑长期维护成本。最终选择复用上游原生编辑器和 managed scope，同时保留 URL 与 stdio 能力，不维护 transport 拦截补丁、外部 MCP gateway 或另一套配置同步机制。

当前 stdio 由 Hermes 直接启动，未接入 terminal 的 gVisor 沙箱；它具有该用户 `agent` 的文件访问权限。当前 `/etc/hermes/.env` 对 agent 组可读，其中既有个人 New API token，也有共享 Exa、飞书凭据。过滤子进程继承环境不能阻止代码自行读取这些文件。[stdio 启动](https://github.com/NousResearch/hermes-agent/blob/f97608f178d1ffeca59860195ab7da295f7c8e5f/tools/mcp_tool_transport.py#L329-L349)、[本地凭据生成及权限](../../nixos/optional/hermes-nspawn.nix)

显式 false 只解除全局锁，**不会限制 MCP transport**。使用约定是优先选择 URL；stdio 按用户自己的 Hermes 进程权限运行，是用户实例的信任边界，并不声称具有 terminal 的 gVisor 隔离。若将来必须隔离不受信任的 stdio，应优先采用上游支持的方案。

## 用户记忆中的更灵活部署方案

官方确实提供 `services.hermes-agent.container.enable = true`：NixOS 管理生命周期，Hermes gateway 在持久 Ubuntu OCI 容器里运行，`/nix/store` 只读挂载，外部工具可以自行安装。默认镜像 `ubuntu:24.04`、runtime Docker，也支持 Podman。与现有 `settings.terminal.backend = "docker"` 不同，它容器化的是 gateway 本身。[官方文档](https://hermes-agent.nousresearch.com/docs/getting-started/nix-setup/)、[选项](https://github.com/NousResearch/hermes-agent/blob/f97608f178d1ffeca59860195ab7da295f7c8e5f/nix/nixosModules.nix#L297-L339)

入口首次安装 sudo、NodeSource Node 22、uv 及用户 Python 3.12 venv；Hermes 用户拥有容器内免密 sudo。venv 的 python/pip 用于可写工具环境，Hermes 自己仍使用 Nix Python，不能把外部 pip 安装等同于修改 Hermes 的依赖闭包。[入口](https://github.com/NousResearch/hermes-agent/blob/f97608f178d1ffeca59860195ab7da295f7c8e5f/nix/nixosModules.nix#L123-L177)、[Nix wrapper](https://github.com/NousResearch/hermes-agent/blob/f97608f178d1ffeca59860195ab7da295f7c8e5f/nix/hermes-agent.nix#L185-L209)

服务重启、宿主机重启及只更新 Hermes 包/配置不会主动销毁 OCI 可写层。容器 identity 改变才删除重建，identity 的源码字段是 `schema`、`image`、`extraVolumes`、`extraOptions`；文档声称包含 entrypoint，但 pinned 源码并不包含。重建会丢失仅存在可写层的 apt/npm 等安装；`stateDir` 和其 `home` 子目录有 bind mount，保存于其中的 venv 等仍保留。不要笼统地认为所有 pip 安装都会丢失。[identity](https://github.com/NousResearch/hermes-agent/blob/f97608f178d1ffeca59860195ab7da295f7c8e5f/nix/nixosModules.nix#L179-L190)、[生命周期与卷](https://github.com/NousResearch/hermes-agent/blob/f97608f178d1ffeca59860195ab7da295f7c8e5f/nix/nixosModules.nix#L648-L707)

此模式仍显式设置 `HERMES_MANAGED=true`，所以单开 container **不能解决自助 MCP 保存**。官方 module 也禁止 container 与 `backend.mode` 同开，只负责 gateway；当前自建 dashboard 不会自动迁入，服务用户、PATH、HOME、凭据挂载都需另行适配。[managed 环境](https://github.com/NousResearch/hermes-agent/blob/f97608f178d1ffeca59860195ab7da295f7c8e5f/nix/nixosModules.nix#L675-L690)、[backend 限制](https://github.com/NousResearch/hermes-agent/blob/f97608f178d1ffeca59860195ab7da295f7c8e5f/nix/nixosModules.nix#L406-L411)

默认 OCI 服务由 root 启动、使用 host network，没有自动加上当前 terminal 的 gVisor 配置。当前备份只覆盖各 nspawn 的 `/var/lib/hermes`，不能据此认为 OCI runtime 的整个可写层也被备份。现有 terminal 镜像已提供 Debian、Nix、uv、Node 和 apt；为普通终端安装依赖不值得增加一次整体迁移。[OCI 参数](https://github.com/NousResearch/hermes-agent/blob/f97608f178d1ffeca59860195ab7da295f7c8e5f/nix/nixosModules.nix#L637-L713)、[当前 terminal](../../nixos/optional/hermes-nspawn/terminal.nix)、[备份范围](../../nixos/hosts/somo-minisforum/default.nix)

## 后续变更的回归重点

后续升级先在 `hermes-nix-canary` 检查 Dashboard 的 MCP 增删改与连接探测、个人凭据保存、配置重载及 rebuild 后的持久性。同时确认默认 managed scope 生效、provider/terminal 的管理员值不被用户覆盖，且配置保存不改动其他用户状态。本次已经完成的验证见本文开头。

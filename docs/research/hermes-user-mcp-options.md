# Hermes Nix 终端用户自助添加 MCP 的实现选项

> 范围：本仓库当前部署及 flake 锁定的 Hermes
> [`3ef6bbd201263d354fd83ec55b3c306ded2eb72a`](../../flake.lock#L223-L246)。结论来自实际 Desktop、backend、MCP loader/writer 与 NixOS module；未读取任何真实凭据。

## 结论

当前部署**已经支持“管理员声明 server，用户只做 OAuth”**，但**不支持通过 Desktop 持久添加 server 定义**。两件事必须区分：

- **添加定义**：写入 `mcp_servers.<name>` 的 `url` 或 `command`；
- **认证既有定义**：为已经存在且声明了 `url`、`auth: oauth` 的远程 server 获取 token。

最小建议是：

1. 近期继续采用**管理员审核并由 Nix 预声明远程 HTTPS/OAuth MCP，用户在 Desktop 自助 OAuth**；共享 guest 已用这种方式部署 Notion（[`guest.nix`](../../nixos/optional/hermes-nspawn/guest.nix#L194-L199)）。
2. 若目标是“任意用户自定义”，优先提供一个**每用户、外部托管的 MCP gateway/proxy**，Hermes 只预声明一个远程入口；或再做一个**只允许远程 HTTPS 的窄 overlay/API**。不要先开放本地 stdio。
3. 不建议仅为此关闭整个 managed mode。若确实要复用现成 Desktop 编辑器而不改上游，较安全的折中是去掉 package-manager 的全局写锁，改用上游 **managed scope** 逐项锁定管理员配置，而不是使全部配置可变；但自定义 MCP URL/命令仍需额外安全策略（[上游 managed-scope 文档](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/website/docs/user-guide/managed-scope.md#L13-L31)）。

## 当前事实与边界

### 配置、managed mode 与 Profile

每位用户有独立 nspawn；Hermes 以 `agent` 运行，默认 `HERMES_HOME=/var/lib/hermes/.hermes`。Nix module 在 activation 时把磁盘现有配置与 Nix 配置深合并，**用户新增键保留、Nix 同名叶子胜出**；因 `addToSystemPackages=true`，`config.yaml` 实际为 `0660`（[上游 module](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/nix/nixosModules.nix#L45-L64)、[activation](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/nix/nixosModules.nix#L734-L764)、[merge script](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/nix/configMergeScript.nix#L16-L32)）。所以有 shell 权限的 `agent` 可直接改同一文件，且不冲突的 user server 能跨 rebuild 保留；但这绕过了 managed UX，而不是正式的用户层。

本仓库同时在全局环境、`hermes-agent.service` 与 `hermes-dashboard.service` 设置 `HERMES_MANAGED=true`（[`guest.nix`](../../nixos/optional/hermes-nspawn/guest.nix#L176-L188)、[`guest.nix`](../../nixos/optional/hermes-nspawn/guest.nix#L356-L418)）。上游还创建 `.managed` marker；任一信号都会触发全局写锁，`save_config()` 与 `.env` writer 直接返回（[检测](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/hermes_cli/config.py#L338-L358)、[config writer](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/hermes_cli/config.py#L7515-L7544)、[env writer](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/hermes_cli/config.py#L7956-L7973)）。这也解释了为何新 Profile 不是逃生口：Profile 虽各有独立的 config、`.env`、token 和 gateway（[profiles.py](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/hermes_cli/profiles.py#L1-L19)），dashboard 进程继承的 `HERMES_MANAGED=true` 仍会阻止所有 Profile 的普通 writer。任何 overlay/API 都应按 Profile 存储；OAuth 本身已经按 `$HERMES_HOME/mcp-tokens/` 隔离（[token storage](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/tools/mcp_oauth.py#L134-L145)）。

### Desktop 看似可编辑，但 managed 下是假成功

Desktop 已有完整 `mcp.json` 编辑器、catalog、probe、OAuth、启停与工具过滤；保存调用 whole-map `PUT /api/mcp/servers`，随后更新本地 cache 并对当前 live session 发 `reload.mcp`（[UI](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/apps/desktop/src/app/skills/mcp-tab.tsx#L665-L716)、[save UX](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/apps/desktop/src/app/skills/mcp-tab.tsx#L858-L899)）。backend 也有 add/replace/delete API，并做“恰好一个 transport”等基本检查（[web_server.py](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/hermes_cli/web_server.py#L11930-L12018)、[API](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/hermes_cli/web_server.py#L12067-L12130)）。

但这些 API 最终都调用被 managed mode 静默短路的 writer，且上层仍返回成功。因此当前 UI 的 add/delete/toggle/catalog 可能短暂显示成功，刷新或重启即消失；不能把现有页面视为可用的 managed-mode 管理面。

OAuth 是例外：backend 可对**已经存在**的 URL server 运行浏览器 flow，token storage 直接原子写入 profile 目录，并 live reconnect（[OAuth API](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/hermes_cli/web_server.py#L12242-L12353)）。但 managed 下对 `auth: oauth` 的补写仍是 no-op，所以管理员必须预先声明 `auth = "oauth"`；不能只预声明 URL，再指望用户认证动作永久改变定义。静态 bearer 则要写 profile `.env`，当前同样被锁；stdio 也没有 OAuth，凭据只能来自其显式 `env`。

### 远程 HTTP/SSE 与本地 stdio 不是同一风险级别

- `url` 默认走 Streamable HTTP；`transport: sse` 才走 SSE，OAuth 只适用于这两类远程 transport（[HTTP/SSE client](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/tools/mcp_tool.py#L2548-L2613)）。远程 server 不在本机执行代码，但会看到发送给其工具的数据、返回可影响模型的内容，并可触发外部副作用。当前 URL 校验只要求 `http(s)` 和有效 hostname，没有阻止私网/loopback，故任意 URL 自助功能还形成 nspawn 内网 SSRF 面（[URL validator](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/tools/mcp_tool.py#L967-L1004)）。对不信任的 server 还应默认 `sampling.enabled=false`；上游当前默认开启 server-initiated sampling（[mcp_tool.py](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/tools/mcp_tool.py#L2810-L2825)）。
- `command` 是 Hermes 进程直接启动的任意本地子进程，运行在 **nspawn 内的 `agent` 权限**，不是 Podman terminal。Podman 的 gVisor/KVM、`/workspace` 映射和 terminal 镜像（[`guest.nix`](../../nixos/optional/hermes-nspawn/guest.nix#L110-L134)、[`terminal.nix`](../../nixos/optional/hermes-nspawn/terminal.nix#L124-L151)）不隔离 stdio MCP；后者可访问该用户的 Hermes 状态与进程可读文件，且 executable 必须存在于 Hermes service 的文件系统/PATH，而不是仅安装在 terminal 容器里。上游只过滤继承环境，再附加用户显式 `env`（[safe env](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/tools/mcp_tool.py#L426-L446)），并明确说明安全检查**不是 sandbox**、只拦少数 shell/IOC 形状（[mcp_security.py](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/hermes_cli/mcp_security.py#L1-L24)、[规则边界](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/hermes_cli/mcp_security.py#L121-L177)）。因此开放 stdio 等价于把 `agent` 级代码执行交给该 UI 用户；两个 systemd 进程还可能各自启动一份 server。

## 方案比较

| 方案 | 无上游补丁？ | 安全与 managed mode | 持久化 / UX / reload |
|---|---|---|---|
| **管理员预声明 catalog + 用户 OAuth** | **是，现成可用** | 管理员审核 endpoint、tool allowlist；定义仍由 Nix 管理。适合远程 OAuth；无认证 HTTP 也可声明。静态 bearer/stdio 凭据仍需管理员安全注入。 | 定义随 Nix，OAuth token 随 Profile 状态跨重启/rebuild。Desktop OAuth UX 最好，但用户不能新增任意 endpoint。OAuth 可刷新 dashboard 当前进程；独立的 `hermes-agent.service` 仍需 `/reload-mcp` 或重启。 |
| **用户 overlay 文件，运行时合并** | 真正的多文件 loader **否**；用 Nix/systemd sidecar 把 overlay 原子合入 `config.yaml` 则**是** | 可保留 `HERMES_MANAGED=true`，规定 admin 层胜出、拒绝同名保留项；应先只准 HTTPS、阻止私网/loopback、禁 sampling。允许 stdio 就仍是 `agent` 代码执行。 | 每 Profile 一个 `/var/lib/hermes/.../mcp-user.yaml` 可持久；当前 Desktop 不会写它，需 SSH/另做小 UI。上游 loader 只读取 `config.yaml.mcp_servers`（[loader](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/tools/mcp_tool.py#L3985-L4017)），故 sidecar 必须维护 effective file，并用 path unit reload/restart；要处理与 Nix activation 的写入竞争。直接手改现有 `config.yaml` 是更小但更脆弱的同文件变体。 |
| **专用 managed-mode backend API/UI** | **否**（需上游或本仓库 downstream source patch；外置 sidecar UI 除外） | 最可控：只绕过 MCP 用户层，不解除全局锁；“privileged”应是逻辑权限，进程仍用 `agent`，不应升 root。复用现成 editor/probe/OAuth，但 whole-map API 要拆成 admin 只读层 + user 可写层，并补 HTTPS/SSRF、大小、名称、secret、stdio allowlist 等校验。 | 原子写 profile overlay，错误可真实返回，UX 最佳。API 成功后可 reload dashboard session；还需明确通知/重启独立 gateway service。 |
| **全部配置 mutable / unmanaged** | **是，部署侧移除 env + marker 即可** | 风险最大：现成 Desktop/CLI 全部 writer 与 bearer secret 流程立即可用，但用户也可改模型、安全、approval、platform 和任意 stdio。若 Nix 仍声明键，rebuild 时这些键仍被覆盖；若停止生成则失去声明式基线。较好的变体是关闭 package-manager 全局锁、用 managed scope 只 pin 管理员叶子。 | 单文件、现成 UX、Profile 原生支持，磁盘状态持久。Desktop 当前 session 会 silent reload；systemd gateway 仍是另一进程。 |
| **外部、用户控制的 MCP gateway/proxy** | **是** | Hermes 只连接管理员预声明的每用户 HTTPS gateway；下游 stdio/任意 connector 在 Hermes nspawn 外执行，避免泄露本机 Hermes 状态。代价是 gateway 能看到全部 MCP 数据并代表用户执行动作，必须有强租户隔离、TLS/OAuth、审计和最小 tool surface。不要把长期 gateway 当作 Podman terminal 内进程：那里无 systemd，生命周期属于 terminal task。 | connector 配置和凭据由外部系统持久，用户用另一套控制台，Hermes managed mode 不变。若 proxy 保持同一连接并发 `notifications/tools/list_changed`，Hermes 会动态刷新工具而无需服务 reload（[dynamic refresh](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/tools/mcp_tool.py#L1866-L1970)）；否则仍需 `/reload-mcp`。 |

## Reload 的实际含义

MCP 连接和 agent tool snapshot 是**进程内状态**。`reload.mcp` 会关闭/重连 server，并重建当前 session 的工具快照；它也会使 prompt cache 失效（[TUI gateway](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/tui_gateway/server.py#L12657-L12735)）。本部署的 Dashboard backend 与 messaging Gateway 是两个 systemd 进程，Desktop 的 silent reload 不等于重载 `hermes-agent.service`。因此任何用户写入方案都应定义：

1. Desktop 当前 Profile/session：写入成功后调用 `reload.mcp`；
2. messaging Gateway/cron：通过其自己的 `/reload-mcp`，或由受限 systemd path/service 重启 `hermes-agent.service`；
3. Dashboard 无 session、其他 Profile、另一进程中的旧连接：不能假定自动同步；
4. stdio MCP 更新时重启会杀掉并重建子进程，HTTP/SSE 则只是重连。Gateway 自身的 reload 实现也是重新读 `config.yaml` 后刷新缓存 agent（[gateway/run.py](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/gateway/run.py#L15432-L15502)）。

综合而言，**现在可直接上线的最小路径是“审核后的远程 OAuth catalog + 用户授权”**；要求用户真正自定义时，**外部 gateway** 是无需维护 Hermes fork 且不把 stdio 代码执行带入 nspawn 的最小扩展。只有必须在 Hermes 原生页面管理任意 endpoint 时，才值得实现 profile-scoped user overlay 与窄 API，并应先把范围限制为远程 HTTPS MCP。

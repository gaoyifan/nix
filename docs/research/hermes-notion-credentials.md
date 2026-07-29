# Hermes Nix 的 Notion 接入方案

> 结论基于本仓库当前部署、锁定的 Hermes
> [`3ef6bbd201263d354fd83ec55b3c306ded2eb72a`](https://github.com/NousResearch/hermes-agent/tree/3ef6bbd201263d354fd83ec55b3c306ded2eb72a)
>（v0.19.0），以及 2026-07-29 的 Notion 官方文档。未读取任何真实凭据。

## 结论

在需求明确为“**主要从 Hermes Desktop 交互使用**”且“**可以接受按 Notion 用户完整权限访问**”后，最佳实现不是继续配置 `NOTION_API_KEY`，而是：

1. 由 Nix 声明官方 Notion MCP：`https://mcp.notion.com/mcp`、`auth = "oauth"`；
2. 为每个实例声明其规范 HTTPS Dashboard URL，供 Hermes 生成 OAuth callback；
3. 用户在 Desktop 的 **Capabilities（能力）→ MCP → Notion** 中自行完成 OAuth；
4. OAuth token 由 Hermes 保存在该用户、该 Profile 的 `$HERMES_HOME/mcp-tokens/`，不经过管理员，也不进入 Git、Nix store、Shell 历史或模型消息。

这利用了 Hermes NixOS module 已有的 `mcpServers` interface。Nix 只管理非敏感的连接定义，用户只管理自己的 OAuth grant，seam 清晰且无需维护上游补丁。Notion 也把官方托管 MCP 作为多数 AI 工具用户的推荐路径；它使用 OAuth，不接受静态 bearer token（[Notion MCP 官方接入文档](https://developers.notion.com/guides/mcp/get-started-with-mcp)）。

本仓库已在共享的 [`guest.nix`](../../nixos/optional/hermes-nspawn/guest.nix) 中声明该 MCP；2026-07-29 已部署到 `somo-minisforum` 上全部 15 个 Hermes nspawn 实例。

## 用户反馈为何会出现

用户收到的 `hermes config set NOTION_API_KEY ...` 是面向普通、非托管安装的通用建议，**不适用于当前 Hermes Nix 部署**：

- 上游确实登记了 `NOTION_API_KEY`，但类别是 `category="skill"`（[`config.py:4112–4130`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/hermes_cli/config.py#L4112-L4130)）；
- Desktop 的 Tool Keys 只渲染 `tool`，没有渲染 `skill`，所以 Notion 不会出现在该页面（[`keys-settings.tsx:20–29,54–60`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/apps/desktop/src/app/settings/keys-settings.tsx#L20-L60)）；
- 当前 guest 设置了 `HERMES_MANAGED=true`，上游会在判断 key 是否应写入 `.env` **之前**阻止 `hermes config set`，底层 env writer 也再次阻止（[`config.py:351–359,7957–7977,8721–8755`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/hermes_cli/config.py#L351-L359)）；
- 本仓库的 backend 和 Gateway 均由 systemd 托管并读取只读 `/etc/hermes/.env`（[`guest.nix:356–410`](../../nixos/optional/hermes-nspawn/guest.nix#L356-L410)），因此上游提示“由管理员配置”符合现有 managed-mode 语义。

所以不要继续尝试取消 `HERMES_MANAGED`、删除 `.managed` marker，或把 token 写进聊天、工单和命令参数。

## 为什么 MCP 是本需求下更好的 module

### 1. 最小 interface

Canary 只需要：

```nix
services.hermes-agent = {
  mcpServers.notion = {
    url = "https://mcp.notion.com/mcp";
    auth = "oauth";
    connect_timeout = 315;
  };
  settings.dashboard.public_url = "https://<user>.hermes.dengdengli.com";
};
```

本仓库通过 `services.hermes-nspawn.dashboardDomain` 为所有用户生成第二项。它不能省略：Notion 拒绝非 loopback 的 HTTP redirect URI，而反向代理路径中的 Dashboard 不能可靠地从请求重建外部 HTTPS scheme。

`connect_timeout = 315` 同样不能省略。Hermes v0.19.0 的 Dashboard OAuth 调用虽然把外层 probe timeout 提高到 315 秒，但内层 `MCPServerTask` 仍读取 server config，缺省在 60 秒取消 `session.initialize()`。算上 discovery 和 DCR，授权 state 在约 48 秒后被 retry flow 替换；用户完成旧页面时就会看到 `OAuth flow expired`。把 server 自身的连接超时设为 315 秒后，原 state 在 100 秒等待中保持稳定，延迟 70 秒的 callback 也返回 200。

上游 NixOS module 原生支持声明 HTTP MCP 和 OAuth，并明确把 token 持久化到 `$HERMES_HOME/mcp-tokens/<server>.json`（[`nix-setup.md:465–490`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/website/docs/getting-started/nix-setup.md#L465-L490)）。

### 2. 不破坏 managed mode

`HERMES_MANAGED` 继续保护 Nix 声明的配置。管理员负责声明“存在一个 Notion MCP server”；用户只对这个已存在的 server 完成 OAuth。Desktop 已有 MCP OAuth browser flow，会把凭据写入 profile-scoped token storage，而不是通过被锁定的通用 config/env 页面（[`web_server.py:12195–12443`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/hermes_cli/web_server.py#L12195-L12443)、[`mcp-tab.tsx:574–631`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/apps/desktop/src/app/skills/mcp-tab.tsx#L574-L631)）。

### 3. 凭据不进入 Terminal

静态 Notion skill 会在加载后把 `NOTION_API_KEY` allowlist 到 Docker terminal；这意味着 terminal 中运行的代码能够读取该 token（[`skills_tool.py:1484–1521`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/tools/skills_tool.py#L1484-L1521)、[`docker.py:1020–1055`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/tools/environments/docker.py#L1020-L1055)）。MCP OAuth token 则留在 Hermes 的 MCP client/token store 中；`mcp-tokens/` 也属于 Hermes 明确保护的凭据目录。

### 4. 用户不必向管理员披露 token

Notion 官方要求把 token 当作密码，不应发到群聊、邮件、工单或源码；OAuth 方案让用户直接在 Notion 页面授权远程 Hermes backend，管理员只部署非敏感 endpoint（[Notion API key 安全建议](https://developers.notion.com/guides/get-started/handling-api-keys)）。

## 权限和适用边界

官方 Notion MCP 以完成授权的 Notion 用户身份工作，能够访问该用户有权访问的内容。用户已确认接受这一范围；但仍应注意：

- 这是“用户完整权限”模型，不是只授权几个页面的 bot；
- 应只连接官方 endpoint `https://mcp.notion.com/mcp`；
- Notion 当前说明 MCP 不支持文件上传；需要该能力时仍要用 REST API；
- OAuth 需要初次浏览器授权，长期无人值守任务还要考虑 token 到期后的重新授权。

如果需求改为以下任一情况，应改用静态 internal connection，而不是 MCP：

- 只能访问明确选定的页面/数据库；
- Gateway/cron 必须长期无人值守；
- 依赖原始 REST、文件上传或 `ntn`/Workers 的完整能力。

此时 token 应从 Nix store 外的 per-user runtime secret 注入，或者临时安全写入对应 profile 的 `$HERMES_HOME/.env`；不能把 token 写成 Nix 字符串。Internal connection 还必须在 Notion 中显式获得目标页面访问权（[Notion internal connection 官方文档](https://developers.notion.com/guides/get-started/internal-connections)）。

## 上线状态与用户验收

2026-07-29 已完成 NixOS switch。部署后的 15 个实例均满足：

- `mcp_servers.notion` 为 `url = https://mcp.notion.com/mcp`、`auth = oauth`、`enabled = true`、`connect_timeout = 315`；
- `dashboard.public_url` 指向各用户自己的 HTTPS Dashboard 域名；
- `hermes-agent.service` 与 `hermes-dashboard.service` 均为 active；
- 所有 15 个 HTTPS Dashboard 登录端点均返回 200；实际 Notion 动态客户端注册已从 `invalid_redirect_uri` 变为 `authorization_required`。

每位用户仍需自行完成一次授权：

1. 使用 Hermes Desktop 连接自己的 remote backend；
2. 打开 **Capabilities → MCP → Notion**，点击 Authenticate；
3. 在浏览器确认域名为 Notion 官方域名并完成授权；
4. 返回 Desktop，确认 Notion MCP probe 能列出工具；
5. 新开会话，分别验证搜索、读取和一次可撤销的写入。

若 Gateway/cron 也要使用，OAuth 完成后需重启实际的 `hermes-agent.service`/Gateway，并单独验收；Desktop backend 与 Gateway 是两个进程，不能假定前者的 live reconnect 会刷新后者。无需给任何实例注入 `NOTION_API_KEY`，也不应 fork 上游去放宽 managed credential writer。

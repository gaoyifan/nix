# Hermes terminal 共享工作区映射评估

## 结论

**建议映射。** 对当前 `hermes-nspawn` 部署，应把 nspawn 实例内的
`/var/lib/hermes/workspace` 以可读写 bind mount 暴露为 terminal 容器的
`/workspace`。这样 Dashboard/agent 所认定的工作目录与 terminal、file tool、
`execute_code` 实际操作的目录才是同一棵文件树。对当前锁定版本和 Dashboard 运行方式，
建议使用显式 `docker_volumes`，同时保留容器内 `terminal.cwd=/workspace`。

这不是“让现有 sandbox workspace 更持久”：上游默认目录本来就是宿主侧持久化
bind mount。变化在于把**按 terminal task/profile 管理的运行时目录**替换为
**该 hermes-nspawn 用户的规范共享工作区**。代价是 `/workspace` 不再具有 task 或
profile 级文件隔离；terminal 中的代码可以直接修改或删除该用户的共享文件。当前架构
一名用户一个 nspawn 实例，且物理宿主只向实例传入 `/dev/kvm` 和只读 secrets，因而该
风险边界仍限于该用户实例，符合此部署的共享工作区目标
（[`hermes-nspawn.nix:170–199`](../nixos/optional/hermes-nspawn.nix#L170-L199)）。

本报告针对 flake 当前锁定的 Hermes rev
[`3c27eb6234bf91b8ceee9e9071591b31e9b148cb`](../flake.lock#L223-L246)（tag
`v2026.8.3`）。下文较早调查留下的固定链接仍指向当时的
`3ef6bbd201263d354fd83ec55b3c306ded2eb72a`；本次针对 `/root` 与 `/workspace`
定位的结论已在当前锁定版本重新核对，见下一节。

## 官方对 `/root` 与 `/workspace` 的定位

官方把它们设计成两个独立路径，而不是同一目录的两个名字：持久模式创建
`<sandbox>/home` 和 `<sandbox>/workspace` 两个宿主目录，分别 bind mount 到 `/root`
和 `/workspace`。`/root` 是容器 root 用户的 home，也是 Docker backend 的默认 cwd；
`/workspace` 是工作区，并且是官方提供给用户挂入启动目录或其他宿主项目的接口
（[`docker.py:835–876,926–973`](https://github.com/NousResearch/hermes-agent/blob/3c27eb6234bf91b8ceee9e9071591b31e9b148cb/tools/environments/docker.py#L835-L876)、
[`terminal_tool.py:1498–1533`](https://github.com/NousResearch/hermes-agent/blob/3c27eb6234bf91b8ceee9e9071591b31e9b148cb/tools/terminal_tool.py#L1498-L1533)）。
官方 volume 文档也把 `/workspace` 用于接收 agent 生成的文件和共享工作区；启用
`docker_mount_cwd_to_workspace` 后，file tools 与 terminal 会看到同一份项目
（[`configuration.md:470–504,538–561`](https://github.com/NousResearch/hermes-agent/blob/3c27eb6234bf91b8ceee9e9071591b31e9b148cb/website/docs/user-guide/configuration.md#L470-L504)）。

两者的持久化开关相同，但目录仍然分离：`container_persistent=true` 时两个目录均为
bind mount；关闭时 `/root` 与 `/workspace` 分别使用 tmpfs，清理后消失
（[`docker.py:958–982`](https://github.com/NousResearch/hermes-agent/blob/3c27eb6234bf91b8ceee9e9071591b31e9b148cb/tools/environments/docker.py#L958-L982)、
[`security.md:480–483`](https://github.com/NousResearch/hermes-agent/blob/3c27eb6234bf91b8ceee9e9071591b31e9b148cb/website/docs/user-guide/security.md#L480-L483)）。
普通 session、`/new` 和 `delegate_task` 子 agent 的 task id 会折叠为 `default`，所以共用
一个容器、一个 `/workspace` 和一套安装状态；只有带 backend/image override 的评测 task
才得到独立 sandbox。profile 则有独立 `HERMES_HOME`，Docker 容器的复用与清理也同时按
task id 和 profile label 隔离
（[`terminal_tool.py:1274–1306`](https://github.com/NousResearch/hermes-agent/blob/3c27eb6234bf91b8ceee9e9071591b31e9b148cb/tools/terminal_tool.py#L1274-L1306)、
[`configuration.md:260–286`](https://github.com/NousResearch/hermes-agent/blob/3c27eb6234bf91b8ceee9e9071591b31e9b148cb/website/docs/user-guide/configuration.md#L260-L286)、
[`profiles.py:1–19`](https://github.com/NousResearch/hermes-agent/blob/3c27eb6234bf91b8ceee9e9071591b31e9b148cb/hermes_cli/profiles.py#L1-L19)）。

因此，不建议把整个 `/root` 与 `/workspace` 映射到同一目录或互相软链接：

- 上游没有这样的配置模式或建议；源码有意把 `home` 与 `workspace` 建成 sibling 目录。
- backend 始终自动挂载 `/root`，但只为显式 `/workspace` mount 提供跳过默认挂载的检测；
  再用 `docker_volumes` 挂 `/root` 会形成重复目标，而不是受支持的“合并 home”开关
  （[`docker.py:931–988`](https://github.com/NousResearch/hermes-agent/blob/3c27eb6234bf91b8ceee9e9071591b31e9b148cb/tools/environments/docker.py#L931-L988)）。
- 镜像内把 `/root` 做成软链接也不会生效，因为运行时 bind mount 会覆盖该路径；在宿主侧
  人为把 `home` 与 `workspace` 链到一起则会把 shell、包管理器和工具的 home 状态混入用户
  项目，并放大 Dashboard/Desktop 可读取的目录范围。

技术上可以修改 backend，或在容器外人为安排两个 mount 使用同一 source，但这偏离官方
布局，且没有解决文件交付所需的最小问题。合理做法仍是保留 `/root` 作为 terminal home，
只把待交付文件写入 `/workspace`。还需区分：官方并不保证容器 `/workspace` 天生对
Dashboard/gateway 可见，甚至建议消息附件使用单独的宿主可见 `/output` mount；本部署之所以
能从 Dashboard/Desktop 下载 `/workspace` 文件，是
`/var/lib/hermes/workspace:/workspace` 这条显式共享契约
（[`configuration.md:488–496`](https://github.com/NousResearch/hermes-agent/blob/3c27eb6234bf91b8ceee9e9071591b31e9b148cb/website/docs/user-guide/configuration.md#L488-L496)）。

截至上游 main
[`25c7827ec95c5f41cc90b1eeb147b92f0032ad3d`](https://github.com/NousResearch/hermes-agent/commit/25c7827ec95c5f41cc90b1eeb147b92f0032ad3d)
（2026-08-05），`docker.py`、sandbox directory 实现及上述 workspace/profile 文档相对
flake 锁定 rev 均无相关语义变化；其间改动集中在其他 terminal 行为和辅助任务配置。

## 两个 workspace 的语义

| 路径 | 所有者与用途 | 生命周期/隔离 |
|---|---|---|
| `/var/lib/hermes/workspace` | Hermes NixOS 模块的 `workingDirectory` 默认值；本仓库 Dashboard 也从这里启动。它位于 `HERMES_HOME=/var/lib/hermes/.hermes` **之外**，是该 nspawn 用户的规范工作区。 | Nix 创建为 `agent:agent`、`2770`；随 nspawn 状态长期保留。见 [`guest.nix:253–262,390–408`](../nixos/optional/hermes-nspawn/guest.nix#L253-L262) 和上游 [`nix/nixosModules.nix:248–260,708–731`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/nix/nixosModules.nix#L248-L260)。 |
| `~/.hermes/sandboxes/docker/<task_id>/workspace` | Docker backend 自建的宿主侧目录；本部署实际根为 `/var/lib/hermes/.hermes/sandboxes/docker/<effective_task_id>/workspace`。 | `container_persistent=true` 时挂到 `/workspace`；显式 volume 已占用 `/workspace` 后，上游不再创建/挂载它。`/root` 仍来自同一 task 下的 `home`。见 [`base.py:182–194`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/tools/environments/base.py#L182-L194) 和 [`docker.py:645–707`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/tools/environments/docker.py#L645-L707)。 |

另有一个同名但无关的概念：本仓库的 Honcho `workspace` 是
`hermes-nix-<user>` 这一记忆服务逻辑命名空间，不是文件路径
（[`hermes-nspawn.nix:17–28`](../nixos/optional/hermes-nspawn.nix#L17-L28)）。

## 收益与文件交付

当前 image 和 terminal 配置都以 `/workspace` 为 cwd，但 Dashboard 的进程 cwd 是
`/var/lib/hermes/workspace`；现有 `docker_volumes` 只包含 skills 和 Lark 状态，并未连接
二者（[`terminal.nix:103–132`](../nixos/optional/hermes-nspawn/terminal.nix#L103-L132)）。映射后：

- Dashboard、terminal 和 file tool 对相对路径得到同一文件，agent/terminal 重建后成果仍在；
- Desktop 的 `file.attach` 会把客户端文件写入 session workspace 下的
  `.hermes/desktop-attachments/`，再返回 workspace 相对引用；映射后该引用可在 terminal
  中直接读取。未映射时，文件落在规范工作区，而相同相对路径在 sandbox workspace 中并
  不存在（上游 [`tui_gateway/server.py:10867–11026`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/tui_gateway/server.py#L10867-L11026)）；
- 消息平台下载的文档、图片、音频等本来就由 Hermes cache 以只读方式自动挂入 terminal，
  因此入站媒体不依赖此映射
  （[`credential_files.py:1–18,385–422`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/tools/credential_files.py#L1-L18)）；
- 出站 `MEDIA:` **不会自动把** `/workspace/report.pdf` 翻译成宿主路径。文件虽然可在
  `/var/lib/hermes/workspace/report.pdf` 被 Dashboard 读取，模型仍须发送宿主可见路径
  `MEDIA:/var/lib/hermes/workspace/report.pdf`；若要更稳妥的通用附件出口，应另设专用
  `/output` → Hermes documents cache 映射。上游明确要求发送宿主路径，并会在缺少
  `/output` 映射时警告
  （[`configuration.md:430–456`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/website/docs/user-guide/configuration.md#L430-L456)、
  [`gateway/run.py:3473–3517`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/gateway/run.py#L3473-L3517)）。

## task、profile 与隔离影响

上游普通顶层调用和 `delegate_task` 子任务会把 task id 折叠为 `default`，共享同一容器、
`/workspace` 和已安装软件；只有带 backend/image override 的评测任务保留独立 task id
（[`terminal_tool.py:1175–1207`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/tools/terminal_tool.py#L1175-L1207)）。因此通常所谓默认目录实际是
`.../docker/default/workspace`，并非每个会话一份。上游也明确说明 `/new`、session 和普通
subagent 共享长寿命容器
（[`configuration.md:205–209,254–280`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/website/docs/user-guide/configuration.md#L205-L209)）。

profile 的 `HERMES_HOME`、配置、凭据、session 和记忆仍各自隔离；上游容器复用标签也含
`hermes-profile`。但把固定的 agent 工作目录映射到 `/workspace`，会让所有采用这份 terminal
配置的 profile 共享文件，即使它们使用不同 terminal 容器；带独立 image override 的 task
也会挂到同一目录。对当前“一名用户一个 nspawn/一个信任域”的部署，这是所需语义；若
profile 被当成不同安全租户，则不应采用该映射。上游 profile 隔离定义见
[`profiles.py:1–19`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/hermes_cli/profiles.py#L1-L19)。

安全边界仍保留 gVisor KVM、cap-drop、`no-new-privileges` 和资源限制，但 bind mount 有意
开放了这一目录：容器内依赖、提示注入或误命令可读取、覆盖、删除其中全部文件。Hermes
会识别 `docker_volumes` 中的宿主路径，并让危险命令经过 approval，而不是按“完全隔离
容器”跳过检查。现有 skills/Lark volume 已是绝对宿主路径，所以本次不会新切换 approval
模式，但会显著扩大可写宿主数据面
（[`terminal_tool.py:260–278`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/tools/terminal_tool.py#L260-L278)、
[`approval.py:2856–2883`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/tools/approval.py#L2856-L2883)）。不要扩大到
`/var/lib/hermes` 或 `.hermes`；后者含凭据和状态数据库。

## 所有权与最小 Nix 形状

本仓库的 agent 是 UID/GID 1000，而 terminal image 默认以 root 运行
（[`guest.nix:94–105`](../nixos/optional/hermes-nspawn/guest.nix#L94-L105)）。因此可写 bind
中的新文件可能是 nspawn UID 0、GID 1000；这与当前默认 sandbox workspace 的实际行为
一致，但 agent 用户未必能改写 mode `0644` 的 terminal 成果。上游提供
`docker_run_as_host_user=true` 解决属主问题，但也明确说明这会失去 `apt install` 以及写
`/root` 中 root-owned 路径的能力
（[`configuration.md:484–496`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/website/docs/user-guide/configuration.md#L484-L496)）。

不要假定现有 Lark volume 的 `idmap=uids=1000-0-1;...` 能解决 workspace 属主：在当前
Podman + runsc 实机探针中，gVisor 内 root 新建的文件在 nspawn 侧仍是 UID 0。上线验收应
据真实双向写入需求决定是接受 `root:agent`、改为 `docker_run_as_host_user`，还是另行设计
权限策略；不应在未经验证时复制该 idmap。

上游确实提供了“把启动目录挂到 `/workspace`”的正式开关
（[`configuration.md:498–521`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/website/docs/user-guide/configuration.md#L498-L521)、
[`terminal_tool.py:1394–1417`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/tools/terminal_tool.py#L1394-L1417)），但当前锁定版本的
Dashboard 还存在双重 cwd 语义：宿主侧 session/file attachment 需要
`/var/lib/hermes/workspace`，terminal 则需要 `/workspace`。Dashboard 会把配置中的非本地
cwd 原样注册为 per-session override；terminal 创建时虽然已把宿主 cwd 映射成
`/workspace`，原始 override 随后仍可能重新胜出
（[`tui_gateway/server.py:1779–1817`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/tui_gateway/server.py#L1779-L1817)、
[`terminal_tool.py:2182–2205`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/tools/terminal_tool.py#L2182-L2205)）。`/var/lib/...` 又不在
该版本只列举 `/home`、`/Users` 和 Windows 路径的 host-cwd 拒绝前缀中。直接把
`terminal.cwd` 改成 `/var/lib/hermes/workspace` 因此有让 terminal 尝试使用容器内不存在
路径的风险。

对该锁定版本，最小且稳定的 Nix 形状是在
`nixos/optional/hermes-nspawn/terminal.nix` 的现有列表中加入显式映射：

```nix
volumes = [
  "${managedSkills}:${managedSkills}:ro"
  "/var/lib/hermes/workspace:/workspace"
  "/var/lib/hermes/.lark-cli:/root/.lark-cli:idmap=uids=1000-0-1;gids=1000-0-1"
  "/var/lib/hermes/.local/share/lark-cli:/root/.local/share/lark-cli:idmap=uids=1000-0-1;gids=1000-0-1"
];
```

保留现有 `terminal.cwd = "/workspace"` 和 `docker_volumes = terminal.volumes`，不要同时开启
`docker_mount_cwd_to_workspace`。Hermes 的 Docker backend 检测到显式 `/workspace` 后会跳过
默认 `.../sandboxes/docker/<task>/workspace` 挂载。挂载之外还应修订现有 system prompt：
说明该目录由同一用户的普通 session/subagent/profile 共享，并要求发送附件时把
`/workspace/<相对路径>` 写成 `MEDIA:/var/lib/hermes/workspace/<相对路径>`；这不属于挂载
生效所需的最小 Nix 改动。

## 迁移影响与上线条件

1. 先盘点并备份 `/var/lib/hermes/workspace` 以及
   `/var/lib/hermes/.hermes/sandboxes/docker/*/workspace`。共享映射启用后，后者不会删除，
   但会从 `/workspace` 隐藏；需要保留的内容应先按业务语义合并到规范工作区，不能直接
   覆盖。
2. 配置生效时必须排空 terminal 后台任务，并删除一次带 `hermes-agent=1` 标签的旧 terminal
   容器。上游跨进程复用只比较 task/profile 标签，**不比较 image、mount 或资源**，所以仅
   restart agent 可能继续复用旧 mount
   （[`docker.py:857–896`](https://github.com/NousResearch/hermes-agent/blob/3ef6bbd201263d354fd83ec55b3c306ded2eb72a/tools/environments/docker.py#L857-L896)）。
3. 历史 session 若已经记录 `/workspace`，此次变更不需要改 DB cwd；它只改变该路径背后的
   文件树。其他旧绝对路径的重写属于独立迁移。
4. 验收至少覆盖：terminal 与 Dashboard 双向读写同一文件并核对实际 UID/GID 和 mode、
   agent 与 terminal 容器重建后仍可见、Desktop 上传可读、`MEDIA:` 使用宿主路径可发送，
   以及 terminal 不能通过 workspace mount 越界访问 `.hermes`（上游自动挂载的只读
   cache/skills 除外）。

综上，映射应作为此 hermes-nspawn 用户工作区的明确共享契约上线，同时保留旧 sandbox
目录直到完成内容核对，并把“profile/task 文件隔离已放弃”记录为该部署的有意选择。

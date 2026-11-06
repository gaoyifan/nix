# Hermes 自定义增强移植到 Rakazo 的评估

本文记录实施前的调查状态。随后已完成长音频转录、Office/OCR 与文档 Skills、
视频处理和 Codex CLI 的安装及部署；Codex 授权按用户要求暂不处理。
实施与验证结果见 [Rakazo 部署记录](../rakazo-microvms.md#computer-tools-and-skills)。

调查日期：2026-11-06。范围是本仓库**额外给 Hermes 加上的能力**，不做两款产品功能数量排名，也不将“Rakazo 未配置”写成“Rakazo 不支持”。Hermes 锁定 `b200f5bc60e31588ba2cb60e288029c4a54ba5fa`，Rakazo 锁定 `46e95fa8314324cbcf6e4e33c7ed06dbbc68b923`；本仓库部署基线为 `be88dfd`。

## 移植清单

| 我们给 Hermes 添加的能力 | Rakazo 当前声明镜像 / 原生替代 | 分类与优先级 |
|---|---|---|
| 文档工具链：LibreOffice、Tesseract 英文/简中、qpdf、node-docx，以及 markitdown、pdf2image、pdfplumber、Pillow、pypdf、python-pptx、pytesseract、reportlab 等 | 上游电脑镜像已有 `poppler-utils`、`pandoc`、`python3-openpyxl`、Python、uv；本仓库 Rakazo 镜像层仅额外装 Tushare。完整 Office/OCR 工具链是可以复用的实际增量。 | **直接移植，P1**：在现有电脑镜像层固化缺少的程序和 Python/Node 依赖。优先覆盖扫描件 OCR、Office 转 PDF、DOCX/PPTX 生成与检查。[Hermes 环境](../../nixos/optional/hermes-nspawn/terminal.nix#L9-L95)、[Rakazo 镜像](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/infra/sandboxes/computer/Dockerfile#L25-L74)、[本地扩展](../../nixos/hosts/el2/services/rakazo/computer.nix) |
| Anthropic `docx/xlsx/pdf/pptx` Skills、`open-kimi-ppt` | Rakazo 有原生 Skill 库、GitHub 导入和附属文本文件读取；导入 Skill 并不会自动安装/运行其中脚本。 | **知识内容可移植，运行部分需适配，P1**：Skill 与依赖环境一起移植，调整 `/workspace`、`/root`、辅助脚本路径及交付文件规则；`open-kimi-ppt` 还要成套携带渲染/导出脚本和参考文件，详见下节。[声明来源](../../nixos/optional/hermes-nspawn/guest.nix#L54-L60)、[Rakazo Skills 说明](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/docs/skills.md#L11-L31)、[附属文件读取](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/adapters/src/skill-tools.ts#L127) |
| 音频转录 Skill、`transcribe-audio` / `estimate-transcription-time` | Rakazo 有原生语音转录入口，但当前两个用户没有配置 Voice 凭据；电脑镜像也没有我们的两条转录命令及 ffprobe。 | **优先移植，P1**：保留现有长文件转录流程，脚本与 Skill 小幅适配即可复用；原生 Voice 用来另行解决语音消息/麦克风入口，不能直接替代原脚本协议和长任务处理。详见下节。[现有声明](../../nixos/optional/hermes-nspawn/terminal.nix#L52-L58)、[Skill](../../nixos/optional/hermes-nspawn/skills/audio-transcription/SKILL.md)、[Rakazo 语音消息入口](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/docs/messaging-apps.md#L22-L24) |
| `ffmpeg`、`yt-dlp[default,curl-cffi]`、Deno/Node 的视频站点处理环境 | 上游电脑镜像已有 uv/uvx，但当前基础包列表及本地 Tushare 扩展没有声明上述媒体工具。 | **直接移植，P1/P2**：如果继续处理视频链接/下载媒体，和音频转录一起配齐；只移植 `yt-dlp` 包不足以复现当前 wrapper 的 curl-cffi、JS runtime 和 EJS 配置。[wrapper 与包](../../nixos/optional/hermes-nspawn/terminal.nix#L47-L50)、[EJS 配置](../../nixos/optional/hermes-nspawn/terminal.nix#L100-L102)、[Rakazo 基础镜像](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/infra/sandboxes/computer/Dockerfile) |
| Codex CLI 的 NewAPI wrapper；编程任务默认交给 Codex | Rakazo 可以通过原生 `shell` 运行编码 CLI，也有 `run_subagent`；但当前电脑镜像没有 Codex/Nix/npm，聊天模型的 Codex OAuth 也不等于 CLI 已经获授权。 | **需适配，P2**：复用路由/模型配置意图；现有 wrapper 用 `nix run github:gaoyifan/nix#codex`，不能脱离 Nix 环境直接复制。建议为 CLI 固化可执行文件及必要运行环境，并通过 Space 的命令凭据提供 `NEWAPI_API_KEY`；这是移植方案判断，尚未实施。[wrapper](../../nixos/optional/hermes-nspawn/terminal.nix#L38-L45)、[当前 Hermes 指令](../../nixos/optional/hermes-nspawn/guest.nix#L268-L274)、[Rakazo shell / 子代理](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/adapters/src/builtin-tools.ts#L465-L475)、[命令凭据](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/adapters/src/bot-secrets.ts#L199-L242) |
| 飞书 `lark-cli`、整套 `lark-*` Skills，以及每实例的 CLI 授权目录 | Rakazo 原生支持飞书聊天入口、MCP/OpenAPI/GraphQL 集成；聊天入口和完整飞书工作台 CLI 不是同一件事。 | **需适配，按使用频率 P1/P2**：保留既有 CLI 工作流时移植 CLI + Skills，并重新设计每用户/Space 的授权与持久化；不要把原来某个实例的 `.lark-cli` 目录或 App Secret 全局共享给所有 Bot。[Skills](../../nixos/optional/hermes-nspawn/guest.nix#L54-L60)、[初始化授权](../../nixos/optional/hermes-nspawn/guest.nix#L319-L345)、[原目录挂载](../../nixos/optional/hermes-nspawn/terminal.nix#L147-L151)、[Rakazo 聊天入口](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/docs/messaging-apps.md#L1-L12)、[自定义集成](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/docs/integrations.md#L24-L38) |
| `newapi-codex` 图片生成/编辑插件，通过 codex-api 调用 `gpt-image-2` | Rakazo 有 `generate_image` / `generate_video` 工具，但是否已接入我们现有 codex-api 后端需单独配置、核对协议。 | **需适配后端，P2**：复用 API 服务和每用户授权，不搬 Hermes 插件类；该插件直接依赖 Hermes `ImageGenProvider` 和图片路由模块。[自定义插件](../../nixos/optional/hermes-nspawn/newapi-codex/__init__.py#L1-L35)、[原生工具](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/adapters/src/builtin-tools.ts#L252-L275) |
| 微信二维码接入工具 `weixin_channel` 与 Hermes 微信通道 | Rakazo 此版本内置聊天通道列表有 Slack、Telegram、WhatsApp、iMessage/SMS、飞书，没有微信；本地插件直接调用 Hermes 的 `plugins.platforms.weixin` 与 Gateway 状态/重启接口。 | **需要专门开发，P3，除非微信为迁移前提**：不能仅拷贝 Skill 或 Python 插件；需处理微信连接、登录状态、收发消息及 Rakazo 账号/Bot 绑定。[本地工具入口](../../nixos/optional/hermes-nspawn/weixin-channel/plugin.yaml)、[Hermes 耦合代码](../../nixos/optional/hermes-nspawn/weixin-channel/__init__.py#L19-L23)、[Rakazo 平台工厂](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/adapters/src/messaging-platforms.ts) |
| 自托管 Honcho 服务、Hermes Honcho 记忆插件 | Rakazo 已原生支持 Honcho，允许只读召回既有 User peer，并往自己的 peer 写新事实；原生语义是显式存事实，聊天摘要留在 Rakazo。 | **优先原生接入，P2，不复制插件**：先验证现有用户 peer、记忆范围和私网访问授权。现有 Honcho 镜像为 3.0.12，而 Rakazo 文档要求 Honcho 3.2+ 才支持忘记已存事实；不能把“能配置 URL”当成全链路兼容已验证。[现有服务](../../nixos/optional/hermes-nspawn/honcho.nix#L10-L16)、[插件封装](../../pkgs/honcho-plugin.nix)、[Rakazo 既有 peer 只读规则](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/docs/memory.md#L29-L45)、[自托管约束及 3.2 要求](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/docs/self-host-integrations.md#L30-L43) |

## 音频转录应保留的部分

我们的 `transcribe_audio.py` 是 Python 标准库脚本，向现有 whisper.cpp 服务的 `/inference` 发整个文件，要求 `verbose_json` 并保留分段时间戳，默认中文与 7200 秒请求超时；`estimate_transcription_time.py` 依赖 ffprobe，并使用已有测得的速度比。它们的价值是复用现有 ASR 服务及长录音工作流，不是让 Bot 在本机重新部署语音模型。[转录实现](../../nixos/optional/hermes-nspawn/skills/audio-transcription/scripts/transcribe_audio.py#L19-L25)、[请求协议](../../nixos/optional/hermes-nspawn/skills/audio-transcription/scripts/transcribe_audio.py#L93-L126)、[估时依赖](../../nixos/optional/hermes-nspawn/skills/audio-transcription/scripts/estimate_transcription_time.py#L14-L40)。

Rakazo 的原生自托管 Voice 转录调用 `/v1/audio/transcriptions` 并取 `{text}`，有 8 MiB 音频上限和 60 秒转录截止时间；与现有 `/inference` 接口、长录音及分段时间戳输出不等价。因此先移植两条命令、补 ffmpeg/ffprobe，再改写 Skill 是较小的变更。[自托管 Voice 实现](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/adapters/src/openai-compatible-voice.ts#L391-L425)、[输入上限](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/adapters/src/voice-factory.ts#L138)、[60 秒截止时间](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/adapters/src/openai-compatible-voice.ts#L38-L42)。

Skill 中的 `terminal(background=true)` 和 `process(poll/wait)` 是 Hermes 工具协议，移植时要改为 Rakazo `shell` 支持的独立后台 `nohup ... < /dev/null > log 2>&1 &`、读取日志/结果文件的流程，路径改为 Bot workspace，需要交付的结果走 `exports/` 和 `attach_file`。旧脚本自身允许两小时请求，并不意味着 Rakazo 前台 shell 会等两小时：其命令默认五分钟、可配置最大一小时。[原 Skill](../../nixos/optional/hermes-nspawn/skills/audio-transcription/SKILL.md#L19-L37)、[Rakazo shell 约定](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/adapters/src/builtin-tools.ts#L465-L475)、[命令超时](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/core/src/sandbox-command.ts#L1-L27)。

## open-kimi-ppt 的具体依赖

本仓库 Flake 使用 `gaoyifan/open-kimi-ppt-skill`，固定在 `faf153b7fa6a027c324a28e6400efa98948c651f`。该 Skill 生成可编辑的 PPTD/YAML 项目及默认配套的扁平化 PPTX，导出脚本借助浏览器渲染，不是一个 Kimi 模型 API key 的包装。[Flake 输入](../../flake.nix#L203-L207)、[锁定 Skill](https://github.com/gaoyifan/open-kimi-ppt-skill/blob/faf153b7fa6a027c324a28e6400efa98948c651f/skills/open-kimi-ppt/SKILL.md#L1-L28)。

其实际链路需要 Node.js 18+、npm/npx、Python、Chromium、agent-browser ≥0.33.2、PyYAML、Pillow 和 websocket-client；`export_pptx_local.py` 还直接依赖 python-pptx。导出时必须能访问 `www.kimi.com` 和 `statics.moonshot.cn`，`export_host.html` 加载远端 SDK，因此不能把“本地生成 PPTX”理解为完全离线。建议与文档工具链一起补依赖、携带 `scripts/` 和 `reference/` 后再导入说明；现有 Rakazo Node/Python/浏览器可复用。[前置条件](https://github.com/gaoyifan/open-kimi-ppt-skill/blob/faf153b7fa6a027c324a28e6400efa98948c651f/skills/open-kimi-ppt/SKILL.md#L22-L28)、[本地导出脚本依赖](https://github.com/gaoyifan/open-kimi-ppt-skill/blob/faf153b7fa6a027c324a28e6400efa98948c651f/skills/open-kimi-ppt/scripts/export_pptx_local.py#L14-L19)、[远端 SDK](https://github.com/gaoyifan/open-kimi-ppt-skill/blob/faf153b7fa6a027c324a28e6400efa98948c651f/skills/open-kimi-ppt/scripts/export_host.html#L35-L43)。

## 实际镜像探测

2026-11-06，主线程在当前声明的新 Rakazo computer 镜像（`s7agxf61zyg4v4gcvh8irivfmcqr5jar-rakazo-computer-context`）上运行了无网络、只读根文件系统的临时探测容器，未启动现有用户 Bot：

- 命令存在：`python3`、`uv`、`node`、`pandoc`、`pdftotext`。
- 命令缺少：`npm`、`nix`、`codex`、`lark-cli`/`lark`、`libreoffice`/`soffice`、`tesseract`、`ffmpeg`/`ffprobe`、`yt-dlp`、`qpdf`、`transcribe-audio`、`estimate-transcription-time`。
- Python 模块存在：PIL、openpyxl、tushare；缺少：markitdown、pdf2image、pdfplumber、pypdf、pptx、pytesseract、reportlab。

两个现有 Bot 容器当前仍绑定旧镜像 `vnzqnwg9vwqqka7hs0awxfchfdi9k562-rakazo-computer-context`，而 supervisor 默认已指向上述新镜像。主线程对旧镜像也做了相同的只读、无网络临时容器探测，以上命令与 Python 模块结果与新镜像一致。后续移植仍需将新增镜像实际应用到现有电脑并验收；本轮未启动或重建用户 Bot。

另用一个临时电脑镜像容器的默认 Docker bridge，对脚本配置的两个现有 ASR 端点执行 `/health` GET，均返回 HTTP 200。只验证健康与该临时网络可达，未上传音频、未进行完整转录；现有 Bot 的实际网络及长文件任务仍需在实施验收时验证。Rakazo 数据库中的 `user_voice_credentials` 与 `space_voice_preferences` 计数当前均为零，表示原生 Voice 尚未配置。

## 无需重复移植的部分

- 浏览器、终端、文件交付、定时任务、子代理和基础记忆都有 Rakazo 原生入口；应迁移既有 Skill/任务的业务逻辑和配置，而不是把 Hermes 同名工具接口搬过去。[电脑与文件](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/docs/computer.md)、[定时/变化监听/Webhook](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/docs/routines.md)、[工具清单](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/adapters/src/builtin-tools.ts)。
- `pdftotext`/`pdfinfo`、Pandoc、openpyxl、Chromium、agent-browser、Python、uv、git、gh 等已由 Rakazo 上游电脑镜像提供；增加文档工具时不必再单独搭建第二套重复基础环境。[上游镜像声明](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/infra/sandboxes/computer/Dockerfile#L25-L156)。
- Hermes 的 gVisor/Podman `/workspace` 挂载、容器重建脚本、Dashboard 工作区兼容、apt/Nix 缓存配置属于原部署运行机制，不能作为用户功能整套复制。Rakazo 当前是共享 MicroVM 内的 Docker 电脑，文件及认证应遵循它自己的用户/Space/Team Computer 边界。[原运行机制](../../nixos/optional/hermes-nspawn/guest.nix#L115-L138)、[原工作区挂载](../../nixos/optional/hermes-nspawn/terminal.nix#L107-L158)、[Rakazo Team / Private Computer](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/docs/computer.md#L29-L36)。

## 建议次序与验证边界

建议先完成 **文档/OCR + 文档 Skills** 和 **音视频下载/转录链路**，再按真实使用补 **飞书 CLI**、**Codex CLI** 与 **Honcho 记忆接入**。微信接入的实现成本明显高于给电脑镜像加依赖；若微信是日常入口，则应升为迁移前置条件。此优先级是根据现有声明的依赖复用程度与改动范围作出的判断，不是用户使用频率统计。

本次未安装依赖、导入 Skill、迁移授权或改动服务。表中软件清单结合锁定 Dockerfile、本仓库声明与上述临时镜像探测；已知现有电脑仍使用旧镜像；后续新增依赖必须实际应用到这些电脑，完整业务链路还要用一份 DOCX/PPTX、扫描 PDF、飞书测试文件和既有 CLI 任务做验证。

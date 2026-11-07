# office-kit/pptx 与 Kimi 本地导出的比较证据

核查日期：2026-11-07。Office Kit 固定版本 `18b7e75cfa7fd1c6e9891ce1285a76c7889b644b`：core `@office-kit/pptx` 0.28.0、DSL 0.15.0、preview 0.21.0、dev 0.14.5。本文包含固定版本的源码核查，以及在 el2 实际执行的匹配制作、导出、LibreOffice 渲染、对象检查、单页热重载和修改保存测试。未通过 Rakazo 调用，也未验证桌面 PowerPoint/WPS。

## 架构与可执行路径

Office Kit 是 TypeScript OOXML 读写库加独立 TSX authoring、preview、dev CLI。DSL 有自己的 JSX runtime，不依赖 React/Vue；显式位置布局，普通 TypeScript 函数组合，**不是 CSS/Flex/Grid 自动排版**。TSX 几何尺寸是英寸，字号/边线是点；core 使用显式 EMU/单位转换。现有模板能加载编辑，未知 OOXML parts 旨在保留；这与从 PPTD YAML 编译新 deck 的 Kimi 路线不同。[仓库说明](https://github.com/office-kit/pptx/blob/18b7e75cfa7fd1c6e9891ce1285a76c7889b644b/README.md#L7-L83)、[DSL 文档](https://github.com/office-kit/pptx/blob/18b7e75cfa7fd1c6e9891ce1285a76c7889b644b/packages/dsl/README.md#L11-L60)。

从本地 checkout 使用的官方命令：

```sh
pnpm --filter @office-kit/pptx-dev... build
node packages/dev/dist/cli.mjs dev packages/dsl/examples/review.tsx
node packages/dev/dist/cli.mjs build packages/dsl/examples/review.tsx --out review.pptx
```

普通用户可用 `@office-kit/pptx-dev init` 创建独立项目，安装固定版本依赖后运行项目的 `check`、`build`、`dev`；repo 内包管理器为 pnpm。Node 至少 22.18。core 运行时只依赖 `fflate`，preview 的 Node PNG 路径另外依赖 resvg、fontkit；完整 live editor/CLI 自有额外依赖。不能用 core 的“一个依赖”概括整套制作工具链。[checkout 指令](https://github.com/office-kit/pptx/blob/18b7e75cfa7fd1c6e9891ce1285a76c7889b644b/CLAUDE.md#L25-L48)、[core package](https://github.com/office-kit/pptx/blob/18b7e75cfa7fd1c6e9891ce1285a76c7889b644b/package.json)、[preview package](https://github.com/office-kit/pptx/blob/18b7e75cfa7fd1c6e9891ce1285a76c7889b644b/packages/preview/package.json)。

## 对本次可编辑性比较相关的能力

| 功能 | 源码/文档确认的 Office Kit 行为 | 实测时需要检查 |
|---|---|---|
| 文字、预设形状 | DSL 编译到原生 shape/text 对象，支持富文本段落和组合。 | PPTX XML 中真实文字/形状、Office 打开后排版；不能以截图好看代替对象检查。 |
| 表格 | `<Table>` 调用 core `addSlideTable`，可有单元格富文本、合并、边框和样式。 | 保持 `a:tbl`，单元格内容与合并准确；不是画出一组看似表格的形状。 |
| 图表 | `<Chart spec>` 调用 core `addSlideChart`；文档宣称覆盖全部 16 类 ECMA plot 元素及组合，自动生成可编辑数据工作簿。 | 本次使用的图表类型、数据、图例及 XLSX；“16 类”不是每一种现代 Excel 扩展图。 |
| 渐变 | DSL `fill` 可直接传 `GradientFillOptions`，实际调用 `setShapeGradientFill`。 | OOXML 原生渐变和 Office/预览的一致性。 |
| 图片适配 | DSL `fit` 直接使用 core `ImageFit`，该版本只有 `fill`、`contain`；crop 有 core API。 | 不要凭经验写 `fit="cover"`；裁剪/cover 须另用实际 API 并检查输出。 |
| 动画/转场 | core 有 `setShapeAnimation`、`setSlideTransition`；文档有 95 个 gallery preset，DSL 用 `<Raw>` 才能调用尚无独立 prop 的 core 能力。 | 生成 timing/transition XML；桌面应用播放与浏览器播放是另两层验收。 |
| 编辑既有 PPTX | `Presentation source` 默认 edit 模式，保留未指定幻灯片；compose 模式才重排。 | 对实际输入 roundtrip 验证，不能仅凭新建文件成功推断所有模板兼容。 |

来源：[DSL 元素与样式](https://github.com/office-kit/pptx/blob/18b7e75cfa7fd1c6e9891ce1285a76c7889b644b/packages/dsl/README.md#L62-L218)、[DSL 实际调用](https://github.com/office-kit/pptx/blob/18b7e75cfa7fd1c6e9891ce1285a76c7889b644b/packages/dsl/src/index.ts#L173-L199)、[图片入口](https://github.com/office-kit/pptx/blob/18b7e75cfa7fd1c6e9891ce1285a76c7889b644b/packages/dsl/src/index.ts#L298-L318)、[ImageFit 类型](https://github.com/office-kit/pptx/blob/18b7e75cfa7fd1c6e9891ce1285a76c7889b644b/src/api/fn/shape-image.ts#L39)、[图表/动画/转场说明](https://github.com/office-kit/pptx/blob/18b7e75cfa7fd1c6e9891ce1285a76c7889b644b/README.md#L535-L624)。

## 实际限制，不能由宣传省略

1. **0.x API 未稳定。** minor release 可带破坏性变更，比较和部署应固定完整版本组。新主题/master/layout 从零构建、SmartArt authoring、复杂动画 timing tree、OLE/ActiveX authoring、文档加密仍列为未实现；未知内容 pass-through 不等于能够创建/理解这些功能。[状态和范围](https://github.com/office-kit/pptx/blob/18b7e75cfa7fd1c6e9891ce1285a76c7889b644b/README.md#L231-L266)。
2. **内置预览不是 PowerPoint 排版权威。** Node 无浏览器 PNG 使用 resvg+替代字体；源码文档明确是近似渲染，某些 chart/SmartArt/EMF/3D 会有 fallback 标记。真实文件需由 LibreOffice 或桌面演示软件再看。[preview fidelity](https://github.com/office-kit/pptx/blob/18b7e75cfa7fd1c6e9891ce1285a76c7889b644b/packages/preview/README.md#L200-L235)。
3. **中文字体需要主动处理。** preview 自带 metric-compatible 字体没有中日韩字形；中文 Node 渲染须提供 regular/bold fontFiles，并给 fontkit 测量器同一套字体。否则可能出现字体回退、bold 丢失或换行测量不一致。不能把这个环境问题误判为实际 PPTX 没有中文。[字体说明](https://github.com/office-kit/pptx/blob/18b7e75cfa7fd1c6e9891ce1285a76c7889b644b/packages/preview/README.md#L67-L137)。
4. **自动检查不覆盖全部排版。** CLI `check` 包含类型检查/文字框测量；表格和图表文字尚未测量。缺失所需字体时宽度只是估计，较小溢出可能仅告警。编译本身也不等于 TypeScript 检查。[dev 检查说明](https://github.com/office-kit/pptx/blob/18b7e75cfa7fd1c6e9891ce1285a76c7889b644b/packages/dev/README.md#L124-L151)。
5. **浏览器播放与导出分开。** core 能写出的动画/转场不代表预览全部模拟；dev 文档只明确一部分转场可动画播放，其他直接切换。[播放说明](https://github.com/office-kit/pptx/blob/18b7e75cfa7fd1c6e9891ce1285a76c7889b644b/packages/dev/README.md#L80-L91)。
6. **手工画布编辑不直接改 TSX。** 最新 dev 文档说明画布更改保存在 `.office-kit/<entry>.editor.zip`，源文件变更尝试合并，冲突需要选择；存在未解决冲突时 CLI 拒绝导出。因此应交付 TSX 项目及该编辑状态，不能只复制 TSX 就承诺包含所有手工改动。[编辑持久化](https://github.com/office-kit/pptx/blob/18b7e75cfa7fd1c6e9891ce1285a76c7889b644b/packages/dev/README.md#L93-L115)。

## 与 Kimi 的公平测试边界

两条路径应使用相同中文文字、图表数据、图像和页面尺寸，各自按原生结构实现；不能将 Kimi 图片打包路径拿来代表已验证的本地原生 WASM。应同时查看最终 PPTX、原生对象/图表数据结构，以及由同一个 Office 渲染器得到的页面。导出速度只记录文件构建本身，不混入 npm 安装、浏览器首次启动、字体下载或人工设计时间。

仅此轮匹配样例可支持“该样例导出/编辑结构/排版如何”，不能推出任意模板、全部动画、图表或字体全面兼容。Office Kit 使用 TSX 并不自动理解已有 PPTD；若目的是直接替换 Kimi 的 PPTD exporter，仍要写 PPTD→DSL/core 的语义映射层。它的价值也可独立评估为一种新制作流程。

## 本轮端到端结果

### 方法与产物

分别以 Kimi PPTD→本地原生 WASM、Office Kit 官方 TSX→CLI 构建三页 16:9（960×540 pt）演示稿：封面、三栏卡片、原生表格与双系列柱状图。文字、字号、Noto Sans CJK SC、照片、坐标和模拟数据匹配。Office Kit 使用 npm 发布包及 lockfile，`npm run check` 为 0 errors / 0 warnings，`npm run build` 成功；不是用别的库代写其成品。两套 PPTX 均由同一 LibreOffice 25.8.5.2 和字体配置转 PDF，再用 PyMuPDF 渲染为 PNG。

产物根目录：`output/pptx-comparison-20261107/`（本机生成物，未提交）。

- `comparison.html`：逐页并排比较，可下载两份 PPTX/PDF。
- `comparison-overview.jpg`：左 Kimi、右 Office Kit 的三页总览。
- `kimi.pptx` / `officekit/deck.pptx`：最终原始输出。
- `kimi/deck.pptd`、`kimi/pages/*.page` / `officekit/deck.tsx`、`officekit/theme.ts`、`officekit/slides/*.tsx`：可修改源文件。
- `comparison-results.json`：实际对象、图表、表格、文件体积检查结果。
- `openxml-validation-final.log`、`openxml-validation-load-save.log`：微软 OpenXML SDK 3.1.0、Microsoft365 schema 的验证结果。
- `roundtrip-results.json`、`hot-reload-result.json`：真实修改/重新读取、局部热重载记录。

这是同一执行者控制布局的导出/工作流比较，不能解释为两个 AI 各自自主设计的审美能力比赛。仅做三页样例，未覆盖 SmartArt、动画播放、复杂模板、批注和大文件。

### 成品与原生对象

| 检查 | Kimi 本地 WASM | Office Kit TSX |
|---|---|---|
| 原始输出 | 120,923 字节 | 132,105 字节 |
| 页数 / 各页对象数 | 3 / 7、18、6 | 3 / 7、18、6 |
| 非空可编辑文本框 | 20 | 20 |
| 原生表格 / 图表 | 1 / 1 | 1 / 1 |
| 类别、两组数据、系列名称 XML | 正确 | 正确 |
| 图表内嵌 Excel 工作簿 | 无 | 1 个 XLSX |
| 内嵌字体 | 无 | 无 |
| 原始 PPTX 微软 schema 校验 | 通过 | 通过 |
| 同一 LibreOffice 渲染 | 三页成功，无明显遮挡/越界 | 三页成功，无明显遮挡/越界 |

实际文字框、表格、图表及独立照片均存在；没有把页面整体变成截图。两套输出在统一图表轴字号/网格后接近，中文换行、封面行距、表格细线和柱宽仍有区别。Office Kit 封面标题行距较紧，部分中文词组的断行较好，卡片正文则两边各有断词，不能据此宣布通用中文排版赢家。

初稿图表的轴字大小、图例、网格线设置不一致，已明确设置双方 12pt 标签、0–300 数值范围及浅色主网格后重建最终稿；初稿另存 `first-pass/`。独立复核者在不知道 A/B 工具身份的情况下检查了初稿六张图，未发现明显越界，提出图表标签/网格差异；最终样式据此统一并由主线程逐页复核。独立复核对初稿样式的描述不能当作最终稿仍有这些差异。

### 修改、预览与兼容性

实际用 Office Kit core 加载两份原始成品，修改封面标题，并把表格和收入图表 Q4 从 240 改为 260，保存再读。两份文件都能重读到修改后的标题和数据；但进一步 schema 验证揭示 **Kimi→Office Kit 图表重建后的文件有无效关系引用**，因此不能把“重读成功”写成“修改完全通过”。Office Kit 自己的成品修改保存后通过验证。

Kimi 的图表没有内嵌 XLSX。其系列名称的合法直接字符串写法又被 Office Kit 读为空名；显式提供正确系列名给 `setChartData` 会触发图表重建。`setChartSpec` 重建 XML 时调用的 `buildChartSpaceDoc` 无条件写 `externalData r:id=rId1`，但调用方仅在原工作簿存在时更新它，没有给无工作簿输入补建 XLSX/关系。这次最终得到 `Sem_InvalidRelationshipId`（`ppt/charts/chart3_1.xml` 的 `externalData`）。修改后的 Kimi 文件仍没有 XLSX，不是已经补齐了工作簿。[触发重建路径](https://github.com/office-kit/pptx/blob/18b7e75cfa7fd1c6e9891ce1285a76c7889b644b/src/api/fn/charts.ts#L634-L675)、[仅更新已有工作簿](https://github.com/office-kit/pptx/blob/18b7e75cfa7fd1c6e9891ce1285a76c7889b644b/src/api/fn/charts.ts#L438-L475)、[无条件 externalData](https://github.com/office-kit/pptx/blob/18b7e75cfa7fd1c6e9891ce1285a76c7889b644b/src/internal/chartml/chart-builder.ts#L1980-L1999)。

对照：Kimi 文件在 Office Kit 中仅加载、保存，不修改图表，微软校验通过。因此问题不能泛化为“加载 Kimi 文件就损坏”。未修库、未手工修复修改后文件，也未将失败产物作为有效最终交付。

Office Kit dev editor 实际可启动并显示三页；修改第三页数据后 revision 1→2，只有第三页 SVG 改变，前两页 SVG 字节相同。中文浏览器最初显示方块，给启动浏览器的字体环境添加 Noto CJK 后可读。预览标题行距与 LibreOffice 仍不同，不能拿内置 SVG 预览替代实际 Office 渲染验收。没有验证画布拖动持久化、内置 Agent 终端、PowerPoint/WPS 的“编辑数据”界面。

本机正常初始化因 `node-pty@1.1.0` 安装脚本失败；使用 `npm_config_ignore_scripts=true` 后项目初始化、check/build、预览及热重载可运行。该绕法没有验证依赖 node-pty 的内置终端可用，不能当作完整 dev 环境安装通过。

一次本地构建记录：Kimi Node/WASM 导出约 0.468 秒（断网执行），Office Kit `buildDeck` 约 0.550 秒。但后者包含 SVG 预览构建，计时边界不同、样本量为 1，不作性能排名。

### 对当前迁移的判断

基于本轮证据，**从零制作新 PPT，可优先试用 Office Kit 独立 Skill**：公开 TS/OOXML 路线、原生图表含工作簿，TSX、check 和热重载有实际价值；这不是视觉明显优于 Kimi 的结论。应固定版本，并保留中文字体配置和 Office 渲染检查。

**已有 Kimi PPTD 的直接导出仍更适合继续验证本地 WASM**：无需额外建立 PPTD→Office Kit 映射。Office Kit 不是 PPTD 的直接替代 exporter；而且当前版本的跨库图表读取/重建存在上述实证问题。双方并不需要强行合为一条复杂流程。


## 独立视觉复核：已生成的三页匹配样例

已查看 `output/pptx-comparison-20261107/comparison-overview.jpg` 六图总览，以及 `render/kimi/page-3.png`、`render/officekit/page-3.png` 原尺寸图片。主线程提供的渲染条件是同一 LibreOffice 25.8、同一 Noto Sans SC 字体配置；本节没有重新渲染或修改源文件。

- 两条路径的三页均能阅读，未看到文字被裁断、图片缺失、表格越界或元素互相覆盖。第一张封面使用同一图片区域，主要可见差异是标题行距和副标题换行；Office Kit 标题两行更紧凑，Kimi 行间留白更大。
- 第二页三列卡片的框、编号、标题和底线均对齐。中文正文换行有差异，例如 Office Kit 第一张卡片的第一行比 Kimi 短；两者都没有文字溢出。该观测说明不能保证相同名义字体/字号就逐像素相同，也不足以推断任一路线的普遍中文排版质量。
- 第三页的 Q1–Q4 表格、收入/成本值及两组柱形关系一致，**两张图均实际显示“收入”“成本”图例名称**。该次复核看到的是初稿：Kimi 有横向网格线、柱更宽，Office Kit 柱更窄、图例字更大且颜色更浅；表头列分隔线也不同。最终稿已统一网格与字号。这些是本样例的输出差异，不能仅凭图片区分来自设置、默认值或导出实现。
- 表格/图表页没有显著的裁切或重叠。图表不是整页图片的证据需要结合 OOXML 对象检查，视觉复核本身不证明数据可编辑、动画有效或 PowerPoint/WPS 打开保存通过。

## Kimi 图表系列名称的互操作缺陷定位

对实际 `kimi.pptx` 的只读 ZIP/XML 检查确认，`ppt/charts/chart3_1.xml` 两个系列各有直接字符串形式的 `c:tx/c:v`，内容分别为“收入”“成本”；LibreOffice 截图也正确显示。因此“某个库读出空字符串”不能归因于 Kimi 没写系列名。

Office Kit 0.28.0 的 `readSeriesName`（chart-reader.ts 第 235–239 行）仅调用 `readStringRef(tx)`。该函数最终只支持 `strRef/strCache`、`strLit`、`multiLvlStrRef` 的数组字符串通道，**没有读取直接子节点 `c:v`**；所以遇到这次 Kimi 写法时返回空数组路径，最终成为空名称。`getShapeChartSeriesNames` 则直接返回 `getShapeChartSpec(...).series[].name`，因此两个公开 API 会一起出现空名称。[底层读取路径](https://github.com/office-kit/pptx/blob/18b7e75cfa7fd1c6e9891ce1285a76c7889b644b/src/internal/chartml/chart-reader.ts#L180-L239)、[公开 API](https://github.com/office-kit/pptx/blob/18b7e75cfa7fd1c6e9891ce1285a76c7889b644b/src/api/fn/charts.ts#L829-L873)。

Microsoft 的 SeriesText/CT_SerTx 文档明确允许系列名的 `strRef` 或 `v` 两种子元素，所以该直接字符串并非因没有 strCache 就无效。这是 Office Kit 这条 reader 的兼容性缺口；不是本次视觉图例丢失，也不是本文已经修复的缺陷。[Microsoft SeriesText 定义](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.charts.seriestext?view=openxml-3.0.1)。

主线程另已执行“显式提供系列名后 setChartData、保存、重载”的对照：数据可重读，但图表重建没有补齐原输入缺失的工作簿，最终 schema 校验失败，详见上文。不能将重读成功推断为工作簿正确；也不能据此断言仅加载和原样保存会删除原始名称。未知 parts 保留、读取 API 和主动重建图表应分别评价。未修改库、提交 issue 或发送外部消息。

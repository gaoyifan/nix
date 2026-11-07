# Kimi 可编辑 PPTX 导出的修复路径

核查日期：2026-11-07。范围是已锁定的 `gaoyifan/open-kimi-ppt-skill@faf153b7fa6a027c324a28e6400efa98948c651f`、原作者公开讨论和现成的本地 PPTD 转换器；没有编辑现有 Skill 工作区中的未提交修改，也没有调用私人 Kimi 会话。原生协议的现场诊断见[失败核查](kimi-pptx-export-failure.md)。本记录比较的是恢复逐元素可编辑导出，不将整页图片打包当作修复。

## 上游历史：确实曾发布本地化修复，但原仓库已清空

我们的 GitHub fork 元数据指向 `acnlie/open-kimi-ppt-skill`，其 main 是旧版 `c32890f`（1.2.0），并关闭了 issues；包内 homepage/bugs 则仍指向原作者 `Binaryify/open-kimi-ppt-skill`。不能只检查 fork 的直接 parent 就认定上游没有更新。[锁定包元数据](https://github.com/gaoyifan/open-kimi-ppt-skill/blob/faf153b7fa6a027c324a28e6400efa98948c651f/package.json#L1-L14)。

原作者仓库的 [Issue #9](https://github.com/Binaryify/open-kimi-ppt-skill/issues/9) 报告相同的 PPTD 能预览、PPTX 无法导出，错误为签名接口 401；有人反馈官方桌面版可导出。作者在 2026-08-07 回复重新安装新版。[Issue #8](https://github.com/Binaryify/open-kimi-ppt-skill/issues/8#issuecomment-5213111993) 随后明确称新版本已完全本地化；[Issue #7 的作者回复](https://github.com/Binaryify/open-kimi-ppt-skill/issues/7#issuecomment-5212382546) 同样确认。这些是作者发布说明，不等同当前机器或所有 PPTD 功能已验证。

但原作者最新 main 是 `bc0a246c1dc37ab9644822e9657c6e23dca2128f`（2026-08-07），只剩 README，说明因为版权原因已清空仓库。[当前 README](https://github.com/Binaryify/open-kimi-ppt-skill/blob/bc0a246c1dc37ab9644822e9657c6e23dca2128f/README.md)、[清空提交](https://github.com/Binaryify/open-kimi-ppt-skill/commit/bc0a246c1dc37ab9644822e9657c6e23dca2128f)。因此不能把社区保留的旧 WASM/镜像说成仍受原作者维护的官方升级。旧文件是否可使用、可再分发，需要分别核对其来源和第三方许可；仓库自身的 MIT 声明不能单独证明其中厂商二进制的授权范围。

## 可行选项比较

| 路径 | 已有证据 | 未解决的问题 | 对本次需求的判断 |
|---|---|---|---|
| 修复当前网页宿主的导出协议 | 当前失败发生在网页选择导出方案前；仅补错误透传或延长等待无效。主线程另核对 SDK 的 external handleExport 路径。 | 宿主回调仍需真正生成 PPTX 的 backend；填入模式标志不会凭空提供 exporter。服务端方案还需明确合法接入方式和授权。 | 若可使用现有 Kimi 正式 backend，可保留最多格式语义；本轮尚未证明无人值守可用。 |
| 固定历史本地 WASM exporter | 社区镜像保留了历史 exporter；主线程独立验证旧 WASM 能在隔离网络下生成 PPTX。 | 厂商二进制来源/许可、未来维护及完整格式验收不能从“能出文件”推出。 | 技术上最接近复用现有 PPTD 语义；原仓库因版权清空是必须呈现的具体约束。 |
| 采用独立 PPTD→原生 OOXML engine | 找到真实实现，直接调用 PptxGenJS，可独立加载，无需 Kimi WASM；详见下节。 | 部分图表不支持，custom path 变成 SVG 对象，特殊样式会归一化；不是完整保真。 | 可作为有明确覆盖边界的长期 backend，不能直接宣传完全替代。 |
| 自行实现完整 PPTD 编译器 | PPTD 是明确的 YAML/元素语义，可映射到现有 OOXML 库。 | 需实现富文本级联、177 个形状/参数、自定义 path、13 种图表及动画等语义。 | 能控制依赖，但完整实现属于一个独立格式转换项目，不是几行脚本修复。 |

## 更值得验证的现成独立实现

### SuperstructureJH/dsh-workbuddy-ppt

核对版本 `08105627aac203c2884b674eed19349952a914fb`，MIT。发布包包含 `dsh-pptd` CLI 和 `./pptd` 模块；`lib/pptd.js` 自称 clean-room 实现，实际导入 Node 内置模块、`js-yaml`、`pptxgenjs`，没有调用 Kimi WASM。可直接使用其 `loadPptdProject`、`checkPptdProject`、`renderPptdProject`，不需要接入整个 DSH UI。它根据 manifest.size 定义 PowerPoint 页面，并用 addText/addShape/addTable/addChart 创建真实对象。[包与 CLI](https://github.com/SuperstructureJH/dsh-workbuddy-ppt/blob/08105627aac203c2884b674eed19349952a914fb/package.json)、[实现](https://github.com/SuperstructureJH/dsh-workbuddy-ppt/blob/08105627aac203c2884b674eed19349952a914fb/lib/pptd.js#L1-L45)、[原生生成与模块导出](https://github.com/SuperstructureJH/dsh-workbuddy-ppt/blob/08105627aac203c2884b674eed19349952a914fb/lib/pptd.js#L1710-L1750)、[许可证](https://github.com/SuperstructureJH/dsh-workbuddy-ppt/blob/08105627aac203c2884b674eed19349952a914fb/LICENSE)。

已核对的边界：

- 原生图表覆盖 bar、line、area、scatter、bubble、pie、radar；candlestick、waterfall、heatmap、treemap、sunburst、sankey 明确报 unsupported。
- `shapeName: custom` 转为 SVG 图片对象，不是 PowerPoint 内可逐点编辑的形状；图标转为 Arial 文本名称/符号，不保证原图标外观。
- 形状 adjustments、部分渐变/图片填充、阴影、图片裁剪等被标记为 normalized 或 fallback；它给出兼容性统计，不能把所有 normalized 视为保真。
- 发布说明把 PowerPoint/WPS 打开、修改、保存和重新打开列为单独验收，Linux 当前 release 未运行。本轮只进行了代码核查，没有替它完成这些验收。

来源：[兼容性分级](https://github.com/SuperstructureJH/dsh-workbuddy-ppt/blob/08105627aac203c2884b674eed19349952a914fb/lib/pptd.js#L157-L208)、[custom shape 实现](https://github.com/SuperstructureJH/dsh-workbuddy-ppt/blob/08105627aac203c2884b674eed19349952a914fb/lib/pptd.js#L1148-L1176)、[兼容性矩阵](https://github.com/SuperstructureJH/dsh-workbuddy-ppt/blob/08105627aac203c2884b674eed19349952a914fb/docs/COMPATIBILITY.md)。

### 两个容易被宣传误导的候选

`z953218350/dsh-np-ppt@2594d90999ec13de1e3d45b98a77ea940bf78c97` 确有 MIT Python 原生 exporter，文字、形状、表格是对象。但代码固定 16:9/微软雅黑，仅特殊处理四类形状，其他形状默认为矩形；图表不读取完整 series，而直接取每行第 1/3 列，固定柱状图和业务系列名称。图片无完整 fit/crop/cropShape 映射。它不能作为任意现有 PPTD 的保真导出修复。[编译器](https://github.com/z953218350/dsh-np-ppt/blob/2594d90999ec13de1e3d45b98a77ea940bf78c97/compiler/export_pptx.py#L520-L867)。

`kdnsna/ultimate-ppt-master-skill@d095abf675d1074b9a04c15fe8b8c665a164c21c` 有 PPTD→SVG→DrawingML 的真原生对象路径，表格/图表成为可编辑形状，失去原生表格/图表数据语义。其 chart renderer 仅显式实现 pie/line，其他按 bar 处理；icon 直接略过。因此“本地可编辑”也不等于完整 PPTD v2 兼容。[本地 exporter](https://github.com/kdnsna/ultimate-ppt-master-skill/blob/d095abf675d1074b9a04c15fe8b8c665a164c21c/upm/export/local.py#L1-L7)、[图表映射](https://github.com/kdnsna/ultimate-ppt-master-skill/blob/d095abf675d1074b9a04c15fe8b8c665a164c21c/upm/render/charts.py#L36-L46)、[元素处理](https://github.com/kdnsna/ultimate-ppt-master-skill/blob/d095abf675d1074b9a04c15fe8b8c665a164c21c/upm/render/svg.py#L495-L531)。

## 为什么单纯换一个 PPTX 库不够

锁定 PPTD 定义了 text/shape/line/image/icon/table/chart 七类元素，坐标 1px=1pt，多级文本样式、177 个预设形状与自定义 SVG path，图片 fit/crop/cropShape，13 类图表及元素动画。这些描述可以映射 OOXML，但后端库不会自动理解 PPTD 的主题继承和数据编码。[元素总表](https://github.com/gaoyifan/open-kimi-ppt-skill/blob/faf153b7fa6a027c324a28e6400efa98948c651f/skills/open-kimi-ppt/reference/pptd.md#L505-L520)、[形状语义](https://github.com/gaoyifan/open-kimi-ppt-skill/blob/faf153b7fa6a027c324a28e6400efa98948c651f/skills/open-kimi-ppt/reference/pptd.md#L713-L760)、[图表语义](https://github.com/gaoyifan/open-kimi-ppt-skill/blob/faf153b7fa6a027c324a28e6400efa98948c651f/skills/open-kimi-ppt/reference/pptd.md#L1025-L1058)。

例如 python-pptx 提供原生文字、AutoShapes、表格、常用图表和数据编辑，PptxGenJS 提供图表/组合图，但都仍需 PPTD 解析和逐属性转换。不能仅替换 import 或调用 save 就获得完整兼容。[python-pptx 图表](https://python-pptx.readthedocs.io/en/latest/user/charts.html)、[AutoShapes](https://python-pptx.readthedocs.io/en/latest/user/autoshapes.html)、[PptxGenJS 图表](https://gitbrent.github.io/PptxGenJS/docs/api-charts/)。

OfficeCLI 还存在同名不同项目：这里核对的开源 `iOfficeAI/OfficeCLI@c56512c8c7b76fe284f09940e4cd492470099d3e` 可创建原生 PPTX 对象，但源码目录未找到 PPTD 导入器。采用它仍需要 PPTD 映射层，不能当成已存在的 Kimi 导出替换开关；不要与另一个 `officecli/officecli` 项目混为一谈。[开源项目](https://github.com/iOfficeAI/OfficeCLI/blob/c56512c8c7b76fe284f09940e4cd492470099d3e/README.md)、[原生对象 CLI](https://github.com/iOfficeAI/OfficeCLI/wiki/command-add-ppt)。

## 本地 WASM 的实际验证

用户希望优先考虑本地 WASM。主线程核对并运行了社区保留的 `E1nzbern/open-kimi-ppt-skill@07eeaadcb04c32c9adb107eb5c8608e6be4e1008` 的 686 行 Node 入口和 788,074 字节 WASM。入口读取 PPTD/图片、组装参数、调用 WASM 并写出文件；本轮未引入完整网页镜像，也没有修改原有 Skill 工作区。[Node 入口](https://github.com/E1nzbern/open-kimi-ppt-skill/blob/07eeaadcb04c32c9adb107eb5c8608e6be4e1008/skills/open-kimi-ppt/scripts/local-export/export-pptd.mjs)、[后端说明](https://github.com/E1nzbern/open-kimi-ppt-skill/blob/07eeaadcb04c32c9adb107eb5c8608e6be4e1008/skills/open-kimi-ppt/scripts/local-export/README.md)。

固定 WASM 的 SHA-256 为 `f62500af4546ab379b458d405c2c6b18d659a1a18a4299baba03ccb4dc08e746`。该社区版本明确使用修改后的 WASM 跳过旧签名校验，不能将其描述为厂商正式提供、授权或持续维护的开放 API。原仓库版权清空事实同样适用于这一选项的来源评估。

所有执行都在 `unshare -Urn` 的隔离网络中完成，环境未提供 Cookie 或其他服务凭据，输入只含公开样例或合成测试数据：

| 输入 | 结果 |
|---|---|
| minimal 单页 | 约 0.28 秒生成 7,334 字节 PPTX；含原生中文文本框，修改文字、保存、重新读取成功。 |
| YU7 八页 | 约 1.44 秒生成 7,620,692 字节 PPTX；每页 9–27 个对象，共 113 个非空可编辑文字对象；ZIP、8 个根级转场和重新读取检查通过。 |
| 合成表格/双系列柱状图 | 保留原生 Table 和 Chart，类别及两组数值正确。后续 XML/LibreOffice 复核确认系列名“收入”“成本”存在且可显示；此前 python-pptx 读出空名属于读取兼容问题，不能判定为导出丢失。 |
| 八页元素动画样例 | 导出成功，各页存在 OOXML timing 节点；未进行 PowerPoint/WPS 动画播放验收。 |

Node 入口的 `fonts`、`customFonts` 和 `chartImages` 参数当前为空，`--embed-fonts` 仅是保留参数；本轮输出没有嵌入字体。因此“核心可编辑导出可运行”已经实证，但“全部格式保真、字体嵌入和动画播放均已解决”尚未成立。

复核产物在 `output/kimi-export-verification-20261107/`：`research-native-{minimal,yu7,features,animation}.pptx`、`research-native-minimal-edited.pptx`、`research-native-validation.json`、`research-features-validation.json` 及相应 WASM 运行日志。当前 Skill、Nix pin 和 Rakazo 部署均未改动。

## 建议的修复实施边界

按用户选择的本地 WASM 方向，最小可维护方案是固定独立 Node 导出入口与 WASM，把已有 Python CLI 接到同一个本地 exporter，并保留 PPTD 作为输入。无需把整个旧网页应用一并引入。需要处理字体、下游图表读取兼容性及导出后内容检查，并核实资源/主题覆盖范围，并用真实 Office 打开、编辑、保存和渲染做最终验收；不能将测试通过的文件生成直接等同全部兼容。

如果还要修复浏览器编辑器中的“导出”按钮，当前 SDK 的 `sdkExportMode=external` 和 `handleExport` 可以作为接入宿主 exporter 的协议入口，但标志本身不会生成 PPTX；下载地址、跨源行为及共享同一导出后端仍需实测。这一层本轮未实施。

独立开源路线可继续评估 `dsh-workbuddy-ppt` 的 standalone PPTD 模块，覆盖相同样例并比较 OOXML 对象、文本/数据、尺寸和渲染；它是另一个具有明确覆盖边界的选项，不应静默替代用户选定的 WASM 引擎。完整保真仍需差异清单，而厂商二进制的来源和再分发依据需要在纳入受维护版本前明确。

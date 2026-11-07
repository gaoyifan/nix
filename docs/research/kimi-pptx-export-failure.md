# Kimi PPTX 导出失败核查

核查日期：2026-11-07。直接在 el2 运行导出脚本，没有使用 Rakazo、Hermes、Kimi 登录账号或私有演示文稿。测试源为本仓库锁定的 `gaoyifan/open-kimi-ppt-skill@faf153b7fa6a027c324a28e6400efa98948c651f`，另对已存在的未提交错误透传修改做对照；未修改这些源文件。

## 结论

失败的是 `export_pptx.py` 调用 Kimi 网页 PPTX 导出的路径。当前网页在该本地 SDK 会话中立即报 `no available pptx export plan`，没有发起实际 PPTX 导出请求，也没有产生下载文件。原脚本没有接收网页错误，最终只报告 90 秒下载超时。

`export_pptx_local.py` 是另一条路径：从 Kimi 导出页面图片，再用 python-pptx 在本机打包成 PPTX。单页及八页样例均通过。其幻灯片是整页图片，不能把成功导出理解为获得了逐元素可编辑的原生 PPTX。[本地打包实现](https://github.com/gaoyifan/open-kimi-ppt-skill/blob/faf153b7fa6a027c324a28e6400efa98948c651f/skills/open-kimi-ppt/scripts/export_pptx_local.py#L37-L60)

## 实测

环境：Node.js 24.21.0、agent-browser 0.33.2、Nix Chromium 155.0.8059.84；Python 依赖用独立 uv 环境提供。运行前补齐依赖并指定可执行浏览器，避免把本机缺库误当成导出协议错误。

| 路径 | 输入 | 结果 |
|---|---|---|
| 锁定版 `export_pptx.py`，默认字体嵌入 | 仓库 minimal 单页 fixture | 下载超时，未出现文件；独立干净重跑与结束时抓取诊断的重跑均失败。 |
| 已有错误透传修改的 `export_pptx.py`，字体嵌入开/关 | 同一单页 | 两次均约 5 秒返回“导出 PPTX 失败”；关闭字体嵌入不能恢复。 |
| 锁定版 `export_pptx_local.py` | 同一单页 | 成功：1 页、43,754 字节、1 个 fade transition。 |
| 锁定版 `export_pptx_local.py` | 仓库 `example/yu7-ppt` 八页、本地图像 | 成功：8 页、1,866,719 字节、8 个 fade transition。 |

两个成功文件均通过 ZIP 完整性检查、python-pptx 重新读取及每页图片结构检查。检查了单页图片和八页总览；没有进行 PowerPoint/WPS 实机兼容性测试。一次原生导出尝试被观察命令影响后主动中止，已排除出结论。

## 根因证据

浏览器结束前抓取的请求记录包含 Kimi 自身的 `msh_nppt_export_end` 事件。提取并去除临时会话标识后的字段为：

```json
{
  "file_type": "pptx",
  "is_success": false,
  "error_reason": "no available pptx export plan",
  "export_duration": 6,
  "user_activation": true
}
```

请求记录中没有 `/apiv2/slides:export-pptx`、`/apiv2-files/file/upload` 或 `SlidesService/ExportPPTXByFiles` 请求。由此可确认这次失败发生在导出方案选择阶段，而非生成后文件未能落到脚本寻找的目录。

本次获取的 Kimi [ExportDialog-x1qyYmJW.js](https://statics.kimi.ai/neo-design/assets/ExportDialog-x1qyYmJW.js) 调用导出函数，其依赖的 [useSaveModel-HTC9wl9Z.js](https://statics.kimi.ai/neo-design/assets/useSaveModel-HTC9wl9Z.js) 中，PPTX 导出选择的是宿主提供的 `handleExport` 或服务端导出方案。无可用方案时，代码在调用服务前直接抛出上述错误。图片导出则在页面中渲染各页并组成 ZIP，因此本次仍可成功。

脚本使用 `sdkMode=ppt-editor` 和本地生成的 `local-export-…` 标识加载 PPTD；宿主没有实现 `handleExport`。该会话未获得当前网页要求的导出方案。这里只确认当前协议与脚本不兼容，不推断 Kimi 在何时改动、登录/订阅后是否恢复，或伪造参数能否解决。

另一个确定的脚本缺陷是错误被隐藏：[export_host.html](https://github.com/gaoyifan/open-kimi-ppt-skill/blob/faf153b7fa6a027c324a28e6400efa98948c651f/skills/open-kimi-ppt/scripts/export_host.html#L119-L123) 的 `showMessage()` 是空实现；[export_pptx.py](https://github.com/gaoyifan/open-kimi-ppt-skill/blob/faf153b7fa6a027c324a28e6400efa98948c651f/skills/open-kimi-ppt/scripts/export_pptx.py#L780-L790) 点击后仅等待下载。现有未提交修改捕获了错误并提前结束，但并未恢复原生 PPTX 导出。

## 可复核产物

本次测试产物位于忽略目录 `output/kimi-export-verification-20261107/`：

- `root-cause-evidence.json`：筛选后的失败事件及实际导出请求计数。
- `pinned-native-export.log`、`native-diagnostic.log`：两次有效原生路径失败记录。
- `current-fonts-on.log`、`current-fonts-off.log`：字体开关对照。
- `pinned-export.log`、`pinned-yu7-export.log`：两次本地图片打包成功记录。
- `pinned-minimal.pptx`、`pinned-yu7-8slides.pptx`：可下载文件。
- `kimi-save-model.js`、`kimi-export-dialog.js`、`kimi-export-plan-snippet.txt`：本次获取的网页实现快照。

本轮只定位和验证，未更改 Skill 的导出行为或接入 Rakazo。延长超时不会补上缺失的导出方案；恢复逐元素可编辑导出，需要另行实现有效的导出后端或本地 PPTD→OOXML 转换。

# Rakazo Office 附件限制的上游依据

调查日期：2026-11-06。部署版本：`46e95fa8314324cbcf6e4e33c7ed06dbbc68b923`。

目前证据更支持“附件格式支持尚未补齐”，而不是“上游明确决定禁止 Word/PPT”。没有找到维护者以安全、无法预览或许可证为理由禁止这些格式的说明。这里的原因判断是推断，不能当成维护者已经解释过的设计决定。

## 明确的上游记录

- [Issue #1187](https://github.com/elie222/rakazo/issues/1187) 报告 Bot 无法读取 PDF/Office 文件，提出在电脑镜像中加入文档转换器，或由 API 提取文档文本。报告将正常上传 DOCX/XLSX 作为预期使用场景。
- 维护者 elie222 创建并合并的 [PR #1188](https://github.com/elie222/rakazo/pull/1188) 明确以“总结用户上传的 PDF、DOCX、XLSX”为目标，加入 `pdftotext`、`pandoc` 和 `openpyxl`，并在 Bot 指令里说明工具已安装。该 PR 改动电脑镜像、工具说明及相关测试，没有扩展附件白名单。
- 维护者于 2026-10-09 在[关闭评论](https://github.com/elie222/rakazo/issues/1187#issuecomment-6082653103)中称，加入这些工具后，Bot 现在可以读取 PDF 和 Office 文件。这是支持 Office 处理意图的证据，不能据此认定所有 Office 格式已经能正常上传。
- [PR #1188 的自动代码审查](https://github.com/elie222/rakazo/pull/1188#discussion_r4186942185)恰好指出了缺失的一层：DOCX/XLSX 不在 MIME 白名单和扩展名映射中，API 会在文件送进电脑之前拒绝，所以镜像里的新转换工具无法用于正常上传的 Word/Excel 文件。评论在合并后约四分钟发布；该审查线程没有后续回复。它是自动 reviewer 的发现，**不是维护者对限制理由的声明**。
- [Issue #1282](https://github.com/elie222/rakazo/issues/1282) 与 [PR #1289](https://github.com/elie222/rakazo/pull/1289)表明 ZIP 也曾被同一套白名单阻止。后来按用户需求增加 `application/zip` 和双向扩展名映射，沿用原来的大小限制和校验；服务器只把文件送入 Bot 工作目录，不负责解压。
- 2026-10-29 合并的 [PR #2748](https://github.com/elie222/rakazo/pull/2748) 又单独补上 XLS/XLSX。PR 明确说明，此前选择 Excel 文件会在上传前被跳过；改动覆盖共享 MIME 白名单、扩展名推断、网页选择器及端到端测试。这解释了当前 Excel 已经可传，而 DOCX/PPTX 仍未加入名单的历史差异。

## 能解释什么，不能解释什么

电脑里“能处理某种文件”、聊天里“允许传这种附件”、客户端“能预览这种附件”是三个不同层面。#1188 补了第一层，自动审查明确发现第二层仍缺失，后来 #2748 才补了 Excel 的入口。这提供了一个具体的历史衔接遗漏，但没有给出 Word/PPT 特有的禁用理由。

ZIP 被允许后可由 Bot 解压处理原始文档，因此仅凭白名单不能得出“上游为了阻止 Office 文档执行风险而特意封禁”的结论。支持或缺少预览也不能单独解释附件是否可传；上游本身允许无专门预览的文件类型。

本次按 `docx`、`pptx`、`PowerPoint`、`wordprocessingml`、`Office`、`unsupported attachment` 检索上游 issue/PR，除上述 Office 提取问题外，没有找到解释为何单独排除 DOC/DOCX/PPT/PPTX 的维护者讨论。仓库当前未启用 GitHub Discussions。

当前部署的实际名单、预览分派和校验可见[附件契约](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/contracts/src/attachments.ts)及[文件交付入口](https://github.com/elie222/rakazo/blob/46e95fa8314324cbcf6e4e33c7ed06dbbc68b923/packages/adapters/src/run-tools-files.ts)。允许的 XLSX/ZIP 可走 `none` 预览类型，所以没有专用预览组件本身不是传输的硬性障碍。

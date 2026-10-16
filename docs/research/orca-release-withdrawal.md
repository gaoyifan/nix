# Orca 1.4.225 / 1.4.226 撤回调查

日期：2026-10-15。结论：**SSH 回归和项目开发者建议降级已确认；为何删除 Release / tag，未找到官方明确说明。**

## 已确认

- 官网更新日志仍列 [1.4.225（10 月 14 日）](https://www.onorca.dev/changelog/1-4-225)和 [1.4.226（10 月 15 日）](https://www.onorca.dev/changelog/1-4-226)。前者将新 SSH 连接默认切换到受管服务器。
- [本仓库自动更新](https://github.com/gaoyifan/nix/actions/runs/38700455735)在 10 月 15 日 07:45 UTC 成功更新到 1.4.226；[15:04 UTC 的任务](https://github.com/gaoyifan/nix/actions/runs/38757091373)尝试回退到 1.4.224 后失败。调查时 GitHub 最新稳定版为 [1.4.224](https://github.com/stablyai/orca/releases/latest)，查询两版 Release 的官方 API 均返回 404。
- 用户报告 .224 升到 .226 后，原有 SSH / WSL 主机无法连接；贡献者 nwparker 表示正在调查（[issue #29083](https://github.com/stablyai/orca/issues/29083#issuecomment-6187847883)）。另有报告称 .226 的无界面服务器账号操作全部失败，降级 .224 后恢复（[issue #28962](https://github.com/stablyai/orca/issues/28962)；尚无开发者诊断）。
- 08:37 UTC，nwparker 明确建议用户降级，并表示正在修复 SSH 问题、争取尽快发布新版（[原文](https://github.com/stablyai/orca/issues/28340#issuecomment-6188002838)）。

## 判断与边界

**较强候选是受管 SSH 服务器迁移带来的回归，因此暂停分发新版。** 这是结合症状与开发者回复的推断；回复没有说删除两版的具体原因，公开 Issues、PR、Discussions 和官网未找到撤回公告。无法据此认定删除者、删除时间或操作动机。官方 X 页面访问受限，未覆盖非公开 Discord 讨论。

## 后续处理（2026-10-16）

上游已发布 [1.4.227](https://github.com/stablyai/orca/releases/tag/v1.4.227)。该版的 [构建入口](https://github.com/stablyai/orca/blob/v1.4.227/package.json)不再调用 `build:packages`，[CLI 打包脚本](https://github.com/stablyai/orca/blob/v1.4.227/config/scripts/build-orcad.mjs)也不再读取 `resolveBuildSourceCommit()`。保留 1.4.225/226 的补丁会导致新版本构建失败。

本仓库已更新到 1.4.227，删除对应补丁与 Git 元数据处理，并改为调用上游 `build:orcad` 入口。本地完整构建和运行时预检通过；临时忽略 1.4.224 的例外已按清理条件移除。

# iCloud 照片增量导出的性能调查

调查日期：2026-10-05。对象为 `el2` 的 Incus `hackintosh`，macOS
26.6.2（25G83），OSXPhotos 0.77.1，Python 3.13。第 1–7 节记录初始
调查和独立对照实验；第 8 节记录后续三项优化的实现、部署及验收。

## 结论与证据边界

**事实：** 当前 `--update` 会遍历全部资产，复用已有媒体文件，但仍检查文件、
整理完整元数据并更新导出记录；自定义 `write_skipped` JSON sidecar 还会覆盖写入。
完整元数据路径存在重复 SQLite 连接，以及同一资产媒体分析结果读取两次的问题。
[导出循环](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/cli/export.py#L2060)、
[跳过后仍更新导出数据库](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/photoexporter.py#L1490)、
[自定义 sidecar 写入](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/sidecars.py#L446)

**事实：** 正在导出的 worker 持续使用约一个逻辑 CPU。20 秒 Python 函数采样
将约 48.2% 的窗口归因到导出数据库使用的 `_get_photo_json_full` 调用链；
媒体分析及云元数据独立分支合计约 38.5%。自定义 sidecar 调用链约 8.2%，
所以当前窗口主要成本是完整元数据计算，不能仅归因于 sidecar 覆盖写。
原生采样同时看到 SQLite SQL 准备及数据库 schema 初始化工作。
独立对照已确认：同样 100 个真实资产，
云元数据连接复用耗时 0.745 秒→0.055 秒，媒体分析结果复用耗时
0.450 秒→0.188 秒，返回数据完全相同。两条局部改动合计节省约
9.52 毫秒/资产；不能把这两项微基准当作完整导出加速倍数。

**推断：** 反复打开数据库使 schema 初始化及语句准备缓存不能被有效复用，
是两项已验证重复开销的机制。Python 函数采样补上了属性归因，但这些采样
只代表所处窗口，不能替代完整导出前后对照。第三项已确认热点是导出结果合并
反复复制累积列表；独立规模基准已量化这一开销，并发现原地追加会改变旧列表
引用的行为，不能只凭最终结果相同就认定 API 完全等价。

## 1. 运行版本与源码一致性

**事实：** `flake.nix` 与 `flake.lock` 的 `osxphotos-src` 都固定为
`2be2970fc0a38b087a65215a8bdb7058a7d6ffef`。本地只读检查的 checkout HEAD
也是该 revision，`git status --short` 为空；检查上游时只获取 Git objects，
没有切换 checkout。包构建使用该 input 的源码，只有排除测试库的过滤。
[本仓库包定义](../../pkgs/osxphotos.nix)、[本仓库导出配置](../../home-manager/icloud-photos-export.py)

guest 的实际 Python 路径为：

```text
/nix/store/lmsa4sb2nywhl5bc9vkdi529ff5qp92m-osxphotos-0.77.1/bin/python
```

**事实：** guest 对应 `lib/python3.13/site-packages/osxphotos` 与上述 pinned
checkout 的八个相关文件 SHA-256 逐一相同：

| 文件 | 双方相同的 SHA-256 |
| --- | --- |
| `photoinfo.py` | `950360c54a224f63fb038e77dd719e47cc7a43efaac5add7c0a6c593263d24e8` |
| `media_analysis.py` | `08db92351ba4076a42070f2a96689bc2c67f12b66bb99d8db0f1d56593e15e98` |
| `photoexporter.py` | `db1c13c36799f8acf8703a10ed33d3c4f7f48e31a0cdcd253a86d9e27a51f7ac` |
| `export_db.py` | `e8893f6b4b8b5b779a88c65625f1550c12a69535605c0052e2f07c13c72eb19e` |
| `sidecars.py` | `d8f4e212a2d9069e859c2abb79efc29a4b7f4688dec25ab66db0b270f7bafad0` |
| `photosdb/photosdb.py` | `df23eebae6470547a35c22278be216fd7de26f41f3b521cc117ae86787aafc71` |
| `sqlite_utils.py` | `2c8c83aabb91f8d83750935ae9eb7c44a1e3567a476ad9bf8ad35cce6147d203` |
| `exportoptions.py` | `c32f2ad2e60f8b82d20fdaaeb7e2fda3321f2e79c64ef9c86d95b6f50f38c672` |

这是 2026-10-05 现场 `shasum -a 256` 和本地 `sha256sum` 的直接对照。文件中的
macOS 27 typed captions 与 `cached_property` 已包含在该 pin 中，不能把它们
当作本地 checkout 被其他任务改动的迹象。

## 2. 当前运行的采样

**事实：** 当前 worker PID 为 `90805`，启动于 02:18:34；本轮查询约 51,535
个资产。前段观察的处理速度约 19–20 个资产/秒，CPU 约 90–95%，原生
sample 报告 physical footprint 约 2.8G。CPU 100% 表示占满一个逻辑 CPU，
不是整台 4 vCPU VM 的全部计算资源。

02:54 的后段 `top` 显示 worker 内存 5,121M、系统压缩器约 2,417M，说明
内存占用随导出增长；该三秒采样仍为约 90% CPU，新增 swapin/swapout 均为零。
这支持该窗口仍以单线程计算为主，同时提示不能忽略完整 JSON 缓存与结果列表
的生命周期。累计换页总量不能直接用作当前磁盘瓶颈的证据。

02:29:36 开始的原生 `sample`，主线程共有 6,150 个样本。在其中一条主要分支中，
`sqlite3_prepare_v2 → sqlite3RunParser` 为 1,230 个样本，后续可见
`sqlite3ReadSchema → sqlite3Init → sqlite3InitOne → sqlite3InitCallback`。
这一分支约占该线程样本的 20%；它既不是所有 SQLite 分支的总和，也不是某个
Python 函数的精确耗时。采样原文保存在宿主临时调查目录
`/tmp/icloud-photos-rootcause-20261005/backup-cpu-sample.txt`。

**事实：** SQLite 执行 SQL 前先将它编译为 prepared statement；Python 的
`cached_statements` 默认缓存 128 条语句，缓存归属于单个连接。
**推断：** 即使 SQL 字符串相同，每次新建、随后销毁连接仍无法沿用旧连接的
语句缓存；这是源码中的重复连接与采样中 prepare/schema 工作相吻合的机制。
[SQLite SQL 编译接口](https://sqlite.org/c3ref/prepare.html)、
[Python 3.13 sqlite3.connect](https://docs.python.org/3.13/library/sqlite3.html#sqlite3.connect)

随后对同一生产 worker 做了 20 秒、49 Hz 的 py-spy Python 函数采样：
979 个样本、0 个采样错误，仅 MainThread。

| Python 调用链 | inclusive 样本占比 |
| --- | ---: |
| `PhotoInfo.json` | 52.20% |
| `PhotoInfo.asdict` | 50.77% |
| `PhotoExporter._get_photo_json_full` | 48.21% |
| `get_media_analysis_results` | 26.66% |
| `PhotoInfo.media_analysis` | 13.59% |
| `PhotoInfo.ai_caption` | 13.07% |
| `PhotoInfo.cloud_metadata` | 11.85% |
| `write_user_sidecar_files` | 8.17% |
| `ExportResults.__iadd__` | 7.66% |

**事实：** json、asdict、导出数据库完整 JSON 和媒体分析之间有父子调用关系，
不能将这些百分比相加。媒体分析与云元数据是独立分支，合计约 38.51%。
`write_user_sidecar_files` 包含模板渲染、完整 JSON 格式化及写入，该窗口约
8.17%；不是仅有文件写入占 8.17%。主要完整元数据开销发生在导出数据库的
记录更新路径，直接取消 `write_skipped` 不会消除其 48.21% 调用链。

exclusive 采样中，`plistlib._read_object` 为 8.78%、`cloud_metadata`
为 8.68%、`__iadd__` 为 7.66%、`get_media_analysis_date` 为 6.13%、
`_get_media_analysis_data` 为 6.03%、`_sqlite_table_names` 为 5.11%、
`find_files_by_prefix` 为 1.53%。exclusive 是最深 Python frame 的归因，
可以包含它直接调用的 C 函数，不等于纯 Python 字节码耗时。
原始 profile 与汇总分别保存为
[speedscope 数据](/tmp/icloud-photos-rootcause-20261005/python-speedscope.json)、
[Python 热点汇总](/tmp/icloud-photos-rootcause-20261005/python-profile-summary.json)。
这些比例只表示本次窗口，不替代整轮导出的耗时分解。

## 3. 具体重复工作的源码路径

### 3.1 云元数据每资产重新打开 Photos 数据库

**事实：** `PhotoInfo.cloud_metadata` 查询 `ZCLOUDMASTERMEDIAMETADATA.ZDATA`，
再解码 plist。它调用 `self._db.get_db_connection()`；该方法直接调用
`sqlite_open_ro(self._tmp_db)`，最终每次执行 `sqlite3.connect(...?mode=ro)`。
没有连接缓存。这意味着读取每个资产云元数据时都新开一个完整 Photos 数据库连接。
[cloud_metadata](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/photoinfo.py#L1743)、
[get_db_connection](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/photosdb/photosdb.py#L715)、
[只读连接创建](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/sqlite_utils.py#L56)

**事实：** 同一个 `PhotosDB` 已有 `_db_connection`；现有公开方法
`PhotosDB.execute(sql, params)` 复用它并返回新 cursor。可只把上述属性的查询
改用此入口，而不改变 SQL、plist 解码、返回数据或 `get_db_connection` 的所有权语义。
**方案：** 在独立副本验证逐资产输出完全相同及连接次数下降，优先评估这个
小范围改动；不要全局替换 `get_db_connection`，其他调用方可能持有或关闭独立连接。
[现有 execute 方法](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/photosdb/photosdb.py#L3404)

### 3.2 媒体分析与 AI caption 重复查询同一资产

**事实：** 完整 JSON 同时读取 `media_analysis` 与 `ai_caption`。
`media_analysis` 调用 `get_media_analysis_results(self)`，`ai_caption` 又重新
调用同一函数，再取 caption。两个属性各自的 `cached_property` 只缓存自己的
结果，不能避免第一次序列化时的这两次分析查询。
[完整 JSON 字段](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/photoinfo.py#L2250)、
[两个属性](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/photoinfo.py#L1781)

每次 `get_media_analysis_results` 进入 `_get_media_analysis_data` 后都开连接、
查分析数据、关连接；若有分析结果，再调用 `get_media_analysis_date`，重新开连接
取日期。它还解码 binary plist。因此一个有分析数据的资产可执行四次媒体分析
数据库连接/关闭，以及两次相同分析结果的查询和解码；没有结果时不再查询日期。
[数据查询与连接](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/media_analysis.py#L190)、
[另一次日期连接](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/media_analysis.py#L138)、
[结果与 plist 解码](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/media_analysis.py#L236)

**方案：** 首先让 `ai_caption` 从已缓存的 `self.media_analysis` 调用
`get_caption`。它仅选择并读取 caption，不修改输入字典；这条改动无需改造连接
生命周期，独立基准已验证受测分析结果和 caption 全部相同。数据与日期的连接
复用也有实测收益，但可放在后续，再决定如何利用现有连接所有权；不要先设计
通用连接池。两项都需保留媒体 caption、confidence 选择逻辑、date_analyzed
和全部分析字段。
[caption 选择](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/media_analysis.py#L358)

### 3.3 复用媒体后仍计算、比较及保存完整元数据

**事实：** 对有本地源文件的普通路径，媒体判断为 skip 后并未早退：仍读取
旧完整 JSON、对当前数据做 minify 和 dictdiff、保存完整 JSON、签名、digest、
date_modified 并记录历史。原片、Live Photo 视频和编辑版本均可能进入这一段。
每个资产的 JSON 对象有缓存，但旧记录读取、反序列化和数据库写入仍按媒体文件执行。
[媒体 skip 判断](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/photoexporter.py#L1366)、
[完整 JSON 缓存](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/photoexporter.py#L196)、
[记录比较与更新](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/photoexporter.py#L1490)

**事实：** 若本地所有源组件已被 iCloud 优化清走，而导出目标完整且不需更新，
`staged.update_skipped` 分支仅登记 skip/history，绕过上述数据库更新。
此时 `write_skipped` 的自定义 JSON 是本轮刷新完整元数据的途径，不能假定
导出数据库会替它更新。至少一个本地源组件仍可用时，其常规导出路径会刷新完整 JSON。
[无需下载的分支](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/photoexporter.py#L974)、
[直接 skip 分支](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/photoexporter.py#L360)

### 3.4 JSON sidecar 的额外格式化与覆盖

**事实：** 当前模板为 `${photo.json(shallow=False, indent=4)}` 且指定
`write_skipped`。它会渲染、直接打开目标文件写入，不比较是否与现有内容一致。
导出数据库用 `(indent=None, shallow=False)`；JSON 缓存键包含 indent，所以
模板还需要另一个格式化 JSON 字符串。取消 `write_skipped` 只跳过这段模板工作，
并不移除有本地源文件路径上的完整元数据构建。
[本仓库模板](../../home-manager/icloud-photos-export.py)、
[JSON 缓存键](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/photoinfo.py#L2277)、
[模板 skip 与覆盖写](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/sidecars.py#L446)

**方案：** 保留每轮完整元数据检查，仅在最终完整 JSON 字节不同、或 sidecar
缺失时写入，可保留元数据完整性并减少写入和后续 rsync 检查。仍需读取/比较
完整数据，并验证已有 sidecar 内容被手动改变时会恢复；收益不能先于基准承诺。

### 3.5 其他仍存在的全量工作

**事实：** 完整 JSON 还读取编辑/original adjustment plist、云元数据和预览
路径；预览文件名列表虽有目录缓存，每资产仍遍历同一个桶的列表筛选 UUID 前缀。
导出报告每资产写入并 flush；结束时 `cleanup` 扫描整个导出目录。它们是明确
工作，尚不能仅凭源码判定其耗时占比。
[完整字段构建](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/photoinfo.py#L2213)、
[预览前缀筛选](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/utils.py#L666)、
[报告 flush](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/cli/report_writer.py#L168)、
[cleanup 扫描](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/cli/export.py#L3318)

### 3.6 结果合并反复复制累积列表

**事实：** `ExportResults.__iadd__` 对 `uuids` 使用 `dict.update`；其他
属性使用 `getattr(self, attribute) + getattr(other, attribute)` 生成新列表，
再赋回属性，不是 `list.extend`。导出循环每个资产执行
`results += export_results`，所以 `skipped`、sidecar 等累积列表在每次合并时
都会再次被复制。列表随资产数增长时，累计复制次数形成平方级增长；不会因此
重建已经累积的 `uuids` 字典。Python 采样的 `__iadd__` 7.66% 证明它是该窗口
的第三项明确热点，但不能由这个比例承诺候选节省多少整轮时间。
[合并实现](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/exportoptions.py#L325)、
[全局逐资产合并](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/cli/export.py#L2130)

**方案：** 规模基准已将列表分支改为原地 `extend`，保留字典 `update`，
确认最终所有字段的顺序、内容、UUID 映射、返回对象及时间戳正确，但旧列表
引用的行为有变化，详见第 5.2 节。优先评估 CLI 自有累加器的原地追加，
避免未经确认就改变公开 `ExportResults.__iadd__` 的列表引用语义。

## 4. 上游是否已修复

**事实：** 2026-10-05 检查的 upstream `main` 为
`a671b60c4cc4be6db4152dbcb351ed3cf33c9bf9`，版本 0.77.2。
与本机 pin 对比，`media_analysis.py` 字节相同；`cloud_metadata` 和
`ai_caption` 的上述重复连接/查询路径仍在，`ExportResults.__iadd__` 也仍
使用列表拼接。
[该 revision 的媒体分析源码](https://github.com/RhetTbull/osxphotos/blob/a671b60c4cc4be6db4152dbcb351ed3cf33c9bf9/osxphotos/media_analysis.py)、
[该 revision 的 PhotoInfo](https://github.com/RhetTbull/osxphotos/blob/a671b60c4cc4be6db4152dbcb351ed3cf33c9bf9/osxphotos/photoinfo.py)

[该 revision 的结果合并](https://github.com/RhetTbull/osxphotos/blob/a671b60c4cc4be6db4152dbcb351ed3cf33c9bf9/osxphotos/exportoptions.py#L324)

已有两项相关改进，但范围不同：

| 上游变更 | 已证事实 | 对本机的边界 |
| --- | --- | --- |
| `a671b60c` / #2256：目录预取改用索引范围 | 原 `LIKE` 匹配无法利用现有非 NOCASE 索引，每个新目录扫描 export_data；提交附上游 292k 行、252 目录 33.9 秒→0.7 秒对照 | 值得在本机导出 DB 副本跑查询计划与计时；上游数字不能当本机收益 |
| `269f4bf0` / #2255：sidecar signature 漂移时核验内容 | built-in sidecar 内容相同时更新签名并跳过重写，主要针对 SMB/NFS/sync mtime 漂移 | 本机导出在 APFS；不覆盖自定义 `write_skipped` JSON 模板，也未解决重复连接 |

[目录预取提交及测试](https://github.com/RhetTbull/osxphotos/commit/a671b60c4cc4be6db4152dbcb351ed3cf33c9bf9)、
[sidecar 内容核验提交](https://github.com/RhetTbull/osxphotos/commit/269f4bf0091bf626fd7371c5af8b89493e119232)

**方案：** 优先考虑在现有 pin 上验证小范围补丁或单独回移已确认的上游改进。
整体升级到 0.77.2 会触及本仓库强制 0.77.1 的 Live Photo workaround，必须重新
验证原始/编辑配对视频及 burst 行为；本次没有做此升级。
[本仓库版本与 Live Photo 保护](../../home-manager/icloud-photos-export.py)

## 5. 独立基准与优化顺序

基准采用当前图库的只读 SQLite 备份和一组真实资产，避免再启动完整 PhotosDB
加载并与 2.8 GiB 的生产 worker 争抢 VM 内存。所有候选只改独立测试进程，
每个候选使用同一组资产，先比较逐资产输出，再比较连接次数、wall time 和 CPU time。
微基准只衡量相应元数据路径，不能直接外推完整导出加速倍数。

### 5.1 基准条件与结果

**事实：** 选择 100 个真实资产，筛选条件为 `ZTRASHEDSTATE=0`、`ZHIDDEN=0`
且有 master，然后按 `Z_PK` 等距采样。100 个均有云元数据，72 个有媒体分析
结果。测试使用 SQLite backup 产生的两个只读冻结数据库副本，运行三轮、
交错原始与候选方案顺序。共享连接在计时前打开并做一次 schema 读取，表中
测量的是已有连接的稳态复用；这与 `PhotosDB.execute` 使用现有连接的候选
相符，媒体连接复用首次初始化的成本另需纳入完整导出验收。下表为 100 个
资产的中位 wall time。

| 路径/候选 | 100 资产中位耗时 | 连接次数 | 该受测路径加速 |
| --- | ---: | ---: | ---: |
| 云元数据原始路径：每资产新连接 | 0.745332 秒 | 100 | 基线 |
| 云元数据：复用连接 | 0.054910 秒 | 1 | 13.57× |
| 媒体分析 + caption 原始路径 | 0.450132 秒 | 344 | 基线 |
| 媒体分析 + caption：仅复用分析结果 | 0.188200 秒 | 172 | 2.39× |
| 媒体分析 + caption：仅复用连接 | 0.166068 秒 | 1 | 2.71× |
| 媒体分析 + caption：连接和结果均复用 | 0.075710 秒 | 1 | 5.95× |

**事实：** 所有受测云元数据输出逐项相等，所有媒体分析结果及 caption 输出
逐项相等。云元数据 CPU time 中位数约 0.671745 秒→0.054865 秒；媒体分析与
caption 的两者复用 CPU time 约 0.442227 秒→0.075412 秒。wall time 与 CPU
time 同时下降，确认这些路径存在可去掉的计算开销；不是只靠省略字段换取速度。

结果与可复查脚本保存在宿主：

- [基准 JSON](/tmp/icloud-photos-rootcause-20261005/performance-benchmark.json)
- [基准脚本](/tmp/icloud-photos-rootcause-20261005/performance-bench.py)
- [媒体路径 cProfile](/tmp/icloud-photos-rootcause-20261005/media-baseline-profile.txt)
- [生产 worker 原生采样](/tmp/icloud-photos-rootcause-20261005/backup-cpu-sample.txt)

**事实：** 另一次开启 cProfile 的同样媒体基线，调用
`get_media_analysis_results` 200 次：100 次来自 `media_analysis`、100 次来自
`ai_caption`。1,854 次 `plistlib.loads` 的累计时间为 0.403 秒；344 次连接
`close` 为 0.253 秒；connection/cursor `execute` 合计约 0.335 秒。这支持
结果复用会同时减少 plist 解析、连接和 SQL 工作。启用 profiler 的这一轮总计
1.167 秒，明显增加了观测开销，不能用它替代上表未启用 profiler 的计时；
累计时间也不应与其父函数时间相加。

344 次媒体连接来自两次同资产结果查询，每次为 100 次数据查询连接加
72 次分析日期连接；只复用结果后变为 172 次，与源码的重复路径吻合。云元数据
候选在冻结副本复用连接；生产实现可使用现有 `PhotosDB.execute`，其确切端到端
收益仍需后续完整导出验证。

**局部外推，不是整轮承诺：** 优先两条小改动（云连接复用、分析结果复用）的
每资产差值为
`((0.745332-0.054910)+(0.450132-0.188200))/100 = 0.00952354` 秒。
按本轮 51,535 个资产线性计算约 490.8 秒，即 8.18 分钟。样本比例、实际资产
数据大小、缓存状态和其余导出工作都会影响真实收益，不能据此承诺整轮减少
8.18 分钟，更不能把 13.57× 或 5.95× 宣传为完整备份加速。

在结果复用之外再做媒体连接复用，此样本增量为
`(0.188200-0.075710)/100 = 0.0011249` 秒/资产，按同样方式约 0.97 分钟。
收益存在，但当前应先实施和验证两条局部小改动，避免先扩大连接管理改动。
测试用约 2 GiB 的数据库临时副本已自动清理；没有写入生产数据库或正在运行的
导出 worker。

### 5.2 累积结果的规模基准

**事实：** 在 Linux 宿主（Xeon Gold 5115）通过 AST 原样加载 pinned 源码的
`ExportResults` 类，候选仅将列表拼接改为 `extend`。每资产的合成输入包含
两个 skipped 媒体、一个自定义 JSON sidecar、一个 skipped XMP 和一个 UUID
映射；对象构造不计入下表，只测累积合并。四个规模各运行一次，不是三轮中位数。

| 合成资产数 | 原始列表拼接 | 原地追加 | 受测合并路径加速 |
| --- | ---: | ---: | ---: |
| 5,000 | 0.393 秒 | 0.044 秒 | 8.85× |
| 15,000 | 4.695 秒 | 0.143 秒 | 32.76× |
| 30,000 | 24.416 秒 | 0.325 秒 | 75.23× |
| 51,535 | 108.871 秒 | 0.480 秒 | 226.61× |

这确认了复制累积列表的规模成本；缓存及内存访问也会影响曲线。它不包括媒体、
元数据或 sidecar 工作，平台与真实输入密度也不同，因此 226.61× 不能作为完整
备份提速倍数。生产窗口的该函数样本占比为 7.66%，应再做完整导出前后对照。
[原始规模基准数据](/tmp/icloud-photos-rootcause-20261005/export-results-benchmark.json)

**已验证的行为边界：** 每种规模的最终全部结果属性值、列表顺序和 UUID 映射
相等；两者返回 `self`，保留累加器创建时的时间戳；受测输入没有在左右结果间
共享列表，传入的另一结果列表没有改变。
但若构造累加器时传入非空列表 `source = ["old"]`，或者外部保存旧列表引用，
原始实现合并后让这些旧引用保持 `["old"]`，候选则将它们改为
`["old", "new"]`。两者最终 `skipped` 都是 `["old", "new"]`，但别名语义
并不相同。候选不能以“结果等价”替代这个 API 行为决策。

### 5.3 按实测收益和实施风险排序

| 顺序 | 候选 | 收益与风险 | 完整元数据 |
| --- | --- | --- | --- |
| 1 | 云元数据改用现有 `PhotosDB.execute` 连接 | 受测路径 13.57×；改动局部，复用现有入口，需完整导出验证 | 保留 SQL、全部字段与 plist 解码 |
| 2 | `ai_caption` 复用 `media_analysis` | 受测路径 2.39×，连接数减半；一处属性改动，无需增加连接池 | 受测所有分析内容、日期及 caption 相等 |
| 3 | CLI 自有结果累加器改原地追加 | 合成规模基准 108.871 秒→0.480 秒；全部属性值相等，但直接改公开方法会改变旧列表引用语义 | 不删任何结果；仍需真实 CLI 整轮验收 |
| 4 | 回移上游目录预取索引范围 | 降低按目录全表扫描；上游已有结果等价与索引测试，仍需本机计时 | 不减少任何字段或资产 |
| 5 | 媒体分析数据/日期复用只读连接 | 在结果复用基础上另省约 1.12 毫秒/资产；涉及连接生命周期，先局部验证再设计 | 受测所有分析内容、日期及 caption 相等 |
| 6 | 完整 JSON sidecar 仅在内容变化时写入 | 尚无本机收益数字；当前窗口调用链约 8.17%；需验证缺失及内容变化 | 保留每轮完整元数据刷新 |
| 7 | 优化每媒体文件重复的旧 JSON 读取/比较/写入 | 尚无本机收益数字；需确保原片、配对视频、编辑版记录及历史正确，范围较大 | 必须保留各文件记录和完整资产数据 |

不建议用增加 VM 核数、并发整个 Photos 导出、取消分析字段或直接去掉
`write_skipped` 代替上述验证。当前循环是串行，更多核数不自动让它并行；并发还
涉及 PhotoKit/AppleScript 与 SQLite 连接所有权，且 VM 内存已需同时容纳图库。
这是基于当前源码路径的工程判断，不是这些方案绝对无效的性能结论。

## 6. 元数据完整性的验收约束

**事实：** Photos ≥5 的 `date_modified` 来自 `ZADJUSTMENTTIMESTAMP`，不是
`ZMODIFICATIONDATE`。它代表编辑调整时间，不能作为标题、说明、关键词、收藏、
相册/文件夹改名、人物命名或后台分析变化的完整变更信号。普通 `--update` 的
原片 skip 判断也不使用完整元数据比较来决定重导出；只有 `force_update` 分支
比较 digest，而 digest 是浅层字段并排除某些数据。
[date_modified 来源](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/photosdb/photosdb.py#L2140)、
[字段赋值](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/photosdb/photosdb.py#L2164)、
[媒体更新判断](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/photoexporter.py#L734)、
[digest 字段选择](https://github.com/RhetTbull/osxphotos/blob/2be2970fc0a38b087a65215a8bdb7058a7d6ffef/osxphotos/photoinfo.py#L2312)

因此候选优化应满足：微基准受测属性的全部返回字段等价，并在后续完整导出中
核验完整元数据；保留 Live Photo 原始和编辑资源导出；媒体未变但元数据变化时
仍更新 JSON；本地源存在和全部被优化清走的两条路径都正确；JSON sidecar 缺失
或内容损坏时能重建。当前仅研究，尚未声称任何候选通过了生产完整导出的验证。

## 7. 当前版本的完整导出观察

删除异常资产后，使用未应用上述优化的生产版本重跑。服务于 02:18:31 启动，
02:19:31 开始资产导出，03:13:05 完成：51,535 个资产，导出 132 个媒体文件，
跳过 81,515 个媒体文件，missing=0、error=0；日志报告导出阶段耗时 53 分 34 秒。
03:13:18 发布 complete=true 的状态后进入宿主 rsync 归档，03:18:13 服务退出
成功，总耗时 59 分 42 秒；导出状态发布后到宿主完成约 4 分 55 秒。

宿主新报告、complete=true、missing=0、errors=0 和 last-success 均已核对，
失败指标归零。staging 清理了已删除资产的七个文件；ZFS 归档仍保留此前的
JPG 和编辑后 MOV，符合 rsync 不传播删除的现有策略。

这是恢复验证和可供比较的现场观察，期间有采样、监控和独立基准，且存在新增
媒体；不是没有观察开销、完全无变化输入的严格性能基线。候选的整轮验收应
保持输入与运行条件可比，分别记录加载、导出、cleanup 和归档传输的耗时。

## 8. 三项优化的实现与验收

实现保持 0.77.1 与源码 pin 不变，以
[静态源码补丁](../../pkgs/osxphotos-performance.patch) 在
[Nix 包构建](../../pkgs/osxphotos.nix) 中应用：

1. `cloud_metadata` 使用现有 `PhotosDB.execute` 的只读连接，保留原 SQL、
   Photos ≤4 的空结果、全部 plist 数据及原来的解码异常行为。
2. `ai_caption` 从同一 PhotoInfo 已缓存的 `media_analysis` 提取，保留 caption
   的选择规则和空字符串结果。
3. 仅 CLI 的自有总结果累积循环使用列表 `extend` 和 UUID 字典 `update`。
   公共 `ExportResults.__iadd__`、逐资产结果合并及导出报告结构均未修改。

未减少元数据字段，保留完整 JSON 每轮刷新及现有原片/编辑版 Live Photo 导出。
新运行环境为
`/nix/store/rcr4rix8nwyb4rqq6lhcrna6rhmr23n0-osxphotos-0.77.1`；通过授权 Terminal
执行 `just darwin`，退出状态为 0，并核对实际导出 wrapper 使用新环境。
系统 closure 仅替换 OSXPhotos 与相应 Home Manager/激活引用；包版本及依赖不变。

### 8.1 独立回归和安装包验证

**事实：** 补丁在 pinned 源码的临时副本零 fuzz 应用。实际原/新 CLI 累积 AST
覆盖全部 35 属性、零结果、空结果、混合结果、列表顺序、错误 tuple、重复 UUID
后者覆盖、创建时间及生产者列表/字典引用，均相等。公共 ExportResults 模块
逐字节不变；旧 `+=` 列表引用行为和 TypeError 保留，复用上游的三项
`test_exportresults.py` 测试均通过。两处 PhotoInfo 修改另通过正常/缺失/坏 plist、
Photos 4 及七种 caption × 两种访问顺序的 14 个用例。
[回归结果](/tmp/icloud-photos-rootcause-20261005/performance-patch-regression.json)

**事实：** 在实际安装包上，对冻结的 Photos 与 MediaAnalysis SQLite 副本等距
选择 100 个真实资产，三轮交错顺序复测原版、仅云连接复用、云连接及 caption
复用。三个方案的云元数据、媒体分析全部字段、分析日期及 caption 逐项相等；
100 项有云元数据、69 项有分析结果、14 项有非空 caption。

| 100 资产的受测元数据路径 | 中位 wall time | 每轮新 SQLite 连接 |
| --- | ---: | ---: |
| 原版 | 1.754 秒 | 438 |
| 仅云连接复用 | 1.049 秒 | 338 |
| 云连接及 caption 复用 | 0.548 秒 | 169 |

该局部测试期间有包构建，不作为无竞争的整轮性能结论；仅计上述元数据路径，
不含 PhotosDB 加载、媒体和 sidecar 工作。测试使用的第一份构建与最终部署构建
仅有 patch 文本空白的区别，相关安装源码逐字节相同；实际 sample 导出使用最终
部署环境。
[安装包验证结果](/tmp/icloud-photos-rootcause-20261005/runtime-verification.json)

**事实：** 使用同一 PhotosDB 快照、同一加载的搜索数据及冻结的媒体分析库，
另外逐资产比较 100 项 `photo.json(shallow=False, indent=4)`。原版与补丁版
的完整 JSON 字节完全相等。
[完整 JSON 对照](/tmp/icloud-photos-rootcause-20261005/full-json-verification.json)

**事实：** 第三项的实际 CLI 累积 AST 在 Linux 宿主重测 51,535 个合成资产，
每项含两个 skipped 媒体、一个 JSON sidecar、一个 skipped XMP 和一个 UUID；
对象构造不计时，原/新各测一次：113.797 秒→0.470 秒，35 属性及顺序相等。
约 242× 仅是该累积操作，不能外推完整备份。
[实际循环规模基准](/tmp/icloud-photos-rootcause-20261005/cli-accumulation-benchmark.json)

### 8.2 临时导出验收

**事实：** 在独立临时目录用真实 wrapper 验证普通照片、视频、未编辑 Live Photo、
编辑 Live Photo、关闭 Live 的编辑版及连拍。六个选择项展开为 13 个资产，原版
首次导出 27 个媒体文件；补丁版增量导出全部 27 个媒体复用，missing=0、error=0。
共 73 个媒体/sidecar 文件的大小与 SHA-256 完全一致；故意删除及损坏的两个 JSON
sidecar 均恢复成原版完整内容。只在临时导出目录测试，没有对生产 staging 使用
UUID 筛选的 cleanup。
[样本导出验收](/tmp/icloud-photos-rootcause-20261005/sample-export-verification.json)

**事实：** 在独立测试进程中，将普通照片的内存元数据标题改为测试值，再执行
同样的增量导出，27 个媒体文件仍全部跳过且 SHA-256 不变，完整 JSON sidecar
写出新标题。测试没有更改 Photos 图库，也没有省略元数据刷新。
[元数据变更验收](/tmp/icloud-photos-rootcause-20261005/metadata-refresh-verification.json)

构建的 `pip check`、Darwin 原生依赖导入和版本检查通过；本仓库
`just fmt`、`just check`、`just fmt-check` 及 `git diff --check` 通过。

### 8.3 优化后生产采样

**事实：** 已部署环境的生产 worker PID 8364，在本轮导出前段进行相同配置的
20 秒、49 Hz Python 采样，979 个样本、0 errors。`cloud_metadata` inclusive
为 2.04%，`get_media_analysis_results` 16.14%，`ai_caption` 未命中采样，
公开 `__iadd__` 仅 0.20%；完整 JSON 的 `_get_photo_json_full` 为 28.80%。

剩余热点包括目录记录预取 `prefetch_directory_records`（exclusive 25.03%）、
媒体分析数据/日期查询（exclusive 7.35% / 5.62%）和逐文件旧 JSON 读取。
这支持已移除的重复工作不再是同样的热点；前后采样来自不同时间及资产窗口，
不能把占比变化直接换算成完整导出的秒数或加速倍数。本次按用户指定只实现
前三项，目录预取索引及进一步媒体连接复用列为后续选项。
[优化后采样](/tmp/icloud-photos-rootcause-20261005/optimized-python-speedscope.json)、
[优化后热点汇总](/tmp/icloud-photos-rootcause-20261005/optimized-python-profile-summary.json)

**事实：** 本轮 10:44:15 的两次原生 top 采样中，worker MEM 为
5,214–5,219M，系统压缩器约 2,772–2,773M；该一秒区间新增 swapin/swapout
均为 0。RSS 会因压缩与 MEM 明显不同，不能用监控中的较小 RSS 宣称内存
下降。本次优化没有解决完整元数据对象缓存的持续内存占用。
[优化后内存采样](/tmp/icloud-photos-rootcause-20261005/optimized-memory-sample.txt)

### 8.4 完整生产导出

**事实：** 06:00 自动备份仍使用原版，06:00:56 开始资产导出，06:50:08
完成，日志耗时 49 分 11 秒：51,474 个资产、0 个媒体新增、81,553 个媒体跳过、
missing=0、error=0；06:54:45 服务完成，总耗时 54 分 45 秒。它比第 7 节含有
新增媒体及调查工作负载的 53 分 34 秒观察更适合本次比较。

**事实：** 部署三项优化后，10:21:36 启动完整服务，10:22:26 开始资产导出，
10:53:36 完成。日志耗时 **31 分 10 秒**，资产数及媒体结果完全相同：
51,474 个资产，0 exported、0 updated、81,553 skipped、missing=0、error=0。
较上述原版观察减少 **18 分 1 秒（约 36.6%）**，导出吞吐约 1.58 倍。
随后 staging cleanup 删除 0 个文件；10:53:49 发布 complete=true、missing=0、
errors=0 的状态。
[原版完整日志](/tmp/icloud-photos-rootcause-20261005/latest-baseline-backup.log)、
[优化后完整日志](/tmp/icloud-photos-rootcause-20261005/optimized-backup.log)

宿主已收到 194,079 条的新报告，missing、error、sidecar_user_error、
exiftool_error、user_error 五列均为 0。全部 51,474 个 UUID 集合及
81,553 个媒体的文件名/UUID 集合与原版报告完全相同；原报告的额外 218 条
是那一轮 staging cleanup 的删除记录。
[归档报告核对](/tmp/icloud-photos-rootcause-20261005/optimized-archive-report-verification.json)

这是一次同规模、同配置、同媒体复用数量的生产前后观察，非多轮随机化 A/B。
文件缓存、后台 Photos 工作及单资产耗时仍可能影响时间；本次新版本有
20 秒采样及低频只读监控。完整流程保留全字段、完整 JSON 刷新及原片/编辑版
导出策略，不把局部的 13× 或 242× 当作整轮加速。

**最终归档验收：** 10:58:26 宿主服务成功结束，完整备份耗时
**36 分 50 秒**，原版同规模观察为 54 分 45 秒，减少 **17 分 55 秒
（约 32.7%）**。从 guest 发布完成状态到服务结束为 4 分 37 秒，包含进程
退出及 rsync；最终物理检查确认全部 **81,553 个媒体文件**在 ZFS 归档实际存在，
且均非空。

服务 `Result=success`、`ExecMainStatus=0`；last-success 与完成时间均为
`1791169106`（10:58:26 +08）。`backup_failed`、`export_missing`、`export_errors`
三个指标均为 0，APFS 使用比例约 51.28%。

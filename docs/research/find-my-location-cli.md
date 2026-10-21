# macOS Find My 坐标与 CLI

日期：2026-10-21

后续已完成物品采集修复：撤销阻塞 HCI 初始化的旧补丁、采用系统虚拟蓝牙模式，
并修正 `Items.data` 的 `identifier` 字段映射。当前七条物品可读，六条有持续更新的
坐标；详见 [服务验证记录](../findmy.md) 与
[HCI 修复记录](hackintosh-idle-cpu.md#find-my--airtag-后续修复2026-10-21)。
下文初次验证中的“Items.data 未生成”保留为当时的历史结果。

初次调研只阅读上游文档与源码；随后按要求在 el2 的 Hackintosh 上做了现场验证，见文末。
项目声称支持某个 macOS 版本，不代表已验证更新版本；下面没有任何 macOS 27 的实测结论。
本机为 27.0.1，远端 Hackintosh 为 26.6.2。

## 官方接口与结论

本次未找到 Apple 面向用户提供的 Find My 坐标查询 CLI 或通用公开 API。
Apple 的 [Find My 开发者入口](https://developer.apple.com/find-my/)介绍的是通过 MFi 接入配件网络；
[Core Location](https://developer.apple.com/documentation/corelocation)提供运行该应用的设备定位，
并不是读取 Apple 账户下其他设备、物品与联系人的接口。

对于同时记录三类对象的目标，目前没有核实到一个在 macOS 27 上即装即用、能统一输出经纬度的方案。
建议先验证自有设备的 iCloud 路径，再决定是否投入物品与联系人的缓存解密路径。

## 第三方方案

| 目标 | 方案 | 坐标能力与限制 |
| --- | --- | --- |
| 自有设备，以及账户获准查看的家庭设备 | [pyicloud](https://github.com/timlaing/pyicloud) | 使用 iCloud Web 服务，可输出经纬度、定位时间、精度及电量；支持持续轮询，不等于覆盖 AirTag 或“联系人”列表 |
| AirTag、Find My 配件的定位报告 | [FindMy.py](https://github.com/malmeloo/FindMy.py) | Python 库可解密经纬度、报告时间和精度；需要设备密钥与账户会话，当前内置 CLI 主要用于导出配件信息 |
| “设备”“物品”“联系人”的本地缓存 | [findmy-cache-decryptor](https://github.com/PnutCN/findmy-cache-decryptor) | 解密现有缓存为 plist；需先取得 FMIP/FMF 密钥，不是独立的实时查询服务 |
| 上述缓存的密钥提取 | [findmy-key-extractor](https://github.com/sabey/findmy-key-extractor) | 上游要求暂时关闭 SIP 与 AMFI；属于高侵入性的前置步骤，不是位置 CLI |
| GUI 中显示的设备、物品、联系人 | [findmy-cli](https://github.com/omarshahine/findmy-cli) | 截图加 OCR，支持 JSON 与历史记录；只提取地点文字、距离、更新时间等，不提供经纬度 |

### 自有设备：优先验证 pyicloud

[PyPI](https://pypi.org/project/pyicloud/)当前发布版为 `2026.10.1`，对应维护仓库为
`timlaing/pyicloud`。本次同时静态检查该版本 wheel 的 `devices.py` 与 `normalize.py`，
确认发布包包含下述 CLI 轮询与 JSON 输出能力，未执行包内代码。

[设备文档](https://github.com/timlaing/pyicloud/blob/3bed0780454855b3e4adde8c933c744753399b26/docs/services/devices.md)
列出位置字段 `latitude`、`longitude`、`timeStamp`、`horizontalAccuracy`、`isOld`。
[CLI 源码](https://github.com/timlaing/pyicloud/blob/3bed0780454855b3e4adde8c933c744753399b26/pyicloud/cli/commands/devices.py)
支持 `--locate`、`--with-family`、`--refresh-interval`，无限轮询的 JSON 模式每轮输出一个紧凑 JSON 数组。
下面是可由用户后续执行的示例，本次没有安装、登录或启动采集：

```sh
uv tool install 'pyicloud[cli]==2026.10.1'
icloud auth login --username '你的 Apple 账户'
icloud devices list --locate --format json
icloud devices list --locate --refresh-interval 300 --format json >> devices.jsonl
```

中国大陆账户登录时添加 `--china-mainland`；家庭设备查询添加 `--with-family`，能否返回位置仍取决于账户权限。
[登录与 CLI 文档](https://github.com/timlaing/pyicloud/blob/3bed0780454855b3e4adde8c933c744753399b26/docs/guides/cli.md)
明确说明会话会按 Apple 决定的周期失效，需要重新认证。它是非官方 Web 接口客户端，
上述静态核实不能替代真实账户的登录与位置可用性测试。

### FindMy.py：有坐标，但新系统上的密钥获取是关键障碍

上游的 [`LocationReport`](https://github.com/malmeloo/FindMy.py/blob/22e4879426f97c9b0a1a33b22dac34ef0cf3d02f/findmy/reports/reports.py)
确实包含 `latitude`、`longitude`、`timestamp`、`horizontal_accuracy`。不过
[`python -m findmy`](https://github.com/malmeloo/FindMy.py/blob/22e4879426f97c9b0a1a33b22dac34ef0cf3d02f/findmy/__main__.py)
当前只有 `decrypt` 子命令；查询需要使用 Python API 或项目示例，不能把它描述成完整的位置查询 CLI。

官方配件需要先从 Mac 导出密钥。上游
[获取位置文档](https://github.com/malmeloo/FindMy.py/blob/22e4879426f97c9b0a1a33b22dac34ef0cf3d02f/docs/getstarted/02-fetching.md)
区分了系统版本：macOS 15 可能需要额外的 BeaconStoreKey 提取工具；macOS 26 的保护仍是障碍，
文档明确说单独关闭 SIP 似乎也无法解决。运行查询可以跨平台，不等于首次提取官方配件密钥不需要 Mac。

同一文档提醒，默认导出的报告 JSON 可以包含解密密钥。如果只想留轨迹，应自行写出需要的坐标、时间和精度字段，
不要把账户会话或设备密钥混入轨迹文件。

### 缓存解密：联系人与物品的另一条路径

[findmy-cache-decryptor 源码](https://github.com/PnutCN/findmy-cache-decryptor/blob/ff01ffda51dafdf1993ddd9ae15ff7e206120266/decrypt_findmy.py)
处理 FMIP 的 `Devices.data`、`Items.data`，以及 FMF 的 `FriendCacheData.data`，使用外部提供的对称密钥解密。
[README](https://github.com/PnutCN/findmy-cache-decryptor/blob/ff01ffda51dafdf1993ddd9ae15ff7e206120266/README.md)
称它针对 macOS 14.4 起的缓存加密设计；这不是 macOS 27 兼容性保证，也不能保证缓存包含新鲜位置。

[findmy-key-extractor README](https://github.com/sabey/findmy-key-extractor/blob/378abfe6f9d6a8a110e7a70c9033a539420e042e/README.md)
声称验证过 macOS 15.7.2 Intel 与 26.5.2 Apple Silicon，要求暂时关闭 SIP、AMFI，并通过调试系统进程取得
`LocalStorage.key`、`FMIPDataManager.bplist`、`FMFDataManager.bplist`。它提取的缓存密钥与
FindMy.py 文档里的 BeaconStoreKey 属于不同用途，不能据此前者可用就判断后者的问题已经解决。
为了日常轨迹记录而削弱系统保护，通常不值得优先选择。

联系人还有一个现成的 GUI 桥接方案
[FollowMyFriends](https://github.com/bytePatrol/FollowMyFriends/blob/967a82e5af6f4d0e8742136b5fb728d9191f8f46/README.md)：
读取本地数据库并向 MQTT 发布 `latitude`、`longitude`、`gps_accuracy`、`location_timestamp`。
它没有现成 CLI，首次设置仍要求预先取得 `LocalStorage.key`；
其[解密代码](https://github.com/bytePatrol/FollowMyFriends/blob/967a82e5af6f4d0e8742136b5fb728d9191f8f46/FollowMyFriends/Services/FindMyDecryptor.swift)
只是从文件加载密钥，不负责提取。README 的“无需 SIP bypass”不能理解成首次提取密钥也无需调整系统保护，
也没有 macOS 27 的验证证据。

### findmy-cli：名字相符，输出却不是坐标

[README](https://github.com/omarshahine/findmy-cli/blob/04ec970ae268aade5e613363ba31a33c83d0373c/README.md)
说明它驱动 Find My 窗口，截图后用 Vision OCR 读取侧边栏，支持 `people`、`devices`、`items` 与 `--json`，
需要屏幕录制权限，滚动和点击还需要辅助功能权限。它会影响前台窗口，并要求显示器保持唤醒和解锁。
项目明确不提取地图上的 pin；macOS 26 及之后的 `--zoom` 也不能取得更精细的街道地址。

其 [SQLite 表结构](https://github.com/omarshahine/findmy-cli/blob/04ec970ae268aade5e613363ba31a33c83d0373c/internal/findmy/ledger/ledger.go)
保存观察时间、对象名称、地点文字、更新时间文字和距离等字段。它适合记录“某时看到某人在某城市”，
不适合直接导出经纬度轨迹。

## 对轨迹记录的影响

以上工具分别读取定位报告、缓存或界面文本，能力不能互相替代。
Apple 的[物品定位说明](https://support.apple.com/en-asia/guide/iphone/ipha779f0c10/27/ios/27)
说位置在物品连接到 Find My 网络时更新；定期查询不意味着物品以同一频率产生新定位。
这些工具也不能保证恢复过去完整的轨迹。

记录设计建议：同时保存稳定对象 ID、经纬度、精度、来源定位时间与实际采集时间；
用对象 ID 和来源时间去重，保留定位失败与采集空档，避免将旧位置反复记成新轨迹点。
长期使用可将 JSONL 导入 SQLite，之后导出 GPX；此处只是方案建议，没有部署采集器。

## el2 Hackintosh 现场验证（2026-10-21）

目标为 Incus `hackintosh`，SSH `yifan@100.64.2.80`，macOS 26.6.2（25G83）、Intel x86_64。
连接前核对了本机名称、地址与目标 DNS，确认目标不是本机。测试前 SIP 与 authenticated root 均开启，
`kern.bootargs` 为 `vsmcgen=2`。

### 已完成的验证

打开 Find My 后，下列缓存生成于 `~/Library/Caches/`：

| 缓存 | 实测结构 | 结论 |
| --- | --- | --- |
| `com.apple.findmy.fmipcore/Devices.data` | 外层 plist 字典，含 `encryptedData`、`signature`；样本密文 29,400 字节 | 已确认设备缓存存在且加密 |
| `com.apple.findmy.fmfcore/FriendCacheData.data` | 同上；样本密文 5,691 字节 | 已确认联系人缓存存在且加密 |
| `com.apple.findmy.fmipcore/Items.data` | 本次探测时未生成 | 尚未验证物品缓存，不表示账户没有物品 |

SSH 用户与 `sudo` 进程读取缓存正文均被 TCC 拒绝。通过远端 Terminal 打开只读 `.command` 探针，
使用 Terminal 的现有访问权限读取成功；没有修改 TCC 数据库、添加完全磁盘访问权限或输出位置内容。

在普通 SSH 会话和 Terminal 中分别调用 Security.framework 的 `SecItemCopyMatching`。
查询禁止交互，不会等待钥匙串确认弹窗；只记录 OSStatus，不输出数据：

| 查询 | FMIPDataManager | FMFDataManager |
| --- | --- | --- |
| 普通 service 查询 | `-25300`（item not found） | `-25300` |
| 显式 Data Protection Keychain | `-25300` | `-25300` |
| 加 Apple 的 `0000000000.com.apple.findmy` access group | `-34018`（missing entitlement） | `-34018` |

这说明普通进程的查询缺少所需 entitlement；`-25300` 不能据此解释成账户没有密钥。
与[上游提取器说明](https://github.com/PnutCN/FMIPDataManager-extractor)中的权限要求一致。

### 验证环境与原始配置备份

远端私有目录为 `~/.local/state/findmy-cache-validation/2026-10-21/`，权限 `0700`，包含只输出摘要的探针、
未修改的 `decrypt_findmy.py`、独立 Python 环境（`cryptography==48.0.1`），以及 Intel 密钥提取程序。
该提取程序按上游查询调用 Security.framework，带同一 keychain access group，仅向私有文件保存结果，
不向终端输出密钥；在本地交叉编译，不要求远端安装 Xcode 工具链。

系统盘 EFI 只读挂载后已备份 OpenCore `config.plist`，然后卸载。私有备份为
`OpenCore-config.before.plist`，权限 `0600`，SHA-256 为
`418652df3f1d8bce143a1dc83e84916946bbd847f8cc0c6c30aba8dc7124cf9f`，
与运维文档记录一致。备份含机器身份，仅保存在远端，不提交 Git。

### 临时提取密钥与实际解密

用户批准了临时关闭 SIP/AMFI、提取密钥、恢复设置，以及本次所需的全部 Hackintosh 重启，
并明确重启单独确认规则仅适用于 NixOS 主机，不适用于其下运行的虚拟机；仓库 `AGENTS.md` 已同步澄清。
el2 宿主没有重启。

通过 OpenCore 临时设 `csr-active-config=7f000000`、在原 `vsmcgen=2` 后追加
`amfi_get_out_of_my_way=1`，并在 NVRAM Delete 中加入 `csr-active-config` 以确保覆盖旧值。
首次重启后实测 SIP disabled，authenticated root 仍 enabled，启动参数与候选配置一致。
原生提取程序成功读出两个 171 字节 key plist，文件均为 `0600`，未将密钥内容输出到终端。

随后在 Terminal 中运行上游 `FindMyDecryptor` 对缓存副本解密，截获并丢弃上游的明文终端输出，
只保存摘要及私有文件。成功标准采用实际 AEAD 校验通过、明文可解析、再检查坐标与源定位时间，
不使用上游在缺失缓存时可能误报成功的 `verified`。

| 对象 | 实际结果 |
| --- | --- |
| 设备 | AEAD 通过，解析为 33 条记录；14 条含经纬度及源定位时间。两次采样的最大源时间由 `1792564180818` 更新为 `1792564262516`，证明本次观察到新定位，而不只是缓存文件时间变化 |
| 联系人缓存 | AEAD 通过，解析为含 17 个顶层字段的字典；未发现坐标，也没有嵌套二进制 plist 可进一步解出坐标。这不是联系人经纬度查询成功 |
| 物品 | 已通过控制台选择 Items 页，但本次仍显示 Loading，尚未生成 `Items.data`，未完成物品解密验证 |

设备坐标快照位于远端验证目录的 `device-locations.json`，包含对象 ID、名称、经纬度、精度及源定位时间，
不包含缓存密钥。原始加密样本及解密 plist 位于 `samples/`，目录与文件均限制为当前用户访问。

恢复过程中确认：重启后系统盘与 Photos 数据盘的 `disk0`/`disk1` 编号发生交换，
因此必须从根 APFS 的 `APFSPhysicalStores` 重新定位系统盘 EFI，不能沿用重启前的 disk 编号。
macOS 即使在此次临时 SIP 配置下也拒绝直接写入 `csr-active-config`；恢复改由 OpenCore 启动时
先删除旧 NVRAM 值、再写入备份中的零值和原 boot-args，随后恢复原始配置文件。

### 恢复保护后的复测

第二次重启后实测 SIP enabled、authenticated root enabled，`kern.bootargs` 恢复为 `vsmcgen=2`。
原始 OpenCore 配置已逐字节恢复，SHA-256 再次与上述备份一致，EFI 已卸载；临时 NVRAM Delete 项
只用于这次恢复启动，未留在最终配置中。Photos 进程恢复运行，`/Volumes/Photos` 正常挂载。

在保护开启的正常环境下，再次使用同一组已提取密钥调用上游解密代码，设备与联系人缓存均通过 AEAD 校验。
设备仍为 33 条记录、14 条有坐标及源定位时间，最新源时间进一步更新为 `1792564479910`。
因此这台机器的设备缓存路径已验证：**只需在首次提取密钥时临时调整保护，日常解密不需要保持 SIP/AMFI 关闭**。
当前通过已有权限的 Terminal 运行；直接 SSH 进程的缓存访问权限问题没有被修改。

最终摘要保存在远端验证目录的 `final-validation-summary.json`，保护与配置校验记录为
`restored-system-summary.json`；`device-locations.json` 已更新为恢复保护后的设备快照。
本次没有部署后台定时采集服务。物品缓存仍未取得，不能宣称三类对象都已验证成功。

联系人经纬度还需要 `findmylocateagent` 的 `LocalStorage.db`，不能拿 FMF 缓存的成功替代。
[上游密钥说明](https://github.com/sabey/findmy-key-extractor)将它列为独立的 `LocalStorage.key`，
与 FMIP/FMF 缓存密钥不同；其后续提取与更新验证如下。

## LocalStorage.db 解密与持续更新验证（2026-10-21）

按后续要求，在同一 Hackintosh 上继续提取联系人数据库的独立密钥。安装 Apple 官方
Command Line Tools 26.6，使用 `lldb-2100.0.17.203`；仅安装工具链，没有安装 catalog 中的 Safari 或系统更新。
复用已核对的临时 OpenCore 设置，在 `findmylocateagent` 的 `sqlite3_key_v2` 入口调用
上游 `extract_db_key.py`。首次 LLDB/debugserver 初始化慢于代理启动，采样确认调试器仍在等待新进程后，
重新触发该代理启动，随后捕获了明确来自 `LocalStorage.db` 的 32 字节密钥。
CloudStorage 的命中被跳过，未混用密钥。

密钥保存在同一远端私有验证目录的 `keys/LocalStorage.key`，权限 `0600`。未输出密钥字节。
初次解密读到 5 条联系人记录，其中 1 条含坐标与源定位时间、4 条暂无可用坐标；
`PRAGMA integrity_check` 返回 `ok`。

### 快照与 WAL 处理

实际数据库位于
`~/Library/Group Containers/group.com.apple.findmy.findmylocateagent/Library/Application Support/LocalStorage.db`。
初次探测主文件仅 4,096 字节、WAL 为 881,712 字节。`lsof` 确认只有当前用户的 `findmylocateagent`
打开这些文件，近期数据不能仅靠复制主文件取得。

上游 `decrypt_localstorage.py` 直接应用所有完整 WAL 帧，未校验事务提交边界、salts 或校验链。
此次保留其 AES 页解密实现，验证程序按 [SQLite 官方 WAL 格式](https://sqlite.org/fileformat2.html#walformat)
先验证头、页大小、salts 与累计 checksum，只合并最后有效提交之前的帧，最后按提交页数截断。
checksum 算法另用 SQLite 实际生成的 WAL 核对，通过 5 帧、4 次提交。

每次采样会短暂 `SIGSTOP` 定位代理，等 `ps` 确认状态为 `T` 后复制 DB 和 WAL，
在 `finally` 中立即 `SIGCONT`；解密及 SQL 查询均在副本上运行，不对原数据库做 checkpoint。
首次运行 `integrity_check`，其余样本运行 `quick_check`，以排除并发写入导致的不一致样本。

联系人通过 `friends.handleServerIdentifier = secureLocations.serverUserID` 关联，
解析 `secureLocations.value` 的二进制 plist。NSDate 按 UTC 处理，数字时间按自 2001-01-01 起的秒数换算；
定位时间缺失时保留缺失，不伪造为采集时间。

### 正常保护状态下验证

密钥提取后已完成恢复重启：SIP enabled、authenticated root enabled、boot-args 为 `vsmcgen=2`，
OpenCore 原文件已按同一 SHA-256 恢复。后续连续采样均在此正常保护状态下进行，
通过 Terminal 的既有权限读取，没有改动 TCC 数据库或新增完全磁盘访问权限。

每约 30 秒保存一次 DB/WAL 快照，按稳定的联系人 server ID 比较源定位时间与坐标，并记录实际前台应用
bundle ID 和 Find My 进程是否仍存在，避免把缓存 mtime 或采集时间变化误认为新定位。
私有原始快照在 `localstorage-samples/`，每次坐标观察追加到 `contacts-snapshots.jsonl`；
验证摘要只包含联系人 ID 的散列，不包含姓名、联系方式或经纬度。

### 实测结果

正常保护状态下，在北京时间 15:39:06—15:49:37 取得 19 次快照，所有 SQLite 一致性检查通过。
每次暂停定位代理的最长时间为 28.014 毫秒。持续只有 1 位联系人返回可用坐标，其余 4 条没有可用位置。

| Find My 状态 | 观察窗口（北京时间） | 样本数 | 窗口内源时间推进 | 窗口内坐标变化 |
| --- | --- | --- | --- | --- |
| 前台，实际前台为 `com.apple.findmy` | 15:39:06—15:42:08 | 7 | 3 次 | 3 次 |
| 后台，Photos 在前台 | 15:43:07—15:46:10 | 7 | 1 次 | 1 次 |
| 主应用退出，Photos 在前台 | 15:47:35—15:49:37 | 5 | 1 次 | 1 次 |

全部正常保护样本串起来比较，同一联系人的源定位时间及经纬度各推进/变化了 7 次，无时间倒退；
比表内合计多出的两次发生在测试阶段交接之间。源时间由北京时间 15:38:26.592938 推进到
15:47:43.395540。关闭主应用阶段的全部 5 个样本均确认 Find My 主进程不存在；
新的源时间 15:47:43 晚于该阶段开始，证明这段窗口内定位代理仍取得了新位置，而非只读到关闭前缓存。

本机当前已登录图形会话中，联系人位置可以周期性解密读取，且本次前台、后台、主应用退出后三种窗口
都取得了新定位。关闭主应用的观察窗口只有约 2 分钟，结论不外推为全天稳定性保证，也不把 30 秒采样间隔
当作定位提供端的更新频率。

### 留存文件与结束状态

下列文件均在 Hackintosh 的 `~/.local/state/findmy-cache-validation/2026-10-21/`，敏感文件权限为 `0600`：

- `LocalStorage.decrypted.sqlite`：最后一次完整快照的明文 SQLite，106,496 字节；导出后再次执行完整 `integrity_check`，结果为 `ok`。
- `contacts-latest.json`：最后一次联系人坐标快照。
- `contacts-snapshots.jsonl`：本次全部有效观察，含源定位时间与采集时间。
- `contacts-track.jsonl`：按联系人 ID 与源定位时间去重后的 9 个定位点，包含初次提取阶段的 1 个点。
- `localstorage-final-summary.json`：阶段计数、保护状态与更新次数摘要。
- `keys/LocalStorage.key`：32 字节独立密钥，与数据文件分开保存。

验证结束后确认 SIP 与 authenticated root 仍为 enabled，启动参数仍为 `vsmcgen=2`，
定位代理正常运行且没有停在 `T` 状态，Photos 进程与数据卷正常；Find My 已重新打开到后台。
没有保留调试会话或常驻采集任务，el2 宿主没有重启。

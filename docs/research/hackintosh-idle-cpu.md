# Hackintosh 持续 CPU 占用：资料与现场核对

调查日期：2026-09-26。对象为 `el2` 上的 Incus `hackintosh`，macOS
Tahoe 26.6.2（25G83）、QEMU 10.2.4、4 vCPU、VirtualSMC 1.3.7。
最初调查只研究和采样；随后按用户要求完成两项修复，验证记录见文末。

## 结论与优先级

值得处理的是两条独立的异常路径：蓝牙控制器初始化失败反复重启，以及
QEMU SMC 不支持键枚举。照片转换另有真实工作负载，不应合并算作空闲开销。

| 方向 | 现场与资料匹配程度 | 建议 |
| --- | --- | --- |
| 蓝牙 dummy HCI | 高：无直通硬件、地址 NULL、每约 32 秒超时、持续 XPC 重连 | 核对 Tahoe 后评估 OpenCore 禁用 HCI 初始化补丁 |
| SMC 键枚举 | 高：现场内核错误、设备树、相同 QEMU 二进制测试均吻合 | 优先验证 VirtualSMC 接管 AppleSMC 的方案 |
| 照片转换/解码 | 已确认在执行 HEIF→JPEG 和 HEVC 软件解码，尚未证明任务卡住 | 保留图库功能，观察同步进度及任务是否收敛 |
| VNC、动画、Spotlight | 当前采样占用很低，动画等已有配置 | 无证据支持继续削减这些功能 |

**修正此前判断：** `PerfPowerServices` 收到蓝牙连接中断日志，不足以证明它的
全部 CPU 消耗来自蓝牙。SMC 枚举是另一个有直接现场证据的问题。最初调查
未获得该 root 进程的调用栈，也尚未做修复前后对照；后续分阶段验证见文末。

## 现场证据

以下为本次 SSH、宿主 `/proc`、设备树及日志采样结果，100% 表示一个逻辑核：

- 宿主 QEMU 约 3.7 核，主要在四条 vCPU 线程；SPICE Worker 约 0.2%。
- `WirelessRadioManagerd` 104%～132%，约 11 天累计 175 小时 CPU。
- `bluetoothd` 占用随重启波动，`launchctl print system/com.apple.bluetoothd`
  显示 `runs = 30436`、`last exit code = 1`。
- 蓝牙日志重复 `BlueTool timed out running boot script!`，相邻失败间隔约 32 秒。
- `PerfPowerServices` 33%～67%；照片转换、解码、图库服务合计约 90%～140%。
- 照片调用栈包含 `IIORecodeHEIF_to_JPEG` 和 `VCPHEVC`；图库日志有下载完成且
  `error: (null)`。这证明有成功处理，但不证明整个图库已同步完毕。
- `csrutil status` 与 `csrutil authenticated-root status` 均为 enabled。
- `kmutil showloaded` 确认 VirtualSMC 1.3.7 已加载，但 `ioreg -p IOService`
  中 AppleSMC 的父节点是 `SMC <class IOACPIPlatformDevice>`，不是 VirtualSMC。
- 内核持续报：

  ```text
  AppleSMCFamily::handleSMCResult ERROR in smcGetKeyFromIndexPMIO.
  1468 kSMCBadCommand(0x82)
  ```

照片采样最初写入 guest 的 `/tmp/hackintosh-photos-sample.txt` 和
`/tmp/hackintosh-videodecode-sample.txt`，随后在重启时被清理。系统进程的 `sample` 因 SSH 会话没有
免密码 sudo 而未成功；没有通过其他方式绕过这一限制。

## 1. 蓝牙：关闭开关未必阻止虚假控制器初始化

Acidanthera 维护者 vit9696 在 Sequoia 的调查中发现：即使关闭蓝牙，
`IOBluetoothFamily` 仍启动 dummy HCI，触发持续 XPC 重连。他给出的
OpenCore `Kernel -> Patch` 将 `IOBluetoothHCIController::start` 入口改为
直接返回，阻止这条初始化路径。应用后相关日志停止，但独立的功耗初始化
问题仍存在。[维护者原始记录与补丁](https://github.com/acidanthera/bugtracker/issues/2480#issuecomment-2779184680)

这与本机症状高度吻合，但原始验证针对 Sequoia，不能当作 Tahoe 的现成修复。
若实施，应核对目标内核中的符号和代码、限定内核版本、备份 EFI 并验证回滚，
然后观察蓝牙重启次数、无线电服务 CPU 和宿主 QEMU 总占用。该方案会禁用
蓝牙功能；本机的控制台输入走虚拟 USB，网络走 VMXNET3。

不建议把 `ExternalDongleFailed` 当作 CPU 开关：BrcmPatchRAM 的正式说明讨论
的是 NVRAM `bluetoothExternalDongleFailed` 与 `bluetoothInternalControllerInfo`，
用于真实蓝牙设备的兼容性。没有找到将 `defaults write ... ExternalDongleFailed`
用于本问题的第一手依据。[BrcmPatchRAM README](https://github.com/acidanthera/BrcmPatchRAM/blob/65389020769837e92e9fb939bac34bd9a3e25bb2/README.md#bluetoolfixupkext)

## 2. SMC：让 VirtualSMC 真正接管服务

上游问题报告将 `PerfPowerServices` 高负载定位到
`PLSMCMetricsAgent getAllKeys -> SMCGetKeyFromIndex`。
[Acidanthera #2480](https://github.com/acidanthera/bugtracker/issues/2480)

QEMU 10.2.4 的 `applesmc_io_cmd_write` 只处理读取命令 `0x10`；虽然定义了
键枚举命令 `0x12`，收到它仍返回 `BAD_CMD=0x82`。
[对应版本源码](https://github.com/qemu/qemu/blob/3e0bcba1ca7d6607ca49a988d165f052a3a53323/hw/misc/applesmc.c#L119-L146)

本次对生产使用的同一个 Nix store QEMU 二进制另起了一个暂停的 TCG 进程，
无磁盘、无生产 VM 连接、使用虚构 OSK，通过 qtest 得到：

| 请求 | 状态端口 0x304 | 错误端口 0x31e |
| --- | --- | --- |
| 读取命令 0x10 | 0x0c，正常确认 | 0x00 |
| 枚举命令 0x12 | 0x08，未确认 | 0x82，不支持的命令 |

独立进程测试后已退出。结合 guest 的相同错误和设备树，可以确认本机存在这项
模拟器功能缺失；具体消除多少 CPU 仍需 guest 对照验证。

`icex/macos-raphael-igpu` 项目记录了一个修复：保留 QEMU SMC 供启动使用，
通过精确 ACPI `_STA=0` 补丁使 macOS 不绑定它，改由 VirtualSMC 提供运行期服务。
其 QEMU 10.1.2、Sequoia、VirtualSMC 1.3.7 组合在两次 guest 启动中测得
`PerfPowerServices` 为 0.0%。这是项目作者的复现记录，尚非本机 Tahoe 验收结果。
[方案及验证边界](https://github.com/icex/macos-raphael-igpu/blob/861ba5ea4d1e8b8a8781914adff3eb65629cc93c/docs/stock-qemu-smc.md)

本机已经加载 VirtualSMC，因此单纯再安装或升级 kext 不足以解决绑定问题。
建议先获取本机 DSDT，核对 SMC 节点并准备独立 EFI 候选配置；保留现有 QEMU
SMC 启动设备。验收需要确认 AppleSMC 的父节点变为 VirtualSMC、枚举正常结束、
内核错误停止，并比较 CPU、Photos 同步和重启行为。不要直接复制其他机器的
DSDT 字节补丁。

另一个候选是给 QEMU 补齐枚举命令及越界结果 `0xb8`。项目提供了补丁和复现
过程，但会增加宿主定制 QEMU 的维护成本，暂作为备选。
[QEMU 修复实验](https://github.com/icex/macos-raphael-igpu/blob/861ba5ea4d1e8b8a8781914adff3eb65629cc93c/findings/research/perfpower-smc-enumeration-20260916.md)

## 3. 避免用破坏功能的方式压低数字

- 不把关闭 SIP 作为优化前提。本机 SIP 开启；Apple 说明 root 也受其限制，
  因而不能承诺 `sudo launchctl` 就能停用受保护系统服务。
  [Apple SIP 说明](https://support.apple.com/en-us/102149)
- 不永久关闭 `photolibraryd`、转换或解码服务。Apple 提供图库同步状态与
  暂停/恢复入口，可用于观察同步负载；暂停同步不保证本地已排队转换立即停止。
  [图库状态](https://support.apple.com/en-ie/119921)
- 不通过关闭再开启 iCloud Photos 排障；Apple 提醒这会重新启动同步过程。
  [Apple 同步排障](https://support.apple.com/zh-cn/101559)
- 不整套应用 OSX-PROXMOX 的优化清单。其脚本还包含强制软件渲染、全盘关闭
  Spotlight、关闭更新检查及跳过镜像校验；本机测到的主要负载不支持这些改动。
  [脚本原文](https://github.com/luchina-gabriel/OSX-PROXMOX/blob/209f6df3a4e36a9a2853975fd962fbc34d562249/Patches/macOS%20VM%20-%20GPU%20Optimization/Tweaks%20macOS%20-%20for%20VM.txt)

建议实施时一次处理一条异常路径，记录相同观察窗口内的宿主 CPU 增量、guest
各进程 CPU、蓝牙重启次数及 SMC 错误。蓝牙相关补丁对这台无蓝牙设备的
iCloud Photos 主机是否无副作用，仍应通过实际下载、转换和图库进度验证。
当前没有证据承诺修复后会降至某个固定核心数。

## 实施记录（2026-09-26）

用户要求实施前两个方案，同时保留照片备份和处理功能。
私有 EFI、身份信息及完整备份保存在宿主机
`/var/lib/incus-macos/cpu-fix-20260926/`（root-only）。系统盘和照片自定义卷
各自有 `pre-cpu-fix-20260926` 快照。所有固件写入均在 VM 停止时完成，
只更新系统盘 EFI 分区的 `EFI/OC/config.plist`。

### 蓝牙候选的本机验证

从 guest 的 `BootKernelExtensions.kc` 定位到目标符号：

- 文件 SHA-256：`c80161fa3065883753fc285339281361a8469cbb6fb27653c88e2a22eb4807a4`。
- 符号虚拟地址 `0xffffff8002511e72`，文件偏移 `0x2411e72`。
- 入口指纹 `554889e541574156534881ec88000000`。
- 替换为 `31c0c39041574156534881ec88000000`，即入口明确返回 false。
  相比原始单字节 `ret`，这确保返回寄存器不保留调用方的值。
- `Base=__ZN24IOBluetoothHCIController5startEP9IOService`，
  `Identifier=com.apple.iokit.IOBluetoothFamily`，`Arch=x86_64`，
  `Count=1`、`Limit=16`、`MinKernel=MaxKernel=25.6.0`，掩码留空。
- 复用并启用原配置中已存在但禁用的 Bluetooth patch 条目。

第一阶段启动后，HCI 控制器不再出现在设备树；观察超过四分钟后，
`bluetoothd` 仍为 `runs=1`、从未退出；它与 `WirelessRadioManagerd` 均接近
0% CPU。SMC 原生探针仍报告 `IOACPIPlatformDevice`、键数量 0、错误 `0x82`，
随后 `PerfPowerServices` 再次达到约一核，证实两条路径可分别验证。

### SMC 配置与验证

读取 guest RAM 中校验和正确的 QEMU DSDT，长度 8690，SHA-256 为
`27e924f8e6b5330d6380966e2c577a62cb8a282629dbccc7ef55e9b0e0e0dc89`。
SMC 匹配字节仅出现一次，偏移 8430。补丁参数：

- `Find=534d435f085f4849440c06100001085f5354410a0b`，
  `Replace=534d435f085f4849440c06100001085f5354410a00`。
- `TableSignature=DSDT`、`OemTableId=BXPC    `（四个尾随空格）、
  `TableLength=8690`、`Count=1`；Base 和掩码留空，BaseSkip/Skip/Limit 为 0。
- 已启用的 VirtualSMC 1.3.7 保持不变；添加 `vsmcgen=2`。
  QEMU `isa-applesmc`、系统身份与 Apple Account 内核补丁保持不变。

两份候选均通过 OpenCore 1.0.7 `ocvalidate`，照片服务配置没有修改。
最终候选配置 SHA-256：
`418652df3f1d8bce143a1dc83e84916946bbd847f8cc0c6c30aba8dc7124cf9f`。

第二阶段已将该配置写入系统 ESP 并正常启动。运行期设备树确认
`SMC <class VirtualSMC> -> AppleSMC`，`kern.bootargs=vsmcgen=2`。
原生 IOKit 探针枚举出 69 个唯一键，索引 69 正确返回 `0xb8`；没有读取键值。
启动数分钟后重复探针结果一致，`PerfPowerServices` 为 0.0%，
`bluetoothd` 仍为 `runs=1` 且从未退出，无线电管理服务也为 0.0%。
新的采样窗口内没有 `smcGetKeyFromIndexPMIO` 错误。
SIP、Authenticated Root 均保持启用，`kern.hv_vmm_present=0`。

宿主通过 `/proc/<QEMU PID>/stat` 的 CPU 时间增量测量，100%=一核：

| 窗口 | 时长 | 宿主 QEMU CPU |
| --- | --- | --- |
| 修复前，原工作负载 | 30 秒 | 370.73% |
| 两项修复后，较轻负载 | 45 秒 | 45.31% |
| 两项修复后，Photos 窗口关闭、后台工作继续 | 45 秒 | 186.47% |

照片任务量不同，不能将总 CPU 差值全归于补丁。独立证据是三个异常服务均
降至接近零、蓝牙重启停止、SMC 枚举正常。Photos 的实际转换和同步仍会消耗 CPU。

### 照片验证中的观察

重启前图库有 53,076 项；为 12 个既有原始文件记录了内容校验和。
启动时发现已有约 56 GiB 的 `Photos.sqlite-wal`，图库进程在
`walIndexReadHdr` 中重建索引，随后进入其迁移准备状态。
这个过程会延迟图库打开，不能将这段 CPU/IO 消耗当作稳定空闲基准。
未手动删除日志、写数据库或执行 checkpoint；让 Photos 完成自己的恢复流程。
[SQLite WAL 生命周期与恢复说明](https://sqlite.org/wal.html#the_wal_file)

恢复过程中短暂保持一个只读 SQLite 连接，查询完成后没有保持读事务，随后
关闭连接。约 15:38，Photos 自身的 `_walCheckpointWithMode:` 完成，WAL 缩至
约 4.5 MiB，下载成功记录恢复；第二阶段启动后未重复此前的长时间日志恢复。

最终验收（15:47）：

- 资产表仍为 53,076 项。
- 内部资源表 `ZLOCALAVAILABILITY=1` 从 153,751 增至 153,903，增加 152；
  `-1` 从 226,820 降至 226,668。这里是资源记录数，不是新增照片数。
- 新启动后的日志持续出现 `downloadDidFinishForResourceTransferTask` 且
  `error: (null)`。期间也见过个别批次请求错误，故不宣称整个图库已同步完毕。
- 用系统 `sips` 将一张既有 HEIC 成功转为 5712×4284 JPEG，仅写临时输出，
  没有替换原图；验证后删除了该临时 JPEG。
- 最初 `/tmp` 中的校验记录在 macOS 重启后被清理，最终改为直接比较修复前
  照片卷快照与当前原始文件。宿主只读挂载快照，12 个文件共 63,876,333 字节
  的 SHA-256 全部一致；随后卸载并恢复 ZFS `snapdev=hidden` 的默认状态。
- Photos 窗口关闭后，其后台图库、下载和解码服务继续运行。未更改 iCloud
  设置、暂停同步或禁用照片分析服务。

初次离线写入遇到 Incus 隐藏停止状态块设备的问题，写入未发生；一次未改配置
的启动仍复现蓝牙超时。后续按 Incus 的 ZFS 卷激活方式处理，停止状态临时设置
`volmode=dev`，写入并读回验证配置哈希后恢复 `volmode=none` 再启动。
所有停止均走 macOS 正常关机流程，没有重启宿主机或强制断电。

完整回滚材料在私有目录，原始恢复镜像未覆盖。回滚 CPU 补丁时只需恢复 EFI
配置；不要为了撤销固件补丁而回滚已继续接收照片的图库卷。

## 再次高 CPU 的调查（2026-09-29）

本次主要原因是 OSXPhotos 增量导出的目录预取查询退化为全表扫描。
没有发现此前 SMC 或蓝牙修复失效的证据；不能将此次现象归因于 Incus 升级。

### 运行期证据

- Incus 7.5.1、QEMU 10.2.4；guest 为 macOS 26.6.2 / Darwin 25.6.0，
  4 vCPU、8 GiB RAM。
- 导出 worker（OSXPhotos 0.77.1 / Python 3.13，PID 1942）自 16:00 启动，
  连续采样约占一核。guest 总 CPU 约 29–34%，宿主 QEMU 的 10 秒增量约
  129%（100% 为一核），主要来自 vCPU 线程。
- `bluetoothd` 仍为 `runs=1`、从未退出；它与 `PerfPowerServices` 最后一次
  进程采样均为 0.0%。设备树仍为 `VirtualSMC -> AppleSMC`。
- 只读检查 QEMU RAM 中当前 DSDT：长度 8690，与 9 月 26 日原表仅有预期的
  SMC `_STA` 和校验和两个字节不同。当前 SHA-256：
  `22c45a5a4bee9e188e2f0cf65aa4da2f4515c9117a186119857c7c102043a779`。
  三分钟日志窗口未发现实际 SMC 枚举错误或 BlueTool 超时。
- 导出报告持续增长，19:02 已达 175,861,180 字节；任务在缓慢推进，并非死锁。

### 热点和查询计划

对 worker 用 py-spy 采样 20 秒，共 979 个样本；69.3% 落在
`ExportDB.prefetch_directory_records()` 执行目录查询的位置。macOS 原生
`sample` 同时显示 `sqlite3_step -> sqlite3VdbeExec -> sqlite3BtreeNext`
为主要热点。完整照片 JSON 的 `cloud_metadata` 路径仅占约 2.7%。

当前导出配置使用 `directory="{uuid}"`、`update=True`，本轮处理 51,437 张
照片。OSXPhotos 对每个新目录执行以下查询，然后缓存该目录的结果：

```sql
SELECT filepath_normalized, uuid, digest, exifdata, export_options,
       dest_mode, dest_size, dest_mtime, error, date_modified
FROM export_data
WHERE filepath_normalized LIKE ? AND filepath_normalized NOT LIKE ?;
-- 参数：uuid/%、uuid/%/%
```

以 `mode=ro`、`query_only=ON` 打开导出数据库验证：`export_data` 有 138,635
行，路径索引使用 BINARY 排序规则，默认 LIKE 不区分 ASCII 大小写。
实际计划为 **`SCAN export_data`**。因此每个 UUID 目录仅有少量文件，却要
遍历整张表；目录缓存无法消除下一个 UUID 的全表扫描。
[SQLite 对 LIKE/GLOB 索引优化的条件](https://www.sqlite.org/optoverview.html#the_like_optimization)
解释了这里默认 LIKE 与 BINARY 索引不匹配的原因。

仅为验证索引效果，对三个真实 UUID 目录使用 GLOB 执行只读对照查询：

| 目录文件数 | 原 LIKE 查询 | GLOB 对照查询 |
| --- | --- | --- |
| 3 | 220.393 ms | 0.492 ms |
| 3 | 171.104 ms | 0.253 ms |
| 2 | 186.782 ms | 0.309 ms |

每组返回的文件集合一致；对照计划为
`SEARCH export_data USING INDEX idx_export_data_filepath_normalized
(filepath_normalized>? AND filepath_normalized<?)`。
这是单条查询的耗时对照，不能当作完整备份的提速比例。

### 引入时间与修复方向

上游提交
[`a7f2f200`（2026-01-23，SMB 性能优化）](https://github.com/RhetTbull/osxphotos/commit/a7f2f200e1878c06049f904667739badeca1cdb5)
引入目录预取及 update 路径的调用；其父版本按文件路径做等值查询。
该优化在当前每张照片独立目录的布局下产生性能退化。
本地备份功能于 `bc1934c`（2026-09-27）引入，早于本次 Incus 升级。
已检查的上游 main `e6c8a9dcb9e6a0bc91eb9bf6951ec161bd2ab683`
（包含 0.77.2）仍保留该查询，单纯升级到这个版本不能消除问题。

建议修正 OSXPhotos 的目录查询，使其利用现有路径索引，并保留直接子文件
过滤。通用修复需要正确处理目录中的通配符；本次 GLOB 对照仅使用已确认
不含通配符的 UUID，不能直接推广到任意目录。无需修改 Apple Photos 数据库、
改变归档布局或删除完整元数据。

本次未修改生产 SQL、数据库索引、EFI 或 iCloud 设置，也未重启 VM。
调查记录了原因与修复方向，尚未实施查询修复或进行完整导出前后对照。

### 修复方案评估

后续只读实测：用现有 BINARY 索引的路径范围查询
（`path >= directory || '/' AND path < directory || '0'`，再筛选直接子文件）
在三个 UUID 目录返回相同文件集合，耗时 0.092–1.213 ms；同期原查询为
107.150–143.594 ms。路径归一化本身已转小写；范围查询无需解释目录中的
LIKE/GLOB 通配符。通用实现仍需覆盖根目录、Unicode 和直接子文件边界。

另将实际路径列复制到独立的内存数据库，仅用于验证索引选择：BINARY 索引
对应 `SCAN`，添加 `COLLATE NOCASE` 索引后，未修改的 LIKE 查询使用索引范围
查找。这不是生产库全字段查询的耗时测试，也未给生产库添加索引。

| 方案 | 优点 | 代价与限制 |
| --- | --- | --- |
| 上游修正范围查询 | 利用现有索引，不迁移文件、不增加索引 | 合入前使用需要本地补丁；合入后可以移除 |
| 导出数据库增加 NOCASE 路径索引 | 不修改 OSXPhotos 代码、不迁移文件 | 增加索引存储及写入开销；数据库重建或上游迁移后需保证索引存在 |
| 禁用目录预取 | 退回已有按文件等值查询，不迁移文件 | 当前没有公开开关，需补丁或 monkey patch；会增加查询次数 |
| 年月目录，UUID 放入文件名 | 仅用公开配置，显著减少目录扫描次数 | 仍是每目录全表扫描；修改日期可改变路径；需要迁移现有归档 |
| UUID 前两位分桶，完整 UUID 放入文件名 | 最多 256 个目录，路径不依赖可编辑日期 | 仍有全表扫描；增加布局约定；需要迁移现有归档 |
| 默认单目录，UUID 放入文件名 | 目录预取只扫描一次，配置简单 | 单目录包含十几万文件；需要迁移，人工浏览不便 |

分桶后如果仍保留每张照片的 UUID 子目录，预取的实际父目录数量不变，不能
解决本次问题。默认原始文件名已由上游提供；布局调整时需要 UUID 文件名是
为了明确避免跨照片重名，而不是修正默认文件名行为。

宿主归档 rsync 刻意不使用 `--delete`。直接更换布局会保留旧路径并复制新路径，
且可能重新导出媒体；不能假定改两项参数即可无成本迁移。迁移必须保留已经
从 iCloud 删除、只剩归档的资产，也不能用全量 `--delete` 清理旧目录。

用户明确不将迁移复杂性作为决策因素，优先减少技术债。因此推荐年月目录，
将 UUID 放入文件名：只使用上游公开模板，不引入 SQL 补丁、额外索引或私有
方法覆盖。减少实际父目录数可以大幅减少扫描次数，但没有修复上游 SQL，
实际完整导出耗时仍需部署后验证。

已检查默认文件名冲突处理：上游会增加 `(1)` 等后缀，并在增量更新时通过
导出数据库寻找同一 UUID 已占用的文件名。无需自己实现冲突处理。不过宿主
归档永久保留已经从图库删除的照片，而 staging 会清理删除项；文件名仍加入
UUID，可使跨导出数据库重建的归档身份不依赖自动编号分配。它只需公开模板，
无需自定义代码。仅追求默认参数最少时可以选择单目录，但人工浏览十几万个
文件不方便，且原始文件名加自动编号不具备上述独立的身份稳定性。

NOCASE 索引虽不修改上游代码，仍需维护上游未管理的数据库结构；禁用预取
仍需私有方法覆盖，均不符合这次优先减少技术债的目标。上游正式修复发布后
可正常升级，无需为了等待该修复保留本地补丁。
不建议使用 SQLite 已弃用的
[`case_sensitive_like` PRAGMA](https://www.sqlite.org/pragma.html#pragma_case_sensitive_like)，
或关闭增量更新、减少归档内容来降低此热点。

### 年月布局实施（2026-09-29）

用户选择年月目录与 UUID 文件名。生产代码仅修改两项公开模板：
`directory="{created.year}/{created.mm}"`、
`filename_template="{original_name}_{uuid}"`，未增加 SQL 补丁或索引。
`just fmt` 通过；在 Hackintosh 的 Terminal 授权会话中执行 `just darwin`
成功，系统闭包仍为 2.34 GiB，仅包装与配置变化，VM 无需重启。

独立目录样本导出覆盖普通照片、视频、Live Photo 及编辑后的 Live Photo，
共四个资产、八个媒体文件。八个文件与旧 staging 的 SHA-256 全部相同；
第二轮八个媒体全部跳过，missing/error 均为零。选取的连拍样本未进入本次
导出集合，因此不将其计为已验证样本。

归档迁移前创建 `pool0/footage2@pre-month-layout-20260929` 快照，并临时阻止
定时服务启动。根据已归档照片元数据，将 51,437 个 UUID 目录中的 193,771
个文件重命名至 183 个月份目录，合计 1,086,602,789,004 字节；逐文件确认
inode 与大小不变，没有重写媒体内容。迁移依据归档而非当前图库筛选，保留
已经从图库删除的归档资产。旧目录仅在为空时删除。
迁移清单保存在宿主 root-only 的
`/var/lib/icloud-photos-backup/layout-migration-20260929/plan.json`。

检查归档导出数据库时发现旧 WAL/SHM 残留：忽略旁文件读取主数据库的
`quick_check` 为 `ok`，guest 当前导出数据库检查也为 `ok`。
将归档的旧旁文件移至上述私有目录保存，再由正常导出后 rsync 更新元数据。
这未修改 live Photos 数据库或导出数据库 schema。

20:18 恢复服务并启动新布局的完整导出。旧布局上一轮在 19:05 完成导出阶段，
耗时 3:03:25，已有一个 `IMG_9423.mov` 资源缺失；新一轮需分别验证布局性能
及该既有缺失状态。

新布局首轮运行中再次采样 20 秒、979 个样本，目录预取调用栈占比从旧布局的
69.3% 降至 3.1%。当前主要开销转为完整元数据生成及正常导出操作，其中
`cloud_metadata` 占 13.1%。此时 APFS 可用空间仍约 993 GiB。
该结果证明目录预取热点已明显下降，但首轮正在重新导出新路径，不能将采样
占比直接换算为完整增量备份的提速比例；完整导出耗时与最终缺失状态待该轮
结束后确认。归档服务和原定时调度均已恢复，独立样本目录已清理。

### 临时快照清理（2026-09-29）

用户要求清理快照以释放空间。删除本轮归档的
`pre-month-layout-20260929`（约 1.09 GiB），并通过 Incus 删除系统盘和照片卷
的 `pre-cpu-fix-20260926`（分别约 5.17 GiB、57.2 GiB）。这些名称在上文中
保留为历史实施记录，已不能作为回滚目标。更早的 accepted-baseline、OpenCore
身份和 Apple ID 补丁前快照保留；EFI 私有备份与归档迁移清单也保留。

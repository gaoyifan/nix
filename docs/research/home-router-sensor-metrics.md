# Home Router 传感器监控扩展调研

日期：2026-08-28

状态：仓库源码、上游一手文档和五台实际 Home Router 节点均已核验；第一批 Dashboard、
per-WAN scrape 收窄与 `el2` smartctl exporter 已于 2026-08-28 实施，其余候选仍是调研建议。

## 结论

第一批实现没有新增 exporter，而是给 Home Router Overview 增加温度面板。当前
`node_exporter 1.11.1` 已经在五台节点上默认采集 `hwmon`、`thermal_zone`、
`cpu` 和 `cpufreq`；Home Router Dashboard 已开始消费这些指标。模块当前每 15 秒抓取 node
exporter，并保留 90 天数据（[`monitoring.nix`](../../nixos/optional/home-router/monitoring.nix#L168-L217)），
并由 [`overview.nix`](../../nixos/optional/home-router/overview.nix) 定义系统、网络和温度面板。

建议按下面顺序扩展：

1. **P0，纯 dashboard：** CPU/SoC 当前最高温、筛选后的全部温度历史、cooling/throttle
   状态和硬件临界温度余量已经实现。额外 WAN scrape 也已限制到 `netclass`/`netdev`，
   后续可可靠增加 sticky alarm 面板。
2. **P0，纯 dashboard：** `el2` 的整机功率与 EDAC 错误；它们已经在当前 scrape 中。
3. **P1，主机特定 exporter：** `el2` 已启用 `smartctl_exporter`，覆盖 12 块 SAS HDD、
   3 块 SATA SSD 和 2 块 NVMe 的温度与 SMART 健康信息。
4. **P1，主机特定 collector：** 只在 `somo-minisforum` 启用 node exporter 的 `wifi`
   collector，增加信号、速率、重试和失败指标。
5. **P2，服务器特定 exporter：** 给 `el2` 接 IPMI，尝试补齐 BMC 的进风/出风、DIMM、
   风扇、PSU 等传感器；具体 sensor 清单尚未读取，权限和凭据也使它不属于零成本改动。

不要先做一个自定义温度采集脚本。Linux 已经用标准 hwmon ABI 统一导出温度、风扇、
电压、电流、功率、阈值、alarm 和 fault，node exporter 也已默认读取它们
（[Linux hwmon ABI](https://docs.kernel.org/hwmon/sysfs-interface.html)、
[node exporter 1.11.1 hwmon collector](https://github.com/prometheus/node_exporter/blob/v1.11.1/collector/hwmon_linux.go#L45-L91)）。

## 已验证的采集链路

### 仓库配置

- `networking.homeRouter.monitoring` 只有开关和 WAN 列表，没有传感器开关
  （[`options.nix`](../../nixos/optional/home-router/options.nix#L327-L334)）。
- Prometheus 的 `node` job 抓取本机 node exporter；节点服务没有关闭任何默认 collector，
  只额外设置了 WAN textfile 目录
  （[`monitoring.nix`](../../nixos/optional/home-router/monitoring.nix#L168-L217)）。
- 锁定的 Nixpkgs node exporter 模块在 `enabledCollectors = []` 时不追加 collector 参数，
  因而使用上游默认集合
  （[锁定 Nixpkgs `node.nix`](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/nixos/modules/services/monitoring/prometheus/exporters/node.nix#L23-L68)）。
- node exporter 1.11.1 官方列表明确把 `hwmon`、`thermal_zone`、`cpu`、`cpufreq`、
  `edac`、`nvme`、`rapl`、`powersupplyclass` 和 `watchdog` 列为默认 collector；`wifi`
  和 `ethtool` 默认关闭
  （[collector 列表](https://github.com/prometheus/node_exporter/blob/v1.11.1/README.md#enabled-by-default)）。

### 当前 dashboard 已经展示什么

| Dashboard | 已有指标 | 源码 |
|---|---|---|
| Home Router Overview / Summary | uptime、CPU、内存、根文件系统、conntrack、load、CPU/SoC 温度、critical headroom | [`overview.nix`](../../nixos/optional/home-router/overview.nix) |
| Home Router Overview / Interface health | carrier、link speed、所选时间范围内的 carrier changes | [`overview.nix`](../../nixos/optional/home-router/overview.nix#L254-L376) |
| Home Router Overview / Trends | interface throughput、packet rate、errors/drops、CPU/内存历史、硬件温度、thermal mitigation | [`overview.nix`](../../nixos/optional/home-router/overview.nix) |
| Public Egress / Status | ping exporter 是否可用、物理 WAN carrier、当前 packet loss 状态 | [`public-egress.nix`](../../nixos/optional/home-router/public-egress.nix#L1-L177) |
| Public Egress / Trends | nftables 分 WAN throughput、loss、mean/best/worst/stddev RTT、WAN errors/drops | [`public-egress.nix`](../../nixos/optional/home-router/public-egress.nix#L178-L360) |

分 WAN byte counter 由模块每 15 秒读取 nftables named counter 后写入现有 textfile collector
（[`monitoring.nix`](../../nixos/optional/home-router/monitoring.nix#L84-L120)、
[`monitoring.nix`](../../nixos/optional/home-router/monitoring.nix#L254-L275)）；每个 WAN 的 ping
exporter 和单独 relabel 后的 link/error scrape 也都在同一模块内
（[`monitoring.nix`](../../nixos/optional/home-router/monitoring.nix#L173-L210)、
[`monitoring.nix`](../../nixos/optional/home-router/monitoring.nix#L219-L252)）。因此本轮建议是在
已有“网络 + 通用系统资源”基础上补硬件健康，而不是重做现有监控。

### 2026-08-28 实机盘点

以下是通过各机 `/sys/class/hwmon`、`/sys/class/thermal` 和
`http://127.0.0.1:9100/metrics` 做的只读核验。这里的温度值会随负载变化；有意义的是传感器
的存在、标签和指标结构。

| 节点 | 已验证硬件 | 当前已经导出的温度 | 展示时的处理 |
|---|---|---|---|
| `cjia` | 4 GiB NanoPi R4S / RK3399；主机导入共用 R4S 模块（[`default.nix`](../../nixos/hosts/cjia/default.nix#L1-L8)、[`迁移记录`](../archive/cjia-nixos-migration.md#L1-L12)） | `cpu-thermal`、`gpu-thermal`；`node_hwmon_temp_celsius` 原始 4 条 | 同一 thermal zone 同时成为 `temp0`/`temp1`，排除 `sensor="temp0"` 后保留 2 条；另有 3 个 cooling device 和 6 个 CPU frequency 序列 |
| `somo-nanopi-r4s` | NanoPi R4S / RK3399（[`default.nix`](../../nixos/hosts/somo-nanopi-r4s/default.nix#L1-L7)） | 同样为 CPU/GPU thermal；原始 4 条 | 同样排除 `temp0` 后为 2 条；另有 3 个 cooling device 和 6 个 CPU frequency 序列 |
| `somo-minisforum` | Minisforum MS-A2，AMD Ryzen 9 9955HX；仓库确认是 AMD 裸机和 MT7921 AP（[`hardware-configuration.nix`](../../nixos/hosts/somo-minisforum/hardware-configuration.nix#L14-L35)、[`wifi-ap.nix`](../../nixos/hosts/somo-minisforum/wifi-ap.nix#L1-L55)） | 10 条：`k10temp` 的 Tctl/Tccd1/Tccd2、2 个 `spd5118` DIMM、NVMe Composite/Sensor 1/Sensor 2、`mt7921_phy0`、`amdgpu` edge | 全部可直接使用；没有 `fan*_input` |
| `el` | VMware7,1 guest；仓库显式启用 VMware guest（[`default.nix`](../../nixos/hosts/el/default.nix#L10-L18)） | 0 条；只有虚拟 AC adapter 的 `node_power_supply_online` | guest 看不到 ESXi 宿主物理温度；应显示 N/A，而不是报采集失败 |
| `el2` | Inspur NF5280M5，双 Xeon Gold 5115；仓库显示物理 i40e/igb/NVMe/SATA 平台（[`hardware-configuration.nix`](../../nixos/hosts/el2/hardware-configuration.nix#L1-L19)） | 原始 31 条：双 package 与 per-core `coretemp`、PCH Lewisburg、2 个 NVMe 各 3 条、I350 NIC | 过滤 `temp0` 以及 20 条 `label=~"Core .*"` 后为 10 条更适合总览；仍保留双 package、PCH、NIC 和 6 条 NVMe |

FriendlyElec 的官方规格也确认 R4S 使用 RK3399，并有 CPU/GPU、可选风扇接口和 0–80°C
工作温度范围（[NanoPi R4S 官方 Wiki](https://wiki.friendlyelec.com/wiki/index.php/NanoPi_R4S#Hardware_Spec)）。
两台当前主线 NixOS 实例只暴露 CPU/GPU 温区和 cpufreq/GPU cooling device，并未暴露
风扇转速或 PWM。

`el2` 还已经导出：

- `node_hwmon_power_average_watt`，来自 ACPI `power_meter`/Intel Node Manager；盘点时读数约
  311–337 W；
- `node_cpu_package_throttles_total`、`node_cpu_core_throttles_total`，盘点时均为 0；
- `node_edac_correctable_errors_total`、`node_edac_uncorrectable_errors_total`，盘点时均为 0；
- `/dev/ipmi0`，但权限是 `root:root 0600`；
- 12 块 Seagate SAS HDD、3 块 Micron SATA SSD、2 块 NVMe。逐盘只读 `smartctl -a -j`
  已能读出温度与健康状态；代表性路径 `/dev/sda`（SCSI）为 36°C、trip 60°C，
  `/dev/sdb`（SAT）为 32°C，`/dev/nvme0n1` 为 46°C。全部盘点范围内 SAS/SATA 为
  29–40°C，NVMe 为 46–50°C。
- `rapl` 虽是 node exporter 默认 collector，但在 Minisforum 和 `el2` 的当前 scrape 中均
  失败；对应 `energy_uj` 只允许 root 读取，而 exporter 以专用用户运行。因此 RAPL 不是
  当前零配置的功耗来源。

## 候选指标排序

难度以当前仓库为基准：**0** 只改 dashboard，**1** 增加一个现成 collector/模块，
**2** 需要额外权限、凭据或主机特定配置，**3** 需要新硬件或自定义采集。

| 排名 | 指标 | 覆盖/当前状态 | 难度 | 价值 | 可靠性 | 结论 |
|---:|---|---|---:|---|---|---|
| 1 | `node_hwmon_temp_celsius` + chip/sensor label | 四台物理机已采集 | 0 | 高 | 高 | 立即加 summary 与 history |
| 2 | `node_cooling_device_cur_state/max_state` | 两台 R4S、`el2`、Minisforum 已采集 | 0 | 高 | 高 | 直接显示内核请求的 cooling/throttle 状态 |
| 3 | `node_cpu_package_throttles_total` / core throttles | `el2` 已采集 | 0 | 高 | 高 | 比从频率下降推断过热更直接 |
| 4 | `node_hwmon_temp_crit_celsius - current` 与温度 alarm | 部分 Intel CPU、NVMe、DIMM、NIC 有；R4S/AMD 不完整 | 0 | 高 | 高/中 | headroom 已展示；WAN scrape 已收窄，sticky alarm 可后续增加 |
| 5 | `node_hwmon_power_average_watt`、EDAC | `el2` 已采集 | 0 | 中高 | 高 | 与温度、负载关联展示 |
| 6 | `smartctl_device_temperature` 和 SMART health | `el2` 已部署，17 块盘全部进入 Prometheus | 1 | 高 | 高 | SAS/SATA 使用稳定 by-id，独立 60 秒 scrape |
| 7 | node exporter `wifi` collector | Minisforum AP 实测可用，当前未启用 | 1 | 中高 | 中高 | 主机级 opt-in；控制基数与隐私 |
| 8 | IPMI 温度/风扇/PSU | `el2` 有 BMC device，尚未读取传感器清单 | 2 | 高 | 未验证/预期高 | 做完前两层后再接入 |
| 9 | hwmon 风扇、板级电压、电流、功率 | 当前只有少量 GPU/整机功率，没有 fan RPM | 0/2 | 中 | 中 | 自动消费将来出现的标准 hwmon；不要假设现在有 |
| 10 | SATA `drivetemp` | `el2` 模块存在但未加载；源码只接受 SATA/SAT | 1 | 中 | 中 | 最多补 3 块 Micron，覆盖不了 12 块 SAS，不替代 smartctl |
| 11 | PHY/SFP 温度与光功率 | 当前 hwmon 无对应设备；`el2` 的 `ethtool -m` 返回 `EINVAL` | 0/2 | 条件性高 | 中高 | 将来换成带 DDM/SFP hwmon 的模块时自动接入 |
| 12 | 环境温湿度 | 五台均无对应传感器 | 3 | 中 | 取决于硬件 | 需要外置 USB/I²C 传感器，不是本轮低成本项 |

## P0：直接增加温度 dashboard

### 1. CPU/SoC 当前最高温

这个 stat 在两台 R4S、Minisforum 和 `el2` 都有数据，在 VMware guest 上自然为空：

```promql
max(
  node_hwmon_temp_celsius{sensor!="temp0"}
  * on(chip) group_left(chip_name)
  node_hwmon_chip_names{chip_name=~"cpu_thermal_0|k10temp|coretemp"}
)
```

使用 `max` 是为了回答“当前最热的 CPU/SoC 传感器是多少”，不是把它命名为单一的
“CPU die 温度”。Intel `coretemp` 同时提供 package/core 值与 Tcontrol/TjMax；官方文档说明
TjMax 处硬件会强制散热（[coretemp](https://docs.kernel.org/hwmon/coretemp.html#description)）。
AMD 的 `Tctl` 是平台散热控制值，不能无条件当作机壳或裸片的物理温度；Tccd 才是 CCD
通道（[k10temp](https://docs.kernel.org/hwmon/k10temp.html#description)）。

不要给所有主机共用一个“精确安全上限”。两台 R4S 当前实测 CPU trip 为 70°C/75°C
passive、95°C critical，GPU 为 75°C passive、95°C critical；Intel、AMD、NVMe、DIMM 和
NIC 的阈值各不相同。面板可以用 70/85°C 做视觉提示，但正式告警应优先使用硬件提供的
crit/alarm。

### 2. 筛选后的全部温度历史

建议先关联人类可读 chip name，再去掉 thermal-to-hwmon 的 `temp0` 副本和 `el2` 的 20 条
per-core 序列：

```promql
(
  node_hwmon_temp_celsius{sensor!="temp0"}
  * on(chip) group_left(chip_name)
  node_hwmon_chip_names
)
unless on(chip, sensor)
node_hwmon_sensor_label{label=~"Core .*"}
```

保留 `chip`、`sensor` 作为稳定标识；可另外用 `node_hwmon_sensor_label` 给 Tctl、Tccd、
Package、NVMe Composite 等添加可读 legend。不要绑定 `/sys/class/hwmon/hwmon0` 这类编号：
编号随驱动加载顺序变化，node exporter 自己也会优先从稳定 device path 构造 `chip`
（[实现](https://github.com/prometheus/node_exporter/blob/v1.11.1/collector/hwmon_linux.go#L377-L433)）。

`sensor!="temp0"` 不是猜测。node exporter 会同时扫描 hwmon 目录和它的 `device` 目录
（[实现](https://github.com/prometheus/node_exporter/blob/v1.11.1/collector/hwmon_linux.go#L175-L185)）；
thermal zone 又可镜像成 hwmon
（[thermal sysfs](https://docs.kernel.org/driver-api/thermal/sysfs-api.html#sysfs-attributes-structure)），
因此两台 R4S 和 `el2` 的 PCH 在当前版本上各出现 `temp0`/`temp1` 双份实测值。

### 3. 临界余量与硬件 alarm

有 `temp*_crit` 的设备可以直接计算剩余温度余量：

```promql
node_hwmon_temp_crit_celsius
- on(chip, sensor)
node_hwmon_temp_celsius
```

Linux hwmon 的 alarm 是硬件直接报告的状态，不是驱动拿当前读数临时比较阈值；这种 alarm
能保留两次轮询之间发生过的越限，语义通常优于 Grafana 固定阈值
（[hwmon alarm ABI](https://docs.kernel.org/hwmon/sysfs-interface.html#alarms)）。

需要过滤无效 sentinel：当前两台 ZHITAI NVMe 的 Sensor 1/2 暴露
`temp_max=65261.85°C`，这是不支持阈值的编码，不是真实上限；同一设备的某些 min 也会出现
`-273.15°C`。不要泛化绘制所有 `node_hwmon_temp_max_celsius`，优先使用有合理值的 crit。

node exporter 1.11.1 还会把 `temp*_crit_alarm` 命名成误导性的
`node_hwmon_temp_crit_alarm_celsius`。它的值仍是 0/1，不能按摄氏度解释；上游 hwmon collector
只有属性名正好为 `alarm` 时才走无单位分支
（[实现](https://github.com/prometheus/node_exporter/blob/v1.11.1/collector/hwmon_linux.go#L264-L310)）。

`spd5118` 的 alarm 是 sticky-until-read：node exporter 的读取会清除已经恢复的状态
（[SPD5118 官方文档](https://docs.kernel.org/hwmon/spd5118.html#hardware-monitoring-sysfs-entries)）。
每个 `node-wan-*` job 仍会请求同一 node exporter，但现已通过 `collect[]` 只运行
`netclass` 和 `netdev`。这避免 metric relabel 之前执行 hwmon collector，也就不会由额外 WAN
scrape 提前读取并清除 sticky alarm。之后可以例如用
`max_over_time(node_hwmon_temp_crit_alarm_celsius[5m])` 查看近期事件。官方说明确认 `collect[]`
会限制一次请求实际运行的 collector
（[node exporter filtering](https://github.com/prometheus/node_exporter/blob/v1.11.1/README.md#filtering-enabled-collectors)）。
主 `node` job 仍执行完整 collector 集合，温度、crit 和 cooling series 不受影响。

### 4. cooling 与真实节流事件

```promql
max(node_cooling_device_cur_state)
```

```promql
increase(node_cpu_package_throttles_total[$__range])
```

`cur_state` 是内核当前请求的散热/限速状态，`max_state` 是该 cooling device 的上限；两台
R4S 的类型能区分 A53、A72 和 GPU，x86 则是 Processor cooling device
（[thermal sysfs](https://docs.kernel.org/driver-api/thermal/sysfs-api.html#sysfs-attributes-structure)）。
不同设备的 state 数值不能横向比较；总览可显示“是否大于 0”，历史图再画
`cur_state / max_state`。

CPU frequency 已经采集，但只适合作为关联证据：powersave、空闲和工作负载都会改变频率，
不能单凭低频认定过热。`el2` 已有的 package/core throttle counter 是更可靠的事件指标。

## P1：低成本但需要新增采集配置

### `el2` 的 smartctl exporter

这是新增 exporter 中回报最高的一项，现已部署。NVMe 温度此前已通过 hwmon 存在，但 12 块
SAS HDD 和 3 块 SATA SSD 没有 Prometheus 温度；smartctl exporter 现在通过 by-id 自动发现
并读取全部 17 块盘，分别覆盖 SCSI、SAT 和 NVMe。

锁定 Nixpkgs 已提供 `services.prometheus.exporters.smartctl`，默认可自动发现设备、以 60 秒
间隔限制实际查询，并配置了磁盘组、device ACL 和必要 capability
（[锁定 Nixpkgs 模块](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/nixos/modules/services/monitoring/prometheus/exporters/smartctl.nix#L25-L78)）。
exporter package 已把 `smartmontools` 的绝对路径编入闭包，不依赖 `el2` 的交互式 PATH。
锁定版本 0.14.0 会导出
`smartctl_device_temperature`、SMART status、media errors、percentage used、power-on time 等
（[官方 metrics 源码](https://github.com/prometheus-community/smartctl_exporter/blob/v0.14.0/metrics.go)）。

部署验证确认 exporter 的 systemd device policy/capability 能读取全部 aacraid/SAS/SAT 盘。
既有 `/dev/nvme0`、`/dev/nvme1` 在首切时没有自动重放 udev `ACTION=add`，因此部署时执行了
一次 `udevadm trigger --settle --subsystem-match=nvme --action=add` 并重启 exporter；之后 ACL、
17 条 device/current-temperature/SMART-status series 均正常。后续开机或设备重新出现时，
NixOS 模块的 udev 规则会自动应用该 ACL。

Dashboard 的 SMART 温度分支只补充 12 块 SAS 和 3 块 SATA。两块 NVMe 的 smartctl current
是 hwmon Composite 温度的整数版本；Overview 已通过 hwmon 展示 Composite 与两个 secondary
sensor，因此不再重复绘制 smartctl NVMe 温度。NVMe 的 SMART health、寿命和错误指标仍完整
保留在 Prometheus。

它使用独立的 60 秒 scrape，而不是沿用 node job 的 15 秒；避免无意义地频繁访问机械盘。
Linux `drivetemp` 官方文档也提醒，读温可能重置某些磁盘的 spin-down timer
（[drivetemp](https://docs.kernel.org/hwmon/drivetemp.html#usage-note)）。

`drivetemp` 看似更轻，但对这台机器不是完整替代：`el2` 的模块存在但未加载，上游实现会
明确拒绝非 SATA 设备，只能尝试覆盖 3 块 Micron SATA SSD，不能覆盖 12 块 Seagate SAS
（[识别逻辑](https://github.com/torvalds/linux/blob/master/drivers/hwmon/drivetemp.c#L498-L574)）。

### `somo-minisforum` 的 Wi-Fi collector

node exporter 的 `wifi` collector 默认关闭。2026-08-28 在本机用相同的 1.11.1 二进制临时
启用、只绑定 loopback 端口后，已验证不需要额外 capability，并成功读出：

- AP 频率；
- 每个 station 的 signal dBm、连接/不活跃时间；
- RX/TX bitrate、bytes、packets；
- TX retry、failed 和 beacon loss。

这与官方 collector 定义一致
（[README](https://github.com/prometheus/node_exporter/blob/v1.11.1/README.md#disabled-by-default)、
[wifi collector](https://github.com/prometheus/node_exporter/blob/v1.11.1/collector/wifi_linux.go)）。
实现成本只是对该主机添加 `enabledCollectors = [ "wifi" ]`；不要默认扩到全部 Home Router。

风险是 station MAC 会成为 label。家庭 AP 基数通常可控，但客户端随机 MAC 和访客轮换会在
90 天保留期内积累序列，也会把设备标识写进 Prometheus。启用前应接受这个隐私/基数取舍，
并观察 `scrape_samples_post_metric_relabeling`。上游对默认关闭 collector 也明确要求逐项测试
scrape 时间和基数
（[官方说明](https://github.com/prometheus/node_exporter/blob/v1.11.1/README.md#disabled-by-default)）。

## P2：IPMI 与板级风扇

`el2` 的 Inspur BMC 是获得“环境温度”和风扇转速的最佳现成来源。官方 IPMI exporter 会
直接提供 `ipmi_temperature_celsius`、`ipmi_temperature_state`、`ipmi_fan_speed_rpm`、
电压、电流和功率指标
（[官方指标文档](https://github.com/prometheus-community/ipmi_exporter/blob/master/docs/metrics.md)）。
锁定 Nixpkgs 也已有 IPMI exporter 模块
（[模块](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/nixos/modules/services/monitoring/prometheus/exporters/ipmi.nix#L20-L64)）。

以上只是 exporter 能表达的标准指标；本次没有运行 `ipmi-sensors`，所以 `el2` 实际提供
哪些 inlet/exhaust/DIMM/fan/PSU 传感器仍是未决事实。

但当前不能把“有 `/dev/ipmi0`”推断成“加一个 enable 就能工作”：设备是
`root:root 0600`，而 NixOS exporter 的通用 hardening 默认启用 private devices、空 device
allowlist 和非 root service user
（[锁定 Nixpkgs exporter 基类](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/nixos/modules/services/monitoring/prometheus/exporters.nix#L312-L410)）。
可选方案是安全地放行本地 `/dev/ipmi0`，或使用 BMC LAN endpoint 与 agenix 凭据。后者还能在
主机关机时采集，但需要确认 BMC 地址、账号和网络可达性。

五台当前 scrape 中都没有 `node_hwmon_fan_rpm`。这是**没有 Linux 可见的 tach sensor**，
不是“机器一定没有风扇”。R4S 官方板卡有 5V 风扇接口，vendor kernel 还描述过基于温度的
PWM fan control（[FriendlyElec 文档](https://wiki.friendlyelec.com/wiki/index.php/NanoPi_R4S#How_to_Control_Fan_Speed_for_Cooling)），
但当前 mainline NixOS 设备树没有相应 fan hwmon/cooling device；而 2-pin 风扇本身通常也没有
转速反馈。因此 R4S 风扇 RPM 不属于低成本、可靠的软件指标。

## 条件性来源：暂时不要专门实现

- **SFP/QSFP DDM：** Linux SFP core 可通过标准 hwmon 导出模块温度、VCC、laser bias、
  TX/RX optical power、阈值和 alarm
  （[内核实现](https://github.com/torvalds/linux/blob/master/drivers/net/phy/sfp.c)）。但 `el2` 当前
  两个 i40e 口执行只读 `ethtool -m` 都返回 `EINVAL`，没有可用 DOM 数据。
- **铜口 PHY：** Aquantia、部分 Realtek/MaxLinear/Marvell PHY 已有 hwmon 温度支持；如果
  将来硬件/驱动暴露出来，现有 node exporter 会自动采集。当前五机只有 `el2` I350 controller
  temperature 已经出现，无需另做 PHY exporter。
- **ethtool collector：** 本机临时测试证明不加过滤会从 i40e/igc/r8169 产生大量 driver-defined
  series；它适合 CRC/FEC/MAC fault，不是通用温度来源。若以后启用，必须同时设置 device 和
  metric include filter
  （[官方 collector 说明](https://github.com/prometheus/node_exporter/blob/v1.11.1/README.md#include--exclude-flags)）。
- **RAPL：** Minisforum 与 `el2` 当前都因 `energy_uj` 权限而采集失败。若以后确实需要 CPU
  package energy，应单独设计最小权限；目前 `el2` 已有 ACPI 整机功率，优先消费现成指标。
- **外部温湿度：** 当前没有 USB/I²C 温湿度计。只有确实需要机柜/房间环境数据时再选硬件；
  不应为了填满 dashboard 在 Home Router 模块中加入无消费者的抽象。

## 已验证事实、推断与未决项

### 已验证事实

- 五个启用 Home Router monitoring 的实际节点均运行 node exporter 1.11.1；配置没有关闭
  hwmon/thermal/cpu collectors。
- 四台物理机已经有可用温度，VMware guest `el` 没有物理温度。
- 两台 R4S 和 `el2` PCH 的 `temp0` 是 thermal-to-hwmon 重复项；全局过滤它能去重。
- 本文列出的 R4S 70/75/95°C trip points 来自 2026-08-28 两台机器的实时 sysfs，
  不是从上游 DTS 推断。
- Minisforum 有 CPU/CCD、DIMM、NVMe、Wi-Fi、GPU 温度，但没有 fan RPM。
- `el2` 有 CPU/PCH/NVMe/NIC 温度、整机功率、thermal throttle counter、EDAC、可读
  SMART 和本地 IPMI device，但没有当前 Prometheus fan RPM。

### 推断

- `el2` 的 IPMI 大概率能补齐进风、出风、DIMM、风扇和 PSU；这是服务器 BMC 的典型能力，
  也是 IPMI exporter 的标准指标，但必须以实际 sensor inventory 为准。
- 加载 `drivetemp` 大概率能覆盖 3 块 SATA SSD；在 canary 实测前不能当成事实，且无论如何
  覆盖不了源码会拒绝的 12 块 SAS 盘。
- 将来更换带 DDM 的光模块或受支持 PHY 后，hwmon 会自动产生新指标；无需现在写兼容层。

### 未决项

- `el2` 选择本地 IPMI device 还是 BMC LAN，以及对应最小权限/凭据方案。
- 是否接受 Wi-Fi station MAC 进入 90 天时序库。
- 是否希望 Home Router Overview 对无温度的 VM 显示显式 N/A；PromQL 返回空本身是正确
  语义，不应伪造 0°C。
- 是否需要机柜/室内环境温湿度；这会引入新硬件，不能由现有模块自动推导。

## 已实施的最小切片

第一批在 [`overview.nix`](../../nixos/optional/home-router/overview.nix) 增加了四块：

1. `CPU/SoC Temperature` stat；
2. `Hardware Temperatures` history，过滤 `temp0` 与 per-core；
3. `Thermal Mitigation` stat/history，使用 cooling state 和已有 throttle counter；
4. `Temperature Headroom`，只显示确实提供合理 crit 的 series。

这批没有新增 option、service、权限或兼容层，并已覆盖四台物理路由器。`node-wan-*` scrape
也已限定为 `netclass`/`netdev`，`el2` smartctl 也已作为主机特定能力接入。后续可增加
sticky alarm，再处理 Minisforum Wi-Fi 和 `el2` IPMI。这样每一步都有真实消费者，也避免把
服务器、AP 和 VMware guest 的硬件差异塞进一个假装统一的接口。

## 运行态复核命令

以下只读命令足以在部署前复核传感器和 exporter 结果：

```bash
for d in /sys/class/hwmon/hwmon*; do
  printf '%s: ' "$(readlink -f "$d")"
  cat "$d/name"
done

for d in /sys/class/thermal/thermal_zone*; do
  printf '%s type=%s temp=%s\n' \
    "${d##*/}" "$(cat "$d/type")" "$(cat "$d/temp")"
done

curl -fsS http://127.0.0.1:9100/metrics |
  rg '^(node_hwmon_|node_thermal_zone_|node_cooling_device_|node_cpu_.*throttles)'
```

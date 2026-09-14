# OSX-PROXMOX 工作原理

> 调查日期：2026-09-14。上游源码固定在提交
> [`209f6df3a4e36a9a2853975fd962fbc34d562249`](https://github.com/luchina-gabriel/OSX-PROXMOX/tree/209f6df3a4e36a9a2853975fd962fbc34d562249)。
> 本文把仓库源码和所附 OpenCore 镜像作为事实来源，以 OpenCore、QEMU、Linux KVM、
> Proxmox 和 Apple 的一手文档解释其行为。安全与许可部分不是法律意见。

## 结论

OSX-PROXMOX 不是 macOS 模拟器，也没有重写 macOS。它是一套高权限安装脚本，把现成的
Proxmox/KVM/QEMU 组合成一台“足够像 Intel Mac”的 x86 虚拟机：

```text
物理机固件
  -> Proxmox Linux + KVM
  -> QEMU Q35 虚拟硬件 + OVMF UEFI
  -> OpenCore 启动盘
       ├─ 注入 Mac 机型/序列号/SMBIOS/NVRAM
       ├─ 注入 VirtualSMC、Lilu、WhateverGreen 等 kext
       └─ 修补/规避 CPU、FileVault 与虚拟机兼容性检查
  -> Apple Recovery 的 BaseSystem.dmg
  -> 安装到虚拟 SATA/VirtIO 磁盘
  -> 此后仍经 OpenCore 启动已安装的 APFS 系统
```

真正承担各层工作的分别是：KVM 执行客户机指令，QEMU 提供虚拟硬件，OVMF 提供普通 PC
UEFI，OpenCore 把这个 UEFI/硬件描述转换成 macOS 能接受的启动环境。项目的价值主要是把
这些参数、补丁和下载步骤预先配好，而不是发明了新的虚拟化机制。

## 1. 宿主机准备：它会改整台 Proxmox 主机

README 推荐把 `install.osx-proxmox.com` 返回的内容直接交给 root shell
（[README L17-L25](https://github.com/luchina-gabriel/OSX-PROXMOX/blob/209f6df3a4e36a9a2853975fd962fbc34d562249/README.md#L17-L25)）。
入口脚本删除现有 enterprise/ceph 软件源文件、安装 Git、浅克隆 `main` 并运行 `setup`
（[`install.sh` L39-L101](https://github.com/luchina-gabriel/OSX-PROXMOX/blob/209f6df3a4e36a9a2853975fd962fbc34d562249/install.sh#L39-L101)）。

首次运行 `setup` 时，它还会：

- 打开 Intel VT-d 或 AMD IOMMU，并使用 passthrough 模式；
- 禁用宿主机 EFI/VESA framebuffer，加载 VFIO modules；
- 同时 blacklist NVIDIA、nouveau、radeon、amdgpu 和若干 HDA 驱动；
- 让 KVM 忽略客户机访问未知 MSR；
- 无条件设置 `vfio_iommu_type1 allow_unsafe_interrupts=1`；
- 打开 nested virtualization，修改 GRUB、Proxmox 前端文件并重启。

这些不是推断，均由
[`setup` L355-L391](https://github.com/luchina-gabriel/OSX-PROXMOX/blob/209f6df3a4e36a9a2853975fd962fbc34d562249/setup#L355-L391)
直接执行。IOMMU/VFIO 的目的是以后把真实 GPU、USB 控制器或网卡交给 VM；macOS VM
本身并不要求每个设备都 passthrough。Proxmox 官方文档也说明，PCI passthrough 后设备不再
供宿主机使用，VM 不能迁移，并要求正确的 IOMMU 与 interrupt remapping
（[PCI Passthrough：Introduction/Requirements](https://pve.proxmox.com/wiki/PCI_Passthrough#Introduction)）。

## 2. QEMU/Proxmox 如何塑造“像 Mac 的 PC”

创建 VM 时，脚本调用 `qm create`，主要配置如下
（[`setup` L418-L481](https://github.com/luchina-gabriel/OSX-PROXMOX/blob/209f6df3a4e36a9a2853975fd962fbc34d562249/setup#L418-L481)）：

| 层次 | 配置 | 作用 |
| --- | --- | --- |
| 固件 | `bios=ovmf` + 4 MiB `efidisk0` | 让普通 PC VM 从 UEFI 启动并保存 UEFI variables；OVMF 本身不是 Apple 固件 |
| 芯片组 | `machine=q35` | 提供较现代的 PCIe/AHCI PC 平台 |
| CPU | Penryn/Haswell/Broadwell/Skylake 模型，`vendor=GenuineIntel` | 向 macOS 暴露它能识别的 Intel 风格 CPUID；AMD 宿主也这样报告 |
| 时钟 | `+invtsc`、`vmware-cpuid-freq=on` | 给客户机稳定的 TSC/频率信息 |
| Apple SMC | `isa-applesmc,osk=...` | QEMU 模拟 Apple SMC 接口并提供两段 OSK 数据 |
| 显示/网络 | `vga=vmware`、`vmxnet3` | 默认先使用虚拟显示和虚拟网卡，而非真实 GPU |
| 存储 | 旧系统用 SATA，新系统用 VirtIO；另挂 OpenCore 与 Recovery 盘 | 把引导器、恢复环境和目标系统盘分开 |

QEMU 自己的 AppleSMC 源码解释得很直接：Intel Mac 的 SMC 保存 macOS 用来绑定硬件的
“magic keys”；`isa-applesmc` 要求 64 字符 `osk`，再把它分成 `OSK0`/`OSK1` 两个 SMC key
（[QEMU `applesmc.c` L23-L28](https://gitlab.com/qemu-project/qemu/-/blob/master/hw/misc/applesmc.c#L23-28)、
[L308-L335](https://gitlab.com/qemu-project/qemu/-/blob/master/hw/misc/applesmc.c#L308-335)）。
所以这里不是单纯改一个“Apple”厂商字符串，而是补上 macOS 启动所检查的一类设备接口。

CPU 处理也分两层：QEMU 选择一个客户机可见的 CPU model/feature set；OpenCore 再做
CPUID/电源管理/内核兼容处理。QEMU 文档明确把 `-cpu model` 定义为选择 CPU 模型和额外
features（[QEMU invocation: `-cpu`](https://qemu.readthedocs.io/en/master/system/invocation.html#hxtool-0)）。
脚本对 AMD 与不同 Intel 世代使用不同参数，但都强制 `GenuineIntel` 和 `+invtsc`
（[`setup` L434-L454](https://github.com/luchina-gabriel/OSX-PROXMOX/blob/209f6df3a4e36a9a2853975fd962fbc34d562249/setup#L434-L454)）。

这不是完整硬件仿真：绝大部分客户机指令仍由 KVM 在真实 AMD/Intel CPU 上执行；CPU model
主要控制客户机看见哪些 CPUID 位和相关虚拟化行为。因此宿主 CPU 缺少必要指令、TSC 不稳定
或某代 QEMU/KVM 行为变化时，仍会启动失败或崩溃。

## 3. OpenCore 是兼容层和真正的启动入口

仓库所附的 96 MiB `.iso` 实际是一个 MBR + FAT32 raw disk image，不是 ISO9660 光盘。
脚本把两个所谓 ISO 先作为 Proxmox CD-ROM 添加，再直接把 VM 配置中的所有
`media=cdrom` 改成 `media=disk`
（[`setup` L470-L481](https://github.com/luchina-gabriel/OSX-PROXMOX/blob/209f6df3a4e36a9a2853975fd962fbc34d562249/setup#L470-L481)），
正与这个格式相符。

我从提交中的
[`opencore-osx-proxmox-vm.iso`](https://github.com/luchina-gabriel/OSX-PROXMOX/blob/209f6df3a4e36a9a2853975fd962fbc34d562249/EFI/opencore-osx-proxmox-vm.iso)
按 512 字节分区偏移读取 FAT32 内容；镜像 SHA-256 为
`4e81a23b92c6f64c5add115dde6dc8ca6fa1fd0e196ee8a25791c8dc5c2e83d3`，其中
`EFI/OC/config.plist` 的 SHA-256 为
`cd69311e6ee491b7b05b1426e56c3670ea5b5bb9ee67917fd31f077a28fd5ada`。配置表现为：

- `PlatformInfo.Automatic=true`、`UpdateSMBIOS=true`、`UpdateSMBIOSMode=Create`，默认身份为
  `MacPro7,1`，并设置 serial、MLB、UUID 和 ROM；
- 注入 `Lilu`、`VirtualSMC`、`WhateverGreen`、`RestrictEvents`、
  `AppleMCEReporterDisabler` 和 `VMHide`；
- 加载 `HfsPlus.efi`、`OpenRuntime.efi`、OpenCanopy 等 UEFI driver；
- 注入 `SSDT-EC-USBX.aml`，并通过 NVRAM 写入 boot arguments；
- `DummyPowerManagement=true`、`ProvideCurrentCpuInfo=true`，另有跨不同 Darwin kernel
  版本强制 Penryn CPU family 的二进制 kernel patches；
- 对 Darwin 21–25 的 APFS 函数 `_apfs_filevault_allowed` 打补丁，明确阻止 FileVault。

OpenCore 官方手册说明，`PlatformInfo` 就是为 macOS services 生成/填写兼容身份字段，
`SystemProductName` 是决定 OS 是否把机器视为受支持 Mac model 的关键字段
（[OpenCore 1.0.7 Configuration L5440-L5447](https://github.com/acidanthera/OpenCorePkg/blob/1.0.7/Docs/Configuration.tex#L5440-L5447)、
[L6479-L6489](https://github.com/acidanthera/OpenCorePkg/blob/1.0.7/Docs/Configuration.tex#L6479-L6489)）。
官方手册也将 `DummyPowerManagement` 定义为禁用 AppleIntelCpuPowerManagement，并明确提到
VM 可能需要虚拟 CPU 和 dummy power-management patches
（[L2325-L2334](https://github.com/acidanthera/OpenCorePkg/blob/1.0.7/Docs/Configuration.tex#L2325-L2334)、
[L2386-L2413](https://github.com/acidanthera/OpenCorePkg/blob/1.0.7/Docs/Configuration.tex#L2386-L2413)）。

`setup` 会调用固定 revision 的 GenSMBIOS submodule；默认以 `iMacPro1,1` 生成 Type、serial、
MLB、UUID、ROM，写入 ISO 内的 `config.plist`，并把结果保存在 ISO storage 下的
`.smbios.json`
（[`setup` L510-L611](https://github.com/luchina-gabriel/OSX-PROXMOX/blob/209f6df3a4e36a9a2853975fd962fbc34d562249/setup#L510-L611)、
[`GenSMBIOS` gitlink](https://github.com/luchina-gabriel/OSX-PROXMOX/tree/209f6df3a4e36a9a2853975fd962fbc34d562249/tools/GenSMBIOS)）。
这层身份主要服务于系统兼容判断与 Apple services；它和 QEMU 的空 `-smbios type=2` 不是
一回事，最终 Mac 风格 SMBIOS 主要由 OpenCore 建立。

## 4. Recovery 下载与安装链

每个菜单项携带 macOS 版本、Apple board-id、MLB 查询值、镜像容量和系统盘总线
（[`setup` L52-L63](https://github.com/luchina-gabriel/OSX-PROXMOX/blob/209f6df3a4e36a9a2853975fd962fbc34d562249/setup#L52-L63)）。
选择版本后，脚本创建并挂载一个 FAT32 文件，调用 `macrecovery.py` 模拟 Apple Internet
Recovery 请求，把 Apple 返回的 DMG 和 chunklist 放进
`com.apple.recovery.boot/`，最后作为 Recovery raw disk 挂给 VM
（[`setup` L394-L415](https://github.com/luchina-gabriel/OSX-PROXMOX/blob/209f6df3a4e36a9a2853975fd962fbc34d562249/setup#L394-L415)）。

`macrecovery.py` 的控制请求发往 `osrecovery.apple.com`，提交 board-id、MLB 和随机 session
字段，响应中取得 DMG/chunklist URL 与 token
（[`macrecovery.py` L127-L190](https://github.com/luchina-gabriel/OSX-PROXMOX/blob/209f6df3a4e36a9a2853975fd962fbc34d562249/tools/macrecovery/macrecovery.py#L127-L190)）。
它不是盲信下载结果：代码内置 Apple EFI ROM public key，验证 chunklist 的 RSA/SHA-256
签名，再逐 chunk 校验 DMG 哈希
（[`macrecovery.py` L82-L124](https://github.com/luchina-gabriel/OSX-PROXMOX/blob/209f6df3a4e36a9a2853975fd962fbc34d562249/tools/macrecovery/macrecovery.py#L82-L124)、
[L248-L316](https://github.com/luchina-gabriel/OSX-PROXMOX/blob/209f6df3a4e36a9a2853975fd962fbc34d562249/tools/macrecovery/macrecovery.py#L248-L316)）。

启动时 OVMF 先进入 OpenCore；OpenCore 的 HFS+/APFS/DMG 支持找到 Recovery 的
BaseSystem.dmg 并启动 Apple 恢复系统。用户仍需在 Recovery 内格式化目标盘并执行网络安装。
安装完成后，OpenCore 扫描目标 APFS 卷并启动其 `boot.efi`。所以 Recovery 是安装源，
OpenCore 才是每次启动都需要的“垫片”。镜像根目录另带四个 `install-EFI-*.pkg`，用于把
不同 GPU/纯 VM 的 EFI 配置装入 macOS；README 为此要求先全局关闭 Gatekeeper
（[README L35-L41](https://github.com/luchina-gabriel/OSX-PROXMOX/blob/209f6df3a4e36a9a2853975fd962fbc34d562249/README.md#L35-L41)）。

## 5. GPU 与设备 passthrough

默认 VM 只有 `vga=vmware`，脚本没有自动给某个 VM 加 `hostpciN`。它所做的是先在宿主机
启用 IOMMU/VFIO、释放 framebuffer 和 blacklist 显卡驱动，用户再通过 Proxmox 把 GPU 及
通常同卡的 HDMI audio function 交给 VM。没有兼容物理 GPU 时，仓库附带的所谓 GPU
optimization 反而会关闭 Metal/OpenGL/hardware acceleration，强制软件渲染
（[`Tweaks macOS`](https://github.com/luchina-gabriel/OSX-PROXMOX/blob/209f6df3a4e36a9a2853975fd962fbc34d562249/Patches/macOS%20VM%20-%20GPU%20Optimization/Tweaks%20macOS%20-%20for%20VM.txt)）；
它减少动画和后台服务，不会让虚拟 VMware VGA 获得真实 GPU 加速。

passthrough 的基本边界是 IOMMU group：待分配的设备及不可拆分的同组设备必须一起处理。
项目菜单可以加入 `pcie_acs_override=downstream,multifunction pci=nommconf` 来人为拆组
（[`setup` L1049-L1052](https://github.com/luchina-gabriel/OSX-PROXMOX/blob/209f6df3a4e36a9a2853975fd962fbc34d562249/setup#L1049-L1052)），
但 Proxmox 官方把 ACS override 明确列为有风险的最后手段
（[PCI Passthrough：Verify IOMMU isolation](https://pve.proxmox.com/wiki/PCI_Passthrough#Verify_IOMMU_isolation)）。
GPU 还必须有相容的 macOS driver、可重置、可供 OVMF 初始化；这就是不同显卡/主板表现差异
很大的根本原因，OpenCore 的机型伪装不能凭空生成驱动。

## 6. 安全事实：README 的“all security features”不成立

README 声称 OpenCore 配置是 “SIP Enabled, DMG only signed by Apple and all features of
securities”
（[README L61-L63](https://github.com/luchina-gabriel/OSX-PROXMOX/blob/209f6df3a4e36a9a2853975fd962fbc34d562249/README.md#L61-L63)）。
前两部分基本符合所附配置：`csr-active-config=00000000` 表示 SIP 默认开启，
`DmgLoading=Signed` 只让 OpenCore 加载 Apple 签名的 recovery DMG。OpenCore 手册也将
`DmgLoading` 定义为 Recovery DMG policy
（[Configuration L4418-L4423](https://github.com/acidanthera/OpenCorePkg/blob/1.0.7/Docs/Configuration.tex#L4418-L4423)）。

但“所有安全特性”与镜像实际配置冲突：

| 项目 | 所附配置 | 含义 |
| --- | --- | --- |
| Apple Secure Boot | `SecureBootModel=Disabled`，`ApECID=0` | 没有 Apple Secure Boot；OVMF UEFI 也不等于 Apple Secure Boot |
| OpenCore Vault | `Vault=Optional` | OpenCore 自身配置/驱动没有强制 vault 验证 |
| 扫描策略 | `ScanPolicy=0` | 使用 failsafe 的开放扫描策略 |
| APFS driver 下限 | `MinDate=-1`、`MinVersion=-1` | 不限制旧 APFS driver |
| 磁盘加密 | kernel patch 阻止 FileVault（Darwin 21–25） | Monterey 至 Tahoe 的 FileVault 被明确关闭 |

OpenCore 官方定义中，只有非 `Disabled` 的 `SecureBootModel` 才对应 Apple Secure Boot 的
Medium Security，再配非零 `ApECID` 才可能达到 Full Security；VM 还需考虑
`ForceSecureBootScheme`
（[Configuration L4611-L4662](https://github.com/acidanthera/OpenCorePkg/blob/1.0.7/Docs/Configuration.tex#L4611-L4662)）。
因此准确表述应是：**它默认保留 SIP，并验证 Recovery DMG，但没有建立完整 secure boot
chain，而且主动禁用了 FileVault。**

供应链也应单独看：

- 首条命令以 root 执行一个会随服务器响应变化的脚本；随后又运行 GitHub `main` 当前内容，
  没有固定 commit；
- OpenCore ISO 从 `raw/main` 下载，先删除旧文件，既没有固定 commit，也没有校验预期 hash
  或签名
  （[`setup` L897-L914](https://github.com/luchina-gabriel/OSX-PROXMOX/blob/209f6df3a4e36a9a2853975fd962fbc34d562249/setup#L897-L914)）；
- Apple Recovery payload 有 chunklist 签名和逐块 hash，这是链条中验证较强的一段；但
  recovery session/metadata 查询本身使用明文 HTTP，而非 HTTPS；
- README 要求全局关闭 Gatekeeper 才运行镜像内 EFI package，这会扩大 macOS 用户态
  安装风险。

## 7. 许可与运维限制

### Apple 许可

以 macOS Sequoia SLA 为例，Mac App Store license 只允许在**已经运行 macOS 的
Apple-branded computer** 上运行最多两个额外虚拟实例，并限定为开发、开发测试、macOS
Server 或个人非商业用途；同一 SLA 另行明确禁止在 non-Apple-branded computer 上安装或
运行 macOS
（[Apple macOS Sequoia SLA §2B(iii), PDF p.2](https://www.apple.com/legal/sla/docs/macOSSequoia.pdf#page=2)、
[§2J, PDF p.5](https://www.apple.com/legal/sla/docs/macOSSequoia.pdf#page=5)）。
所以项目写的“development/student/testing only”免责声明不会把普通 PC/云服务器上的
Proxmox 变成获许可的 Apple 硬件。实际适用条款仍应按所安装 macOS 版本、取得方式、地区和
组织协议确认。

仓库自身也没有 `LICENSE` 文件；相反，`setup` 文件头写明 all rights reserved、禁止复制/
修改/分发并限开发或学生非商业用途
（[`setup` L8-L24](https://github.com/luchina-gabriel/OSX-PROXMOX/blob/209f6df3a4e36a9a2853975fd962fbc34d562249/setup#L8-L24)）。
因此 README 的 GitHub license badge 不能当作开源许可授权。

### 运维

- **TSC 是硬约束。** 项目给所有 CPU profile 暴露 `invtsc`，并警告 Monterey 以后在宿主
  TSC 不稳定时多核 VM 会崩溃
  （[README L81-L112](https://github.com/luchina-gabriel/OSX-PROXMOX/blob/209f6df3a4e36a9a2853975fd962fbc34d562249/README.md#L81-L112)）。
  Linux KVM 文档说明 TSC 本来就是最复杂的虚拟时钟之一，多 socket/NUMA、C-states 和迁移
  都可能破坏同步
  （[Linux KVM timekeeping: TSC](https://docs.kernel.org/virt/kvm/x86/timekeeping.html#tsc-hardware)）。
- **共享身份。** 脚本修改 ISO storage 中的一份 OpenCore ISO 和一份 `.smbios.json`；所有
  引用它的 VM 会共用同一套 serial/MLB/UUID/ROM。多个并行 VM 若不拆分镜像，会以同一个
  Mac 身份访问 Apple services。
- **升级耦合。** OpenCore、kext、kernel binary patches 与 Darwin kernel 版本强耦合；一次
  macOS 更新即可让固定 pattern 不再匹配或产生新 panic。项目支持列表只是作者测试声明，
  不是 Apple/Proxmox 的支持承诺。
- **宿主机副作用大。** 无条件 blacklist GPU/audio drivers、修改 boot parameters、允许
  unsafe interrupts、移除软件源和 patch Proxmox UI，都可能影响同机其他 VM、宿主 console、
  安全边界和后续升级。它要求 fresh Proxmox 正是因为没有把变化隔离成一台 VM 的配置。
- **passthrough 限制。** 真实 GPU 不能同时归宿主和 VM，通常阻止 live migration；GPU reset
  bug、IOMMU group、ROM、BAR 空间和 macOS driver support 都取决于具体硬件。

## 一句话心智模型

把它理解为“自动部署的 Hackintosh BSP”最准确：Proxmox/KVM 提供性能和隔离，QEMU/OVMF
提供 PC 虚拟平台，QEMU AppleSMC + OpenCore 的 SMBIOS/NVRAM/kext/kernel patches 让 macOS
接受该平台，Apple Internet Recovery 提供安装内容。它能降低手工配置门槛，但不会消除
Hackintosh 的硬件兼容、更新脆弱性、宿主安全副作用或 Apple 许可限制。

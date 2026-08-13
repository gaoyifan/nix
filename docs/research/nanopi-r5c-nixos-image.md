# NanoPi R5C NixOS 镜像构建方案调研

调研日期：2026-08-13。

## 结论

NanoPi R5C 已经可以使用主线 Linux、主线 U-Boot 和 NixOS
`generic-extlinux-compatible` 构建可直接写入 microSD 或 eMMC 的 NixOS
镜像，不需要 FriendlyELEC 的 vendor kernel。当前最完整的社区实现是
[`bdew/nixos-nanopi`](https://github.com/bdew/nixos-nanopi/tree/2da773866f5e69a227daf05fa453a8b3bf4b29a7)；
它提供 R5C NixOS module、可构建的 flake package 和预构建镜像，并有真机用户验证。
但 nixpkgs 和 nixos-hardware 目前还没有官方 R5C 镜像或专用 module。

对本仓库，推荐不直接引入 `bdew/nixos-nanopi`，而是沿用已在
[`nixos/optional/nanopi-r4s.nix`](../../nixos/optional/nanopi-r4s.nix)
中使用的 NixOS `sd-image.nix` + extlinux 结构，新增一个从主线 U-Boot
源码构建的 R5C bootloader package。这一路线与现有 R4S 实现一致，
同时避免了社区方案对第三方预构建 U-Boot ZIP 的依赖。

## 主线支持现状

FriendlyELEC 的官方规格确认 R5C 采用 RK3568B2、LPDDR4X、eMMC、
microSD 和两个 PCIe 2.5 GbE，调试 UART 是 3.3 V、1500000 baud；官方
也明确支持从 microSD 启动并通过 MaskROM/USB 恢复 eMMC，见
[`NanoPi R5C Wiki`](https://wiki.friendlyelec.com/wiki/index.php/NanoPi_R5C)。

Linux 主线在
[`05620031408a`](https://github.com/torvalds/linux/commit/05620031408ac6cfc6d5c048431827e49aa0ade1)
加入 R5C 设备树，随后在
[`5325593377f0`](https://github.com/torvalds/linux/commit/5325593377f07de31f7e473a9677a28a04c891f3)
修正 reset GPIO。当前的
[`rk3568-nanopi-r5c.dts`](https://github.com/torvalds/linux/blob/3d6d817622b0a9721e3cc404df3469171582be13/arch/arm64/boot/dts/rockchip/rk3568-nanopi-r5c.dts)
通过 R5S 共用 DTSI 描述 eMMC、microSD、RTC、HDMI、USB、热管理、
三个 PCIe controller、LED 和按键。因此可使用 stock NixOS kernel；无需
携带板厂 kernel 补丁。

U-Boot 主线在
[`6a73211d4bb1`](https://github.com/u-boot/u-boot/commit/6a73211d4bb12d62ce82b33cee7d75d215a3d452)
加入 `nanopi-r5c-rk3568_defconfig`，又在
[`a9e9445ea2bb`](https://github.com/u-boot/u-boot/commit/a9e9445ea2bb010444621e563a79bc33fe064f9c)
开启 R5C/R5S 所需的 PCIe bifurcation 和 RTL8169 驱动。当前 U-Boot 的
[`Rockchip 文档`](https://docs.u-boot.org/en/stable/board/rockchip/rockchip.html)
也明确列出 R5C，并给出 MMC 启动镜像的标准写入布局。

R5C 的启动链是：

```text
RK3568 BootROM
  -> rkbin DDR TPL + U-Boot SPL (idbloader.img，sector 64 / 32 KiB)
  -> TF-A BL31 + U-Boot proper (u-boot.itb，sector 16384 / 8 MiB)
  -> /boot/extlinux/extlinux.conf
  -> NixOS kernel + initrd + rockchip/rk3568-nanopi-r5c.dtb
```

Rockchip 的 DDR TPL 仍是不可自由的 `rkbin` blob；这不是 R5C 社区项目
特有的限制。当前 nixpkgs 已打包
[`rkbin`](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/pkgs/by-name/rk/rkbin/package.nix)，
并导出 `BL31_RK3568` 和 `TPL_RK3568`。

## 已有方案

### `bdew/nixos-nanopi`

这是目前最适合直接下载或作为参考的方案。它的
[`README`](https://github.com/bdew/nixos-nanopi/blob/2da773866f5e69a227daf05fa453a8b3bf4b29a7/readme.md#L187-L237)
明确提供 `nixosModules.r5c` 和 `nix build .#nanopi-r5c-image`；生成的镜像
可直接写入 SD 或 eMMC。其
[`r5c.nix`](https://github.com/bdew/nixos-nanopi/blob/2da773866f5e69a227daf05fa453a8b3bf4b29a7/models/r5c.nix#L223-L254)
选择主线 DTB，并按 PCIe sysfs path 稳定命名两个 RTL8125B 网口。
它默认使用主线 `r8169`，另提供可选的 out-of-tree `r8125`。

镜像布局很简洁：
[`utils/image.nix`](https://github.com/bdew/nixos-nanopi/blob/2da773866f5e69a227daf05fa453a8b3bf4b29a7/utils/image.nix#L397-L445)
生成一个从 16 MiB 开始的 ext4 root partition，写入 extlinux 配置，再把
`idbloader.img` 写到 32 KiB、`u-boot.itb` 写到 8 MiB。项目于
2026-06-01 发布了
[`NixOS 26.05 / U-Boot 2026.04`](https://github.com/bdew/nixos-nanopi/releases/tag/nixos2026.05-uboot2026.04-build1)
的 R5C 镜像，并且于 2026-07-17 修正了 remote builder 下 extlinux 为空的问题。
R5C 用户也在
[`issue #1`](https://github.com/bdew/nixos-nanopi/issues/1#issuecomment-2712074202)
报告成功构建和使用该板的镜像。

其局限是：

- U-Boot 不在同一 Nix derivation 内从源码构建，而是下载并 hash 固定
  `inindev/uboot-rockchip` 的预构建 ZIP；
- 预构建镜像的默认用户/密码是 `nix`，启用 SSH 和无密码 sudo，不应
  原样用于生产；
- 没有显式配置 MAC 时每次启动会随机生成；
- 在 x86_64 主机构建 aarch64 镜像时需要 binfmt 模拟或 aarch64 remote builder。

### 其他可参考实现

- [`tanshihaj/nixos-configs`](https://github.com/tanshihaj/nixos-configs/blob/35242957a268c69a8bb8787c6dfc4266f9fe232f/platforms/nanopi-r5c/default.nix)
  把 U-Boot、GPT 镜像和 `rkdeveloptool` MaskROM/Loader 刷写流程都放入 Nix；
  但它是带有个人用户、Wi-Fi、router 和 secret 设定的个人配置，并且
  U-Boot 仍停在 2023.10，适合参考而不适合直接引入。
- [`kaseiwang/flakes`](https://github.com/kaseiwang/flakes/tree/596c7b82a3b6e328b9337e0410d93a57908bb08f/nixos/r5c)
  可用 Nix 构建 U-Boot 和 rootfs，但最后需手工分区和 `dd`，未导出完整
  可直接刷写的镜像。

## 本仓库的推荐实现

当前 flake 锁定 nixpkgs `531670d871c0e29724a02f3cbcac170adc65b58c`。该
revision 使用 Linux 7.1.5 和 U-Boot 2026.04；其
[`ubootNanoPiR5S`](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/pkgs/misc/uboot/default.nix#L407-L418)
已经展示了 RK3568 所需的 `rkbin.BL31_RK3568` 和 `rkbin.TPL_RK3568`。
R5C 只是 nixpkgs 没有再导出一个同构 package。

调研中已在本仓库环境中实际执行以下等价构建：

```nix
pkgs.buildUBoot {
  defconfig = "nanopi-r5c-rk3568_defconfig";
  env = {
    BL31 = pkgs.rkbin.BL31_RK3568;
    ROCKCHIP_TPL = pkgs.rkbin.TPL_RK3568;
  };
  filesToInstall = [
    "idbloader.img"
    "u-boot.itb"
    "u-boot-rockchip.bin"
  ];
  extraMeta.platforms = ["aarch64-linux"];
}
```

构建成功，产出 184 KiB `idbloader.img`、1.2 MiB `u-boot.itb` 和
9.1 MiB `u-boot-rockchip.bin`。这验证了当前锁定的 nixpkgs 已经具备
构建 R5C bootloader 的全部条件。该验证只覆盖 reproducible build，
不代替真机启动测试。

具体落地只需：

1. 新增 `pkgs/nanopi-r5c-uboot.nix`，使用上述 `buildUBoot` 定义，并从
   `pkgs/default.nix` 导出。
2. 新增 `nixos/optional/nanopi-r5c.nix`，导入 NixOS
   `installer/sd-card/sd-image.nix`，启用 extlinux，并明确设置
   `hardware.deviceTree.name = "rockchip/rk3568-nanopi-r5c.dtb"` 和串口参数
   `console=ttyS2,1500000n8`。
3. 设置 `sdImage.firmwarePartitionOffset = 16`，将 boot files 放入 root
   partition 的 `/boot`，用 `postBuildCommands` 把 `idbloader.img` 写入
   sector 64，把 `u-boot.itb` 写入 sector 16384。这与已经在真实
   R4S 配置中使用的镜像布局相同。
4. 加入 `aarch64-linux` NixOS host 和 `packages.aarch64-linux.<host>-image =
   config.system.build.sdImage`。本仓库已配置 aarch64 remote builder，无需再加
   binfmt 兼容层。
5. 首次使用新 SD 卡测试，保留现有 eMMC 不变。通过
   1500000 baud UART 验证 U-Boot、extlinux 和 initrd，然后检查两个
   RTL8125B 的 PCI path、接口命名和 MAC 稳定性。

### 网口和驱动

R5C 的两个网口都是 PCIe RTL8125B，不应借用 R4S 的 `end0`/
`enp1s0` 假设。`bdew/nixos-nanopi` 已经使用
`platform-3c0800000.pcie-*` 和 `platform-3c0400000.pcie-*` 匹配两个口；本仓库
落地时应在真机上用 `udevadm info` 确认后再把它们命名为 LAN/WAN。

先使用主线 `r8169`。只有在 iperf3、丢包、offload 或稳定性测试证明
具体问题时，才应引入 out-of-tree `r8125`；不应为了假设的性能改善
预先增加内核外模块。

## 风险和验收点

- 已证明的是主线支持、Nix 构建成功和现有社区镜像的真机成功；
  本仓库自己的 U-Boot 2026.04 + Linux 7.1.5 组合仍需在实际 R5C 上验证。
- SD 启动会受 eMMC 中现有 bootloader 和 Rockchip boot order 影响。首试时
  不应盲目清除 eMMC；若 BootROM 不选 SD，再按 FriendlyELEC 的 MaskROM/
  USB 恢复流程处理。
- 两个网口是同型 PCIe 设备，不能依赖探测顺序区分 LAN/WAN；必须
  按物理 PCI path 命名并在板上实测对应口。
- OpenWrt 24.10 曾有一个仍未关闭的
  [`R5C 冷启动后第二个网口未出现`](https://github.com/openwrt/openwrt/issues/17452)
  报告，症状指向 PCIe 初始化时序。它不证明当前 NixOS/kernel 组合存在同一问题，
  但构成了反复断电冷启动并确认两口都以 2.5 GbE 工作的具体测试依据。
- 应验证 microSD 启动、eMMC 可见性、两个 2.5 GbE、USB、RTC、
  温度传感器、按键/指示灯、重启/关机和第一次 rootfs 扩容。
- 生产镜像不应保留社区镜像的默认密码、随机 MAC 或全接口 DHCP。

## 最终判断

构建 NanoPi R5C NixOS 镜像不是一个需要 vendor kernel 或大量补丁的实验性
项目了。它现在是一个与本仓库已有 R4S 镜像非常接近的小型板级
集成工作。建议实现主线 U-Boot 源码构建的本地 module/package，用
`bdew/nixos-nanopi` 作为镜像布局、PCI path 和真机行为的对照，
而不是把整个社区 flake 变成新依赖。

# `Jimmy-Z/oob` 与 NixOS 的兼容性及切换风险

> 调查日期：2026-08-14。结论对照 `Jimmy-Z/oob`
> `7870d25b2a994e4ce99f1e3d83cd2ce2d300e385`，以及本仓库锁定的 nixpkgs
> `531670d871c0e29724a02f3cbcac170adc65b58c`
> ([`flake.lock`](../../flake.lock#L402))；源码链接均固定到对应版本。

## 结论

**思路与 NixOS 兼容，但上游安装方式不能原样使用。** Linux network namespace、
macvlan 和 systemd 的 `NetworkNamespacePath=` 都不依赖 Debian；当前 nixpkgs 提供
`iproute2`、Dropbear 和支持该指令的 systemd。因此可以把同一设计写成 NixOS 的两个
systemd service。

**普通 `nixos-rebuild switch` 不会主动删除 `/run/netns/oob`，但不能据此保证当前 OOB
SSH 会话不断。** `ip netns add oob` 通过 `/run/netns/oob` 的 bind mount 固定 namespace；
上游 setup unit 没有 `ExecStop=`，代码中也没有 `ip netns del`。只重启 Dropbear 时，旧
namespace 仍在，新进程可再次加入。真正释放命名 namespace 的操作是 unmount/delete
该名字，并且只有最后一个使用者消失时才释放 namespace
([iproute2 对命名 namespace 和生命周期的定义](https://github.com/iproute2/iproute2/blob/4151eafe813535de1ce756e978874dca43f439e4/man/man8/ip-netns.8.in#L56-L71),
[`ip netns delete`](https://github.com/iproute2/iproute2/blob/4151eafe813535de1ce756e978874dca43f439e4/man/man8/ip-netns.8.in#L95-L114),
[`ip netns add` 创建 bind mount](https://github.com/iproute2/iproute2/blob/4151eafe813535de1ce756e978874dca43f439e4/ip/ipnetns.c#L870-L900))。

风险在于 NixOS 的切换语义：声明式 service 的定义一旦变化，
`restartIfChanged` 默认是 `true`，切换会停止/启动或 restart 它
([NixOS 选项定义](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/nixos/lib/systemd-unit-options.nix#L548-L585),
[unit 内容比较](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/pkgs/by-name/sw/switch-to-configuration-ng/src/main.rs#L499-L504),
[执行 restart](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/pkgs/by-name/sw/switch-to-configuration-ng/src/main.rs#L1529-L1577))。
上游 `oob-sshd.service` 又以 `Requires=` 和 `After=` 依赖 setup unit
([unit 源码](https://github.com/Jimmy-Z/oob/blob/7870d25b2a994e4ce99f1e3d83cd2ce2d300e385/oob-sshd.service#L1-L11))。
因此 setup 或 SSH unit 因 Nix 表达式、脚本 store path、Dropbear 包路径等变化而被切换时，
Dropbear 会被停止，当前 OOB SSH 连接也会断开。namespace 通常仍存在，但从远程维护角度看，
OOB 通道已经在切换中断过；如果切换命令本身正运行在该 SSH 会话中，这尤其危险。

所以直接回答“切换会不会破坏 oob netns”：

- 不修改 OOB units、父接口也不被重建的切换，**不会破坏 namespace**；默认 namespace
  中的 nftables/OpenSSH 变化也不会直接改写它自己的网络栈。
- OOB unit 定义变化时，NixOS 默认会**中断 OOB 服务**；上游脚本不会删除 namespace，
  但不能保证无损切换。
- 如果 NixOS 实现给 setup unit 增加了对称的 `ExecStop=ip netns del oob`，那么 setup unit
  被重启时会明确销毁并重建 namespace 和 macvlan；这比上游行为更整洁，却必然造成中断。
- 如果切换删除/重建 macvlan 的父接口，或使父链路长期 down，OOB 也会失联。它与主机共享
  内核、物理 NIC 和电源，不是真正的 IPMI 式 OOB；上游 README 也明确限定了这一点
  ([设计与限制](https://github.com/Jimmy-Z/oob/blob/7870d25b2a994e4ce99f1e3d83cd2ce2d300e385/README.md#L1-L5))。

## 为什么网络隔离本身有效

iproute2 将 network namespace 定义为一份独立的网络栈，拥有自己的 route、firewall rule
和 network device
([`ip-netns(8)`](https://github.com/iproute2/iproute2/blob/4151eafe813535de1ce756e978874dca43f439e4/man/man8/ip-netns.8.in#L56-L71))。
oob 的 setup 脚本执行以下操作：

1. 创建命名 namespace `oob`；
2. 在物理父接口上创建 bridge-mode macvlan；
3. 把 macvlan 移入 `oob`，设置静态地址并启用 loopback
   ([`oob-setup`](https://github.com/Jimmy-Z/oob/blob/7870d25b2a994e4ce99f1e3d83cd2ce2d300e385/oob-setup#L1-L15))；
4. 让 Dropbear 通过 `NetworkNamespacePath=/run/netns/oob` 加入它
   ([`oob-sshd.service`](https://github.com/Jimmy-Z/oob/blob/7870d25b2a994e4ce99f1e3d83cd2ce2d300e385/oob-sshd.service#L6-L11))。

systemd 260.2 对 `NetworkNamespacePath=` 的正式语义正是：路径必须在 fork 时指向有效的
network namespace 文件，启动的进程随后加入该 namespace
([systemd 文档](https://github.com/systemd/systemd/blob/f1d0952a125b96b7ab2f1ff29a87448ade8ac29b/man/systemd.exec.xml#L2092-L2110))。
本仓库锁定的 nixpkgs 使用 systemd 260.2
([package definition](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/pkgs/os-specific/linux/systemd/default.nix#L202-L210))，
不存在 systemd 功能缺口。

这也意味着 NixOS 的主 namespace firewall 不会替 OOB namespace 过滤 Dropbear。隔离是
该设计能避开主机 nftables 误配置的原因，同时也是安全边界：若需要防火墙，必须在 OOB
namespace 内另行配置，不能假定 `networking.firewall` 已覆盖它。

## 上游实现不能直接装到 NixOS 的地方

上游安装说明是 Debian/Ubuntu 风格：用 `apt` 安装 `dropbear-bin`，再由 `install` 调用
`systemctl link` 和 `enable`
([README setup](https://github.com/Jimmy-Z/oob/blob/7870d25b2a994e4ce99f1e3d83cd2ce2d300e385/README.md#L7-L18),
[`install`](https://github.com/Jimmy-Z/oob/blob/7870d25b2a994e4ce99f1e3d83cd2ce2d300e385/install#L1-L7))。
其 unit 硬编码 `/usr/sbin/dropbear`，但 nixpkgs 的 Dropbear 安装到 Nix store 的 `bin/`
输出
([oob unit](https://github.com/Jimmy-Z/oob/blob/7870d25b2a994e4ce99f1e3d83cd2ce2d300e385/oob-sshd.service#L6-L9),
[nixpkgs Dropbear package](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/pkgs/by-name/dr/dropbear/package.nix#L21-L58))。
setup 脚本中的 `ip` 也应通过 service `path = [ pkgs.iproute2 ];` 或绝对 store path 提供。

因此合适的 NixOS 落地方式是声明 `systemd.services.oob-setup` 和
`systemd.services.oob-sshd`，以 Nix store 路径引用 `iproute2`、Dropbear、脚本和 banner，
而不是运行上游 `install` 往 `/etc/systemd/system` 写命令式链接。

上游 setup 还不适合被重复执行。它每次都无条件 `ip netns add`、`ip link add`、
`ip addr add`，且没有 `set -e`
([脚本](https://github.com/Jimmy-Z/oob/blob/7870d25b2a994e4ce99f1e3d83cd2ce2d300e385/oob-setup#L1-L15))；
第二次运行时 namespace 文件已存在，而 iproute2 以 `O_CREAT|O_EXCL` 创建该文件并返回错误
([实现](https://github.com/iproute2/iproute2/blob/4151eafe813535de1ce756e978874dca43f439e4/ip/ipnetns.c#L870-L875))。
后续命令仍会继续，可能留下多余的 macvlan 或掩盖部分失败。因此不能把这份脚本原样放进
一个会在 `switch` 时自动重启的 NixOS oneshot service。

## 建议的切换边界

若这个通道的目标是“即使普通 SSH、防火墙配置改坏，也仍可救援”，建议把切换策略明确为：

- setup 和 Dropbear service 都设置 `restartIfChanged = false`。这样 unit 内容变化时，
  `switch-to-configuration` 会跳过自动重启；新配置留到重启或明确的维护窗口应用。只设置
  `stopIfChanged = false` 不够，它只是把 stop+start 换成 `systemctl restart`，仍会杀掉
  Dropbear 进程
  ([两个选项的精确语义](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/nixos/lib/systemd-unit-options.nix#L548-L585),
  [switch 对 `X-RestartIfChanged=false` 的处理](https://github.com/NixOS/nixpkgs/blob/531670d871c0e29724a02f3cbcac170adc65b58c/pkgs/by-name/sw/switch-to-configuration-ng/src/main.rs#L727-L750))。
- setup service 的正常 stop/restart 应有明确的对称清理，再从零创建 namespace；不要重复运行
  上游的非幂等脚本。由于清理会切断 OOB，这个 restart 只应在本地控制台、另一条独立管理链路
  或已安排的维护窗口执行。
- 将父接口视为该通道的硬依赖。只要 NixOS switch 保留同一个 Ethernet netdev，macvlan
  可以继续存在；涉及接口改名、bond/bridge 重组、父设备删除或 NIC 驱动重载的变更不应通过
  唯一的 OOB SSH 链路直接切换。
- 静态地址必须在同一二层可达范围内；上游脚本没有添加 default route，所以按示例只能依赖
  地址前缀自动生成的直连 route。若管理端不在同一子网，需要显式配置 gateway/route。

这套策略保留了该项目真正有价值的边界：主 namespace 的 OpenSSH、route 和 nftables
可以出错，而救援 Dropbear 仍运行在独立网络栈中；同时不把一次普通 NixOS 配置切换变成
OOB 自身的隐式维护事件。

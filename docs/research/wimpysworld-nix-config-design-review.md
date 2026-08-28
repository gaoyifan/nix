# wimpysworld/nix-config 架构设计审查

> 调查日期：2026-08-28。上游源码固定在提交
> [`33ac488613f9232a57ebed70c33030122d87f002`](https://github.com/wimpysworld/nix-config/tree/33ac488613f9232a57ebed70c33030122d87f002)。
> 本仓库对照基线固定在提交
> [`d933ea8dd5cebf3c5b18c3efb8dc5fd796393460`](https://github.com/gaoyifan/nix/tree/d933ea8dd5cebf3c5b18c3efb8dc5fd796393460)。
> 本文只使用该提交的源码、仓库内 README/文档和 Nix/NixOS 官方文档。
> “事实”表示源码直接证明的行为；“推断”表示由这些事实得到的设计判断；
> “建议”面向本仓库；“风险”不等于已经发生的线上故障。

## 结论

这个项目最值得借鉴的不是某一个目录技巧，而是一条完整的数据流：

```text
主机/用户 inventory
  -> 一处解析默认值
  -> 自动生成 NixOS、Darwin、Home Manager outputs
  -> 注入跨模块共享的 typed facts
  -> 功能模块按语义 facts 自行启用
  -> CI 构建全部生成结果
```

优先级判断如下：

| 设计 | 判断 | 对本仓库的建议 |
| --- | --- | --- |
| 从 flake outputs 枚举并实际构建全部 checks | 最高 ROI | 保留现有平台 job/aggregate cache，只补“枚举并构建”；不要复制整套 inventory 脚本 |
| updater 修改后开 PR，由 CI 门禁合并 | 最高 ROI | 保留三个 updater 的更新逻辑和调度，只替换直推分支的尾端 |
| CI 凭据只注入真正使用它的 step/job | 最高 ROI | 把 R2 凭据和 cache 签名 key 从 workflow 全局环境移到发布步骤 |
| 单一 host inventory 生成 flake outputs | 强烈值得借鉴 | 先用 Nix attrset 收敛 `system`、modules、deploy 地址等重复清单；现在没有证据需要 TOML |
| typed host/user facts 与派生属性 | 强烈值得借鉴 | 建一个较小的项目 namespace，只收稳定事实；逐步替代 `specialArgs` 中的身份数据 |
| broadcast-and-gate | 有条件借鉴 | 只用于真正跨多主机、由稳定角色或硬件事实决定的功能；独有拓扑和服务继续显式组合 |
| 目录自动发现 | 谨慎、局部借鉴 | 只放在结构完全同质的叶模块目录；顶层域和主机 composition 保持显式 |
| TOML + JSON Schema 双层 contract | 有外部消费者时才值得 | 若采用，必须同时有 schema lint 和 resolver/module contract tests |
| 全量生成结果的 CI matrix | broadcast 的必要配套 | 应和 inventory 生成一起落地，不能只测试当前主机 |

项目 README 自己也把该仓库称为 “the deep end”，并建议新配置从更简单的 starter
开始；这与本次结论一致：应提炼其机制，不应照搬整个个人策略树
（[README L11-L15](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/README.md#L11-L15)）。

## 已验证的架构

### 1. Registry 是 flake output 的 inventory

事实：`flake.nix` 用 `builtins.fromTOML` 读取 system/user 两个 registry，再把同一份
`systems` 分别交给 `mkAllNixos`、`mkAllDarwin` 和 `mkAllHomes`
（[flake.nix L84-L106](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/flake.nix#L84-L106)）。
`fromTOML` 是 Nix 官方内建函数，会把 TOML 字符串转换成 Nix 值
（[Nix Reference Manual: `fromTOML`](https://nix.dev/manual/nix/2.32/language/builtins.html#builtins-fromTOML)）。

事实：`resolveEntry` 明确实现四层覆盖，后者优先：默认用户、由 kind/OS 推导的
desktop、ISO 默认值、registry 显式值；最后把 hostname 和对应的 user record
合并进结果
（[`flake-builders.nix` L13-L52](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/flake-builders.nix#L13-L52)）。
`mkSystemConfig` 再把已解析 entry 映射为三个 builder 的参数
（[`flake-builders.nix` L384-L408](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/flake-builders.nix#L384-L408)）。

事实：output 的集合也由 registry 推导：Linux 且非 home-only 的 entry 生成 NixOS，
Darwin entry 生成 nix-darwin，非 ISO entry 生成 `username@hostname` Home Manager
profile
（[`flake-builders.nix` L410-L436](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/flake-builders.nix#L410-L436)）。

推断：这消除了“host 清单、system 清单、Home profile 清单、部署清单各维护一份”这一类
结构性漂移。默认值覆盖顺序也从散落的调用点变成可审查的 resolver。

建议：本仓库对照基线在 [`flake/nixos.nix`](https://github.com/gaoyifan/nix/blob/d933ea8dd5cebf3c5b18c3efb8dc5fd796393460/flake/nixos.nix#L36-L70) 中显式重复
hostname、system 和 module list，并在同一文件后半段另建 deploy nodes。第一步可建立一份
Nix inventory，同时生成 `nixosConfigurations`、deploy nodes 和需要的 cache/check
outputs。先用 Nix 数据结构即可；上游选择 TOML 的明确理由是让不懂 Nix 的用户和非 Nix
工具消费 registry
（[`noughty/README.md` L58-L66](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/noughty/README.md#L58-L66)），
目前没有证据表明本仓库有这个需求。

### 2. Noughty 把共享 facts 变成 module options

事实：`lib/noughty/default.nix` 只依赖 `config` 和 `lib`，并声明可同时导入 NixOS、
nix-darwin、Home Manager 的 `noughty.*` options
（[`noughty/default.nix` L1-L15](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/noughty/default.nix#L1-L15)）。
三套根 module 确实都导入它：NixOS
（[`nixos/default.nix` L19-L43](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/nixos/default.nix#L19-L43)）、
Home Manager
（[`home-manager/default.nix` L17-L38](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/home-manager/default.nix#L17-L38)）
和 Darwin
（[`darwin/default.nix` L19-L29](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/darwin/default.nix#L19-L29)）。

事实：模型没有只传一组松散 booleans，而是保留事实并派生查询：

- `kind` 和 `formFactor` 是 enum，`tags` 是 string list，OS 从 platform 推导
  （[`noughty/default.nix` L101-L160](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/noughty/default.nix#L101-L160)）；
- workstation/server/laptop/vm/Linux/Darwin 等 flags 从这些事实推导
  （[`noughty/default.nix` L163-L208](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/noughty/default.nix#L163-L208)）；
- GPU vendor/compute acceleration 使用 enum 和 derived booleans，而不是全部塞进 tags
  （[`noughty/default.nix` L210-L361](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/noughty/default.nix#L210-L361)）；
- displays 是 typed submodules，并产生 primary output、resolution、orientation、DPI 等
  read-only shortcuts
  （[`noughty/default.nix` L403-L521](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/noughty/default.nix#L403-L521)）。

Nix 官方 module system 正是用 options 的类型约束、合并规则和多 module 定义来管理这类
共享配置
（[nix.dev: Module system](https://nix.dev/tutorials/module-system/)）。

事实：纯 helper 与 option module 分离；helper 闭包通过
`_module.args.noughtyLib` 注入，并读取最终的 `config.noughty.*`
（[`noughty-helpers.nix` L1-L38](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/noughty-helpers.nix#L1-L38)、
[`noughty/default.nix` L623-L632](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/noughty/default.nix#L623-L632)）。
官方 module-system 教程也展示了用 `_module.args` 提供可在 module evaluation 中使用的参数
（[nix.dev: Module system deep dive](https://nix.dev/tutorials/module-system/deep-dive.html#interlude-reproducible-scripts)）。

推断：这里最优秀的设计是把“原始事实、派生事实、便捷查询”分开。调用模块不必各自重新
猜测某台主机是不是 laptop、有没有 CUDA，也不必让 `specialArgs` 成为不可覆盖的第二份
identity source。

建议：本仓库可先定义较小的 namespace，例如 host 的 `name`、`system`、`kind`、
`formFactor`、结构化 hardware capabilities 和少量稳定 roles，以及 user identity。只有在
至少两个消费者确实需要时才增加派生字段；不要复制上游所有 display/GPU/keyboard 字段。

风险：Noughty 已经混入并非 host facts 的个人环境常量，例如固定 Tailnet，以及只服务于
壁纸选择的 resolution mapping
（[`noughty/default.nix` L612-L620](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/noughty/default.nix#L612-L620)、
[`noughty-helpers.nix` L40-L49](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/noughty-helpers.nix#L40-L49)）。
照搬会把 inventory 演化成所有模块都依赖的 “God object”；应坚持 facts、全局 policy、
单个 feature 配置三者的 ownership 边界。

### 3. Broadcast-and-gate 用语义取代 host import matrix

事实：README 将模式定义为“所有相关 module 都被导入，每个 module 依据 typed metadata
自行启用”
（[README L62-L86](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/README.md#L62-L86)）。
实际代码中，fingerprint module 按 `fprintd` tag 启用
（[`hardware/fprint/default.nix` L1-L10](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/nixos/_mixins/hardware/fprint/default.nix#L1-L10)），
GPU module 按 workstation、GPU presence/vendor/acceleration 选择驱动和工具
（[`hardware/gpu/default.nix` L20-L47](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/nixos/_mixins/hardware/gpu/default.nix#L20-L47)、
[`hardware/gpu/default.nix` L60-L106](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/nixos/_mixins/hardware/gpu/default.nix#L60-L106)），
Home Manager development hub 则组合 user 的 `developer` tag 与 host 类别
（[`development/default.nix` L8-L16](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/home-manager/_mixins/development/default.nix#L8-L16)、
[`development/default.nix` L49-L57](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/home-manager/_mixins/development/default.nix#L49-L57)）。

事实：有 `imports` 的 hub 保持 imports 无条件，只对 `config` 使用 `mkIf`；例如 Hermes
module 无条件导入自己的子 module，随后按 tag gate config
（[`hermes/default.nix` L414-L428](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/nixos/_mixins/server/hermes/default.nix#L414-L428)）。
这是对 Nix module system 约束的正确响应：`imports` 必须在 `config` 可用前静态决定，
依赖 `config` 的 conditional import 会形成递归
（[NixOS 官方 Wiki: Imports](https://wiki.nixos.org/wiki/The_Nix_Language_versus_the_NixOS_Module_System#Imports)、
[NixOS options: `_module.args`](https://nixos.org/manual/nixos/stable/options.html#opt-_module.args)）。

推断：当 feature 是否适用确实是 host facts 的函数时，这个模式比每台机器维护一份
feature list 更稳定。增加同类主机不需要复制已有选择，新 feature 的 ownership 也集中在
自己的 module 中。

建议：本仓库只在下列条件同时满足时采用 broadcast：

1. feature 横跨多台主机；
2. 启用条件能由稳定、可命名的事实或角色表达；
3. feature module 自包含且拥有自己的 secrets/options/tests；
4. 全部受影响主机都会在 CI 中求值或构建。

本仓库的 [`nixos/common`](../../nixos/common/default.nix#L1-L15) 已经是无条件 broadcast
层，而 [`somo-minisforum`](../../nixos/hosts/somo-minisforum/default.nix#L32-L48) 和
[`el2`](../../nixos/hosts/el2/default.nix#L6-L18) 的显式 imports 描述了真实且差异很大的
服务/拓扑 composition。建议保留后者的可见性，只把反复出现、语义稳定的 optional
capabilities 转成 gates。

风险：README 的 “condition false = zero cost” 说法不准确
（[README L68-L80](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/README.md#L68-L80)）。
仓库自己的详细文档随后给出了更准确的表述：imports 会先组成完整 module tree，false
module 仍会被求值，只是不贡献最终 config
（[`noughty/README.md` L474-L490](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/noughty/README.md#L474-L490)）。
因此可推断它通常没有运行时副作用，也可能因 laziness 避免 forcing 大量值，但绝不是零
evaluation cost；本次没有做定量 benchmark。

风险：composition 从“在 host 文件读 imports”变成“搜索全树哪些 gate 会命中”。项目仍
保留 `isHost` escape hatch，而且真实 service modules 仍有按 hostname 启用的情况，例如
website module
（[`website/default.nix` L1-L12](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/nixos/_mixins/server/website/default.nix#L1-L12)）。
这不是错误——唯一服务或物理拓扑本就可能属于某台 host——但说明 semantic gates 不能
消除所有 host-specific composition，也不应为消除 hostname 而制造虚假 tags。

### 4. “自动发现”实际是显式分域、域内发现

事实：NixOS 和 Home Manager 根 module 都显式列出一级 domains，而不是扫描整个树
（[`nixos/default.nix` L19-L43](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/nixos/default.nix#L19-L43)、
[`home-manager/default.nix` L17-L38](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/home-manager/default.nix#L17-L38)）。
server、hardware、scripts、services 等若干 hub 才用 `builtins.readDir` 导入全部直接子目录；
过滤条件只要求 entry 是 directory 且名称不是 `_template`
（[`server/default.nix` L1-L10](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/nixos/_mixins/server/default.nix#L1-L10)、
[`services/default.nix` L1-L10](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/home-manager/_mixins/services/default.nix#L1-L10)）。
官方定义中，`readDir` 返回目录 entry 到文件类型的 attrset
（[Nix Reference Manual: `readDir`](https://nix.dev/manual/nix/2.35/language/builtins.html#builtins-readDir)）。

推断：最好的部分是保留显式 architecture domains，同时让同质的叶 feature 具备
drop-in extension point。README 所说“放一个目录即可”的承诺只对已经使用 auto-discovery
的 hub 成立，并非任意路径都成立。

建议：如果本仓库采用，限定在例如同构 checks 或 self-gating leaf modules；不要自动扫描
`nixos/hosts`、顶层 `optional` 或包含文档/fixtures/子系统的混合目录。每个自动发现目录都要
把“每个直接子目录必须是可 import module”写成显式 contract，并由全量 evaluation 保证。

风险：这里只有 `_template` 一个排除项；新增普通资料目录、实验目录或缺少
`default.nix` 的目录也会进入 imports。相同的 discovery boilerplate 还复制在多个 hub，
未来若需要改变排除规则，存在多处同步成本。若本仓库最终有三个以上同类 discovery hub，
再引入一个纯 helper 是合理的；现在不应为了追求“自动”先造框架。

### 5. Host 与 user metadata 分离，但只建模一个 primary user

事实：system registry 的 `username` 指向 user registry；resolver 用已解析 username 查询
一个 `userEntry`
（[`flake-builders.nix` L39-L52](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/flake-builders.nix#L39-L52)）。
user registry 本身按用户名保存角色 tags
（[`registry-users.toml` L1-L5](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/registry-users.toml#L1-L5)），
最后同时设置 `noughty.host.*` 和 `noughty.user.*`
（[`flake-builders.nix` L193-L225](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/flake-builders.nix#L193-L225)）。

推断：把 “这是什么机器” 与 “谁在使用它” 分开是正确的 domain model，同一个 developer
persona 可以跨 workstation、server 和 Darwin 复用；module 也能组合 user role 与 host
capability，而不是把两者压成 hostname。

风险：关系是 `system -> username` 的单值映射，`mkAllHomes` 每个 system 只生成一个
`username@hostname`
（[`flake-builders.nix` L430-L436](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/flake-builders.nix#L430-L436)）。
它不建模一台机器上的多位 managed users。对单用户个人配置足够，但本仓库若采用 inventory，
应先决定需要 `primaryUser` 还是 `users = [ ... ]`，不要继承一个没有说清的单用户限制。

### 6. 纯数据 contract 是比继续扩张 metadata 更好的边界

事实：compositor 的 launcher、portal、capabilities、Waybar 等跨消费者数据被放在一个不依赖
module system 的纯 attrset
（[`wayland-compositors.nix` L1-L47](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/wayland-compositors.nix#L1-L47)）。
独立 test 明确检查 required paths 和 pure-data 性质
（[`tests/wayland-compositors.nix` L1-L95](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/tests/wayland-compositors.nix#L1-L95)），
并作为 flake check 暴露
（[`flake.nix` L128-L145](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/flake.nix#L128-L145)）。

推断：当多个 subsystem 需要同一份 capability contract 时，纯数据模块 + contract test
比继续给 `noughty` 增加便捷字段更深、更容易单测。这一点甚至比目录自动发现更值得借鉴。

## 已发现的边界与维护风险

### 1. Registry、builder 与 option contract 已出现真实漂移

高风险事实：system JSON Schema 允许 `keyboard.locale`
（[`registry-systems-schema.json` L130-L146](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/registry-systems-schema.json#L130-L146)），
Noughty 也声明可覆盖的 `host.keyboard.locale`
（[`noughty/default.nix` L565-L591](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/noughty/default.nix#L565-L591)），
文档还给出 registry 中设置 locale 的例子
（[`noughty/README.md` L294-L302](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/noughty/README.md#L294-L302)）；
但 `mkSystemConfig` 只传 `keyboard.layout` 和 `keyboard.variant`，完全忽略 locale
（[`flake-builders.nix` L405-L407](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/flake-builders.nix#L405-L407)）。

推断：一个合法、通过 schema lint 的 locale override 会被静默丢弃，最终仍由 layout 推导。
这是重复维护外部 schema、resolver 参数和 module options 所导致的具体失败模式，不只是理论
担忧。

建议：若本仓库引入 registry，至少为每个有默认/override 语义的字段写 resolver-to-final-
config contract test。更简单的方案是让 resolver 直接生成一份 `project.host` module attrset，
而不是把每个字段展开成十多个 function arguments。

### 2. 三个 builders 的 metadata plumbing 大量重复

事实：`mkHome`、`mkNixos`、`mkDarwin` 分别重复近乎相同的参数列表和 `noughty.host`
赋值块
（[`flake-builders.nix` L159-L227](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/flake-builders.nix#L159-L227)、
[`flake-builders.nix` L229-L304](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/flake-builders.nix#L229-L304)、
[`flake-builders.nix` L306-L376](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/flake-builders.nix#L306-L376)）。
上游文档也承认增加一个 registry-backed option 要修改 `mkSystemConfig` 和三个 builder
（[`noughty/README.md` L673-L677](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/noughty/README.md#L673-L677)）。

建议：借鉴 builder 的职责，不借鉴扁平参数接口。让 `resolveEntry` 产出规范化的
`{ host = ...; user = ...; }`，再由一个共享函数生成注入 module；三个 platform builder
只负责选择平台入口、host hardware module 和对应 module-system constructor。

### 3. Freeform tags 同时承担分类与 control-plane，约束偏弱

事实：tags 在 JSON Schema 和 Noughty 中都只是任意 string list
（[`registry-systems-schema.json` L37-L40](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/registry-systems-schema.json#L37-L40)、
[`noughty/default.nix` L145-L149](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/noughty/default.nix#L145-L149)）。
但 `iso` 会改变默认 desktop/username 并导入 installer module，`wsl`、`lima`、
`steamdeck` 会改变是否生成 NixOS output
（[`flake-builders.nix` L34-L63](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/flake-builders.nix#L34-L63)、
[`flake-builders.nix` L263-L303](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/flake-builders.nix#L263-L303)）。

事实：registry 顶部声称列出 canonical tag vocabulary
（[`registry-systems.toml` L1-L5](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/registry-systems.toml#L1-L5)），
但后面的实际 entries 已使用未列出的 `librechat`、`mongodb`、`hermes`、`postgres`、
`agentsview`
（[`registry-systems.toml` L342-L357](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/registry-systems.toml#L342-L357)）。

推断：普通 feature labels 用 freeform tags 是合理的低成本选择；会改变 output topology、
identity 或 installer behavior 的字段则已是 control-plane，不应依赖可拼错的 string。

建议：将 `managedScopes`/`outputs`、image kind、primary user 等构建语义做成结构化字段；
feature tags 可以继续自由，但最好有“registry 中存在却没有 consumer”和“consumer 使用却没有
registry entry”的 lint。

### 4. Host/hardware 边界是约定，不是事实

事实：README 宣称 host-specific directories 只含硬件，所有 behavior 都在自门控 modules
中
（[README L88-L95](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/README.md#L88-L95)）。
实际的 `nixos/revan/default.nix` 除磁盘/GPU 外，还直接配置 packages、SnapRAID service、
udev rules 和大量 tmpfiles
（[`revan/default.nix` L49-L115](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/nixos/revan/default.nix#L49-L115)）。

推断：真实系统总有难以抽象的 storage topology 和 host-only behavior；这反而证明不应把
“消灭 host config”当目标。好的边界是共享能力由 feature module 拥有，独有物理拓扑和
不可复用 policy 留在 host，而不是按文件路径机械划线。

### 5. `flake-builders.nix` 的职责并不单一

事实：同一文件既负责 registry/configuration builders，也包含 theme palette helper，随后
又生成 packages 和 devShells
（[`flake-builders.nix` L83-L157](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/flake-builders.nix#L83-L157)、
[`flake-builders.nix` L438-L505](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/lib/flake-builders.nix#L438-L505)）。

建议：本仓库已有按 output domain 分开的 `flake/*.nix`，应保留这一边界。只抽出纯
inventory resolver 和 platform constructors，不要把 packages、theme、devShell 再聚合到一个
“builder”模块。

## CI 为什么是这套架构的一部分

事实：registry 有 JSON Schema，`just lint-registry` 会用 Taplo 校验 system/user TOML
（[`justfile` L630-L635](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/justfile#L630-L635)），
独立 workflow 也执行相同检查
（[`checker.yml` L1-L28](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/.github/workflows/checker.yml#L1-L28)）。

事实：builder workflow 先从实际 flake outputs 生成 inventory matrix
（[`builder.yml` L13-L48](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/.github/workflows/builder.yml#L13-L48)），
再逐 host/profile 构建所有 NixOS、Darwin 和 Home Manager configurations
（[`builder.yml` L244-L347](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/.github/workflows/builder.yml#L244-L347)）。

推断：broadcast 会放大单个 module 修改的影响面，auto-discovery 会让新目录自动进入影响面；
全量 output matrix 正是控制这两个风险的必要反馈回路。只借鉴 broadcast 而不借鉴全矩阵 CI，
会得到最差组合。

风险：schema lint 不能证明 schema、resolver 和 final options 彼此接通；前述
`keyboard.locale` 就是反例。它必须补 resolver/module contract tests，不能把“schema 通过”
当成端到端保证。

## 工程工作流中值得直接借鉴的部分

### 1. CI 构建 flake 声明的 checks，而不只求值它们

事实：上游在每个平台 job 中枚举 `checks.${SYSTEM}` 的属性名，并逐一执行 `nix build`；任何
失败都会使 job 失败
（[`builder.yml` L120-L142](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/.github/workflows/builder.yml#L120-L142)）。

事实：本仓库已经声明 `deploy-activate`、`deploy-schema`、`home-router`、
`low-memory-disk-image`、`nixos-disk-writer-kexec` 和 `oob-ssh` 等 checks
（[`flake/checks.nix`](../../flake/checks.nix#L22-L47)），但主 CI 只构建
`checks.x86_64-linux.formatting`
（[`.github/workflows/build.yml`](../../.github/workflows/build.yml#L78-L80)）。本地
`just check-all` 使用 `nix flake check --no-build`，只能证明 derivation 可求值，不能证明
这些测试实际通过
（[`justfile`](../../justfile#L225-L240)）。

建议：这是对本仓库收益最高、改动边界最小的一项。沿用现有三个 runner 和 aggregate cache
设计，在对应平台动态枚举并构建 checks；可将廉价检查和磁盘镜像/VM 测试分 job，以免慢测试
拖住所有反馈。无需复制上游数百行的通用 flake inventory。

### 2. 自动更新先开 PR，让已有 CI 成为事务边界

事实：上游 freshener 用 matrix 表达“每个 package 有自己的 update contract”，共享尾端只在
确有变化时创建 PR
（[`freshener.yml` L18-L98](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/.github/workflows/freshener.yml#L18-L98)）。
共享脚本负责去重、建分支、提交、创建 PR 和请求 auto-merge
（[`open-pr.sh` L13-L40](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/.github/freshener/open-pr.sh#L13-L40)）。

事实：本仓库三个 updater 的尾端仍直接 push 当前分支：CLI updater
（[`bump-cli-packages.yml`](../../.github/workflows/bump-cli-packages.yml#L66-L84)）、Hermes
（[`bump-hermes.yml`](../../.github/workflows/bump-hermes.yml#L44-L59)）和 Immich
（[`bump-immich.yml`](../../.github/workflows/bump-immich.yml#L47-L62)）。其中 Hermes/Immich
只求值 checks 的 `drvPath`，没有运行真实测试。

推断：更新经 PR 能把“修改、构建/测试、合并”变成可观察的闭环，失败不会先污染 `main`。

建议：保留本仓库现有 updater 脚本、不同调度周期和专属验证；只把最后的直推改成独立 PR。
先以 required checks 为合并门禁，再决定是否 auto-merge，不必为此强行合并三个 workflow。

风险：不要原样复制上游配置。其 PR 脚本尝试启用 auto-merge，但仓库治理文件同时声明
`allow_auto_merge: false`
（[`.tailor.yml` L10-L21](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/.tailor.yml#L10-L21)），
两处意图不一致。

### 3. CI 权限、secret 和发布阶段均有清晰边界

事实：上游为 job 显式声明权限，并把 package 下载 secret 限制在实际使用它的 step
（[`builder.yml` L17-L48](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/.github/workflows/builder.yml#L17-L48)、
[`builder.yml` L172-L179](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/.github/workflows/builder.yml#L172-L179)）。
所有 build jobs 之后还有一个 sentinel 汇总失败/取消状态，发布 job 只依赖 sentinel
（[`builder.yml` L349-L423](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/.github/workflows/builder.yml#L349-L423)）。

事实：本仓库把 R2 access key、secret key、cache 签名 key 和 endpoint 放在 workflow 顶层
`env`，因此每个 job/step 都获得这些变量，即使只有发布和清理阶段需要它们
（[`.github/workflows/build.yml`](../../.github/workflows/build.yml#L30-L37)）。

建议：默认 `contents: read`；只在确需写入的 job 提升权限。将 R2 和签名凭据缩到 upload/prune
steps，或独立为只在 `main` 全部构建成功后运行的 `publish-cache` job。上游的 sentinel 思路可
复用，但无需照抄 FlakeHub 发布实现。

### 4. 动态 inventory 值得借鉴其目标，不宜复制其实现

事实：上游 CI 会从真实 flake outputs 生成 devshell/package/NixOS/Darwin/Home matrices
（[`builder.yml` L13-L48](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/.github/workflows/builder.yml#L13-L48)）。
这避免新增 output 后忘记维护一份手写 CI 清单。

风险：其 package job 会把不可求值的 package 记为 skipped 后继续
（[`builder.yml` L190-L208](https://github.com/wimpysworld/nix-config/blob/33ac488613f9232a57ebed70c33030122d87f002/.github/workflows/builder.yml#L190-L208)），
sentinel 又把 skipped job 视为通过。若 inventory discovery 自己失败并产出空矩阵，这种
fail-open 设计可能制造“全绿但什么也没测”的结果。

建议：本仓库现有 `nixos-hosts-cache`、`system-manager-hosts-cache` 和 `cli-apps-cache` 已用
aggregate derivation 覆盖主要输出。先给 checks 补动态枚举；只有 matrix 带来的并行性明显
有价值时再扩大 discovery，并断言发现数量/预期平台、遇到求值错误 fail closed。

## 应保留的本仓库优势

- 本仓库已按 output domain 拆分 `flake/*.nix`，并以 `treefmt.nix` 统一多语言格式化；这比上游
  把大量职责集中进 `flake-builders.nix`、同时在 flake/justfile 重复 formatter 逻辑更清晰。
- 本仓库的主机包含 router、云主机、storage、Incus 和专用服务等异构拓扑。显式 imports
  在这里是审计线索，不是需要消灭的样板代码。
- `home-router` 已有 typed options 和 NixOS integration test。短板是 CI 没运行测试，不是缺少
  一套 Noughty 式全局 metadata 模型。
- 当前 agenix + 私有 secrets submodule + CI fallback 符合本仓库的授权边界；上游的 SOPS
  选择本身不构成迁移理由。

## 面向本仓库的落地顺序

### 第一阶段：只收敛 inventory 和 builders

建立一份 Nix attrset inventory，最初只包含已经重复出现的事实：

```nix
{
  ali-sg = {
    system = "x86_64-linux";
    modules = [ disko.nixosModules.disko ../nixos/hosts/ali-sg ];
    deploy.hostname = "ali-sg.ts.gaof.net";
  };
}
```

从它生成 `nixosConfigurations` 和 deploy nodes。特殊 image/install outputs 继续显式扩展，
不要为了让所有 entry 形状一致而增加大量 nullable fields。

### 第二阶段：引入最小 typed facts

把 hostname、system、primary user，以及已经有多个消费者的稳定类别变成 module options。
先迁移现在通过 `specialArgs` 传递的 identity；inputs、构建函数等仍留在 specialArgs。为
resolver defaults 和每个 override 写 evaluation tests。

### 第三阶段：只迁移重复的语义 composition

选择两三个真实重复点试行 self-gating，例如 bare-metal、VM、router 或 backup capability。
feature 自己声明 `.enable`/配置并拥有 secrets；inventory role 只提供默认启用条件，host 仍可
`mkForce` 覆盖。独有 services、network topology、disk layout 保持显式 imports。

### 第四阶段：补全矩阵 CI 后再考虑 auto-discovery

CI 从生成的 outputs 自动取得 host matrix并逐一求值/构建。只有某个叶目录已经反复出现
“新增 module 后总要机械更新同一个 imports list”时，才把该目录改成 auto-discovery；顶层
domains 和 hosts 不扫描。

这四个架构阶段之前，先完成三个独立的 workflow 修补：实际构建现有 checks、缩小 secret
作用域、让 updater 经 PR。这些改动不依赖 inventory 重构，且能先提高后续重构的安全性。

## 未决不确定性

- 本次是固定提交的静态源码审查，没有 benchmark 全量 broadcast 相比 selective imports 的
  evaluation time 或内存，因此只否定 “zero cost” 的绝对说法，不给出性能数量级。
- 没有部署或运行上游任何 host；关于 runtime behavior 的判断仅限 module 最终会定义什么。
- 上游 registry schemas、README 和实现已存在漂移；本文以固定提交源码为准，不假定后续
  commit 已修复。
- 本仓库是否需要多用户 host inventory、供非 Nix 工具读取的 inventory，仍是产品需求问题；
  在这些需求出现前，不建议为它们预先引入 TOML/schema 或复杂关系模型。

# nix-community/infra 的 secrets 与仓库结构研究

本文基于 nix-community/infra 的 `master` 分支快照
[`28f7d368`](https://github.com/nix-community/infra/tree/28f7d3684aedff8b6a7bf8fc9a4347f6e01cd7d3)
以及本仓库当前的 agenix 迁移进行比较。上游当前使用的是 `sops-nix`，不是 agenix；值得借鉴的是其信息组织和一致性检查，而不是直接更换 secrets 后端。

## 结论

1. 文档不应再复制一份允许解密的主机和密钥列表。应把带名字的 recipient registry 和每个 secret 的授权规则作为唯一事实来源，并将其保存在私有 secrets submodule 中。
2. 本仓库当前只有一个 `nix-systems/default` 节点；因为 `auto-pause-cemu` 还使用 `nix-systems/default-darwin`，lock 中的 `systems` 与 `systems_2` 是两个不同仓库。给 agenix 增加 `inputs.systems.follows = "systems"` 后，它已经复用根 flake 的 `default` 节点。
3. example secrets 不是 agenix 所必需的。最简方案是把可以公开的 `.age` 密文直接放在主仓库，随后删除私有 submodule 的可用性分支和整个 `files-example`。如果仍要求隐藏密文或文件名，则必须保留某种“没有 submodule 时可求值”的结构，但可以只保留运行时路径，不需要一套伪凭据树。
4. infra 最值得借鉴的是 secrets 声明靠近消费者、主机文件只组合功能模块。不要为了模仿它而引入 flake-parts、lite-config 或动态模块发现；以本仓库规模，这些会增加间接性。

## Recipient 和主机密钥记录

infra 把所有可解密身份集中记录在 [`sops.json`](https://github.com/nix-community/infra/blob/28f7d3684aedff8b6a7bf8fc9a4347f6e01cd7d3/sops.json)：

- `admins` 是具名的管理员 age public keys；
- `hosts` 是具名的主机 age public keys；
- 文件本身不手写 public key，而是按名字引用这两个集合。

[`sops.nix`](https://github.com/nix-community/infra/blob/28f7d3684aedff8b6a7bf8fc9a4347f6e01cd7d3/sops.nix) 从 registry 生成授权矩阵：管理员默认可以解密所有文件；`hosts/<hostname>/secrets.yaml` 自动授权给同名主机；共享模块的 secret 显式列出使用它的主机。这样，“身份是什么”和“谁能读哪个 secret”各有一处声明。

生成的 `.sops.yaml` 仍然提交到 Git，但不是独立维护。[`dev/sops.nix`](https://github.com/nix-community/infra/blob/28f7d3684aedff8b6a7bf8fc9a4347f6e01cd7d3/dev/sops.nix) 在 flake check 中重新生成配置、比较差异，并执行 `sops updatekeys`；管理员 onboarding 也只要求修改 `sops.json` 后运行同一个更新命令，[见 `devdoc/onboarding.md`](https://github.com/nix-community/infra/blob/28f7d3684aedff8b6a7bf8fc9a4347f6e01cd7d3/devdoc/onboarding.md#L1-L8)。

主机私钥与 public key 清单也有明确关系。infra 将安装所需的 SSH host private keys 加密保存在 `secrets.yaml`；[`tasks.py`](https://github.com/nix-community/infra/blob/28f7d3684aedff8b6a7bf8fc9a4347f6e01cd7d3/tasks.py#L75-L97) 可以解密指定主机私钥，再由 `ssh-keygen` 和 `ssh-to-age` 导出 SSH/age public key，供 registry 记录与人工核对。它没有把运维时查询到的 key 只留在文档或聊天记录中。

### 对本仓库的建议

本仓库的 `secrets/files/secrets.nix` 同时承担 recipient registry 和 agenix rules，并位于私有 submodule；未初始化 submodule 时，主仓库用户和 CI 看不到授权关系。私有 submodule 同时保留规则和 `.age` 密文：

```text
secrets/
└── files/          # secrets.nix + .age 密文，均由私有 submodule 管理
```

`secrets/files/secrets.nix` 是唯一的主机/用户 key 清单与授权矩阵。公开文档只记录密钥轮换方法和文件位置，不复制 raw key。这样更新 public key 不会产生第三份容易漂移的文档。

agenix 官方也把 `secrets.nix` 定义为 CLI 使用的 public key 授权清单，并明确它不需要导入 NixOS 配置，[见教程](https://github.com/ryantm/agenix/blob/b027ee29d959fda4b60b57566d64c98a202e0feb/README.md#L307-L341)。修改规则后应运行 `agenix --rekey`，[见 rekey 文档](https://github.com/ryantm/agenix/blob/b027ee29d959fda4b60b57566d64c98a202e0feb/README.md#L701-L737)。

这里不增加只检查 attrset 类型的 flake check。规则文件与 `.age` 路径集合在迁移时已核对；以后修改规则应直接运行 `agenix --rekey`。不应宣称匿名 CI 能验证现有密文的实际 recipients：agenix 的 rekey 实现会先解密再重新加密文件，[见 `agenix.sh`](https://github.com/ryantm/agenix/blob/b027ee29d959fda4b60b57566d64c98a202e0feb/pkgs/agenix.sh#L202-L213)。

## `nix-systems` lock 去重

infra 在根 flake 只声明一个 `systems` input，并对上游公开的共享 inputs 显式使用 `follows`，例如 `nixpkgs`、`treefmt-nix` 和 `flake-parts`，[见 `flake.nix`](https://github.com/nix-community/infra/blob/28f7d3684aedff8b6a7bf8fc9a4347f6e01cd7d3/flake.nix#L13-L58)。其当前 lock 因而只有一个 `nix-systems/default` 节点。

本仓库当前 lock 的实际 input 边是：

```text
root             -> systems_2  (nix-systems/default)
agenix           -> systems_2  (nix-systems/default，同一 revision)
auto-pause-cemu  -> systems    (nix-systems/default-darwin)
```

在 [`flake.nix`](../../flake.nix) 的 agenix input 中已增加：

```nix
inputs.systems.follows = "systems";
```

这已经消除了重复的 `nix-systems/default` 节点。`systems` 指向另一个仓库 `default-darwin`，是 auto-pause-cemu 自己选择的系统集合；不应为了去掉 lock 节点后缀而强制它 follow 根 `systems`。lock 中的 `_2` 只是节点标识，判断重复应看 input 边、repository 和 revision，不能按后缀判断。

## 是否还需要 example secrets

infra 没有 example secrets。加密后的 YAML/二进制 secret 直接提交到仓库，flake checks 也直接包含这些文件。[`dev/sops.nix`](https://github.com/nix-community/infra/blob/28f7d3684aedff8b6a7bf8fc9a4347f6e01cd7d3/dev/sops.nix#L14-L33) 构造 check source 时显式包含所有 YAML 和 `modules/secrets`。主机没有自己的 secret 文件时，共享模块只在文件存在时设置默认路径，[见 `modules/shared/sops-nix.nix`](https://github.com/nix-community/infra/blob/28f7d3684aedff8b6a7bf8fc9a4347f6e01cd7d3/modules/shared/sops-nix.nix)。这解决的是“某主机没有 secret”，不是“CI 看不到整个 secrets 仓库”。

agenix 的正常模型同样允许密文进入 source 和 Nix store；运行时只把明文解密到 `/run/agenix` 等路径，[见官方教程](https://github.com/ryantm/agenix/blob/b027ee29d959fda4b60b57566d64c98a202e0feb/README.md#L358-L381)。因此，如果本项目接受 `.age` 密文及其文件名公开，最简且最可靠的结构是：

1. 将 `.age` 文件和 rules 放进主仓库；
2. 将 public certificates 和非秘密的 `.nix` 元数据放回普通配置目录；
3. 删除 secrets submodule、`hasRealSecrets` 分支和 `files-example`；
4. 所有配置始终引用真实的 encrypted source，CI 与部署求值同一套模块。

这比 example tree 更安全：缺少 submodule 时不会悄悄产生一套带伪凭据的“可部署”配置，也不会要求每次新增 secret 同步维护真实文件、example 文件和 fallback 逻辑。

如果 ciphertext 或 secret 文件名本身必须保密，就不能照搬 infra，也不能在保持匿名 CI 完整构建的同时简单删除所有 fallback。仍可缩减为：

- 把 `hermes-nspawn.nix`、`wg-iplc.nix`、`caddy.nix`、public certificates 等非秘密内容移出 secrets；
- 无 submodule 时不声明 `age.secrets`，消费者只保留稳定的运行时字符串路径；
- 删除 example credential 内容，而不是复制一整棵 fake secrets 目录。

这种模式可以支持求值，但不能用来实际 switch；若 CI 需要构建所有 activation closures，必须逐项确认没有构建期读取 secret source。就简洁性和部署一致性而言，公开 `.age` 密文仍是首选。

## 模块结构的可借鉴之处

infra 的顶层 host inventory 只记录主机名和 system，[见 `flake.nix`](https://github.com/nix-community/infra/blob/28f7d3684aedff8b6a7bf8fc9a4347f6e01cd7d3/flake.nix#L90-L113)。每个 `hosts/<name>/default.nix` 只导入该主机使用的功能模块；例如 build03 组合 buildbot、Hydra、nixbot、backup 等模块，[见 host 配置](https://github.com/nix-community/infra/blob/28f7d3684aedff8b6a7bf8fc9a4347f6e01cd7d3/hosts/build03/default.nix)。

secret 声明通常与消费它的功能模块放在一起，而不是集中到一个按 hostname 分支的巨大模块。例如 Hercules CI 模块同时声明它所需的 secret source 和对应的运行时 path，[见 `modules/nixos/hercules-ci.nix`](https://github.com/nix-community/infra/blob/28f7d3684aedff8b6a7bf8fc9a4347f6e01cd7d3/modules/nixos/hercules-ci.nix)；backup 模块也直接拥有其 secret 声明，[见 `modules/nixos/backup.nix`](https://github.com/nix-community/infra/blob/28f7d3684aedff8b6a7bf8fc9a4347f6e01cd7d3/modules/nixos/backup.nix#L29-L53)。共享 encrypted source 通过显式 `sopsFile` 引用，主机专属 secrets 则默认来自同目录的 `hosts/<hostname>/secrets.yaml`。

对本仓库可采用同样的 ownership 原则，但继续使用 agenix：

- `nixos/common/default.nix` 只负责导入 agenix NixOS module；
- Tailscale 模块声明 `age.secrets.<name>` 并直接把 `.path` 交给服务；
- WLT、Hermes、Wi-Fi、ACME 各自在现有功能模块中声明和消费 secrets；
- Home Manager 的 Atuin/Restic secrets 留在用户级模块；
- `secrets/files/secrets.nix` 只负责 recipients/rules，不再承担 NixOS service interface。

这已经删除了 [`secrets/default.nix`](../../secrets/default.nix) 中的 hostname 分支和大量 `services.secrets.nixos.*` 中转选项。只有确实被多个模块共同消费的 runtime path 才值得保留一个共享 option。

infra 还使用 flake-parts、lite-config 和自动导出 `modules/<platform>` 下的模块，[见 `modules/default.nix`](https://github.com/nix-community/infra/blob/28f7d3684aedff8b6a7bf8fc9a4347f6e01cd7d3/modules/default.nix)。这适合它同时管理 NixOS、nix-darwin、NixBSD、Terraform 和大量对外模块的规模。本仓库当前显式 host constructors 和 imports 更容易追踪，不建议为了目录外观一致而引入这套框架。

## 推荐实施顺序

1. ✅ 加 `agenix.inputs.systems.follows = "systems"`，合并重复的 `nix-systems/default` lock 节点。
2. ✅ 将 recipient registry/rules 收敛到私有 submodule，公开文档不复制 key 或授权关系；不添加只检查 attrset 类型的伪 check。
3. ✅ 保留私有 `.age` submodule；已把非秘密元数据移出 submodule，并把 `files-example` 缩减为求值所需的元数据。
4. ✅ 把 NixOS `age.secrets` 声明移动到实际消费者模块，并删除 `services.secrets.nixos.*` 中转 option。

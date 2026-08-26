# Atuin record sync 的 key ID mismatch

日期：2026-08-27。源码结论固定到本仓库使用的 Atuin `v18.15.2`
（commit [`1b4eb49`](https://github.com/atuinsh/atuin/tree/1b4eb4901d256637c75849f0e4f82e476934b922)）；
issue 只采用 Atuin 官方仓库中的原文和维护者回复。

## 结论

- **同一同步账号的所有客户端必须使用同一把 encryption key。** 账号 password 是认证凭据，
  与端到端加密无关；各主机当前的 key/password 相同是预期状态，但 password 相同不能证明
  records 可解密。源码直接写明 password 只负责认证、所有客户端必须共享 encryption secret
  ([`encryption.rs`](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin-client/src/encryption.rs#L1-L9))；
  新机登录也明确要求使用另一台主机的同一把 key
  ([`account/login.rs`](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin/src/command/client/account/login.rs#L178-L188),
  [同步指南](https://github.com/atuinsh/atuin/blob/v18.15.2/docs/docs/guide/sync.md#L51-L67))。
- `k4.lid.*` 是 wrapping key 的 **key ID**，不是 key 本身。维护者明确确认这些字符串
  “just key IDs, not the keys”
  ([issue #2142](https://github.com/atuinsh/atuin/issues/2142#issuecomment-2173641920))；
  源码类型是 `KeyId<V4, Local>`，由当前 32-byte key 的 `to_id()` 生成
  ([`record/encryption.rs`](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin-client/src/record/encryption.rs#L116-L150))。
  它可用于确认两把 key 是否相同，但不能反推出解密 key。
- 报错里的 `currently using` 是本机当前加载 key 的 ID；`expecting` 是正在解密的那一条
  record 内保存的 wrapping-key ID。两个 ID 不同，严格证明该 record 不是由当前 key 包裹；
  它不证明哪把 key “正确”，也不包含先后顺序
  ([`record/encryption.rs`](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin-client/src/record/encryption.rs#L117-L138))。
- 因此此前称 `expecting` 为“旧 key ID”并不严谨，应改称“该 record 所需的另一 key ID”。
  只有结合 record 的 host、timestamp 和已知的 key 变更事件，才能把它进一步判断为旧或新。
  Atuin 18.15.2 每次只加载一把 wrapping key，没有历史 keyring；源码明确说多 key 支持只是
  未来可能性
  ([`record/encryption.rs`](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin-client/src/record/encryption.rs#L122-L138))。

当前 secrets module 中的 key 如果对应 `currently using`，就**不是**那条 record 所需的
`expecting` key。除非另一把实际 key 还存在于备份、另一台机器或密码管理器中，否则只有
`k4.lid.*` 无法恢复它。这里“当前 key 一致”与“云端存在另一 key ID 的 record”并不矛盾：
前者只描述现在各机的 key 文件，后者描述该 record 创建或 rewrap 时使用的 key。

## 加密模型

Record sync v2 对每条 record 生成随机 content-encryption key（CEK），用 CEK 加密正文，
再用用户的 32-byte encryption key（在这里相当于 key-encryption key / wrapping key）包裹
CEK。record 保存密文以及一个 JSON footer，其中有 wrapped CEK `wpk` 和 wrapping-key ID
`kid`
([`record/encryption.rs`](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin-client/src/record/encryption.rs#L16-L51),
[`encrypt`](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin-client/src/record/encryption.rs#L54-L112),
[`footer`](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin-client/src/record/encryption.rs#L141-L167))。

解密时 Atuin 先从当前 `key_path` 读取唯一的 32-byte key，计算其 ID；再读取 record footer
的 `kid`。两者不相等时，它在尝试 unwrap CEK 之前就报错。因此：

```text
currently using k4.lid.A = 当前 key 文件中 key 的 ID
expecting       k4.lid.B = 该 record footer 中记录的 wrapping-key ID
```

源码中另有“old/new key encoding”的兼容逻辑：早期 key 文件直接写 32 bytes，后来加入
MessagePack 长度前缀；两种编码如果解出相同 32 bytes，会得到同一 key ID，与本次两个不同的
`k4.lid` 无关
([`encryption.rs`](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin-client/src/encryption.rs#L83-L118))。

## 另一 key ID 的可能来源

已由官方维护者确认的一种具体路径是：Atuin 在 key 文件不存在时会随机生成 key，未登录时也
仍需用它加密本地 records；正常 `atuin login` 若收到另一把账号 key，会先将整个本地 store
从当前 key re-encrypt 到账号 key，再覆盖 key 文件
([`load_key`](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin-client/src/encryption.rs#L33-L68),
[`login`](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin/src/command/client/account/login.rs#L237-L265))。

如果用户或声明式配置直接把账号 key 写到 `key_path`，就可能绕过这次转换：此前由临时随机
key 加密的 records 仍留在 store，之后的 records 则使用注入的账号 key。Atuin 维护者在
[issue #2479](https://github.com/atuinsh/atuin/issues/2479#issuecomment-2528215934)
对这一混合 store 成因作了明确解释。这与 HM/secret 直接部署 key 文件的模式高度相关，
但在尚未定位 mismatch record 的 host/timestamp 之前，只能列为强候选，不能断言它就是本次
事故的历史路径。

其他与官方模型一致的可能路径包括：某台主机过去以不同 key 登录并上传过 records；key 文件
丢失后由 `load_key` 自动生成新 key；或手工替换/复制 Atuin 内部文件。当前各机 key 相同不会
排除这些历史路径。维护者也说明，这类错误通常表示 store 中有当前 key 无法解密的 records，
而复制 files/sessions 等操作可能触发边缘情况
([issue #2449](https://github.com/atuinsh/atuin/issues/2449#issuecomment-2499141545))。

[`#3379`](https://github.com/atuinsh/atuin/issues/3379) 只是一个仍未得到维护者诊断的 open
bug report；它复现了相同报错，但不足以证明本次是 Atuin 已确认的软件 bug。此前把它称为
“Atuin 的已知问题”应撤回。

## 为什么 Debian 可能看似正常

这是根据 18.15.2 同步源码得出的**推论**：sync 先把远端 records 原样写入 `records.db`，然后
只解密本轮新下载的 record IDs，将它们增量写入 `history.db`
([`record/sync.rs`](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin-client/src/record/sync.rs#L218-L272),
[`client/sync.rs`](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin/src/command/client/sync.rs#L77-L119),
[`incremental_build`](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin-client/src/history/store.rs#L260-L295))。

所以旧机可能已经有完整、可搜索的 `history.db`，而一次没有新增下载的普通 sync 不会遍历并
重新解密 `records.db` 的所有旧 records。新机从空 store 下载全量 records 时则一定会碰到
mismatch。要判断 Debian 的 encrypted store 是否真的一致，应使用只读验证
`atuin store verify`；它会逐条用当前 key 解密整个 store
([`verify`](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin-client/src/record/sqlite_store.rs#L337-L346))。
注意不能只检查退出码：18.15.2 即使验证失败也只打印 `Failed to verify...`，随后返回成功；
必须检查输出明确包含 `Local store encryption verified OK`
([`store/verify.rs`](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin/src/command/client/store/verify.rs#L13-L24))。

还可以在 `records.db` 的一致性快照上只读定位 mismatch 的来源。`store` 表直接保存
`host`、纳秒 Unix `timestamp` 和 `cek` JSON；`cek` 内含 `kid`
([`sqlite_store.rs`](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin-client/src/record/sqlite_store.rs#L73-L114))。
按 `(host, kid)` 分组并比较最早/最晚时间，可区分“某个 host 一直使用另一 key”和
“同一 host 在某个时间点发生 key 切换”，也能确认 Debian 的本地 store 是否已经包含坏 records：

```sql
SELECT
  host,
  json_extract(cek, '$.kid') AS kid,
  COUNT(*) AS records,
  datetime(MIN(timestamp) / 1000000000, 'unixepoch') AS first_utc,
  datetime(MAX(timestamp) / 1000000000, 'unixepoch') AS last_utc
FROM store
GROUP BY host, kid
ORDER BY first_utc, host, kid;
```

这只暴露 key ID，不读取或输出实际 key；在断言“旧 key”或决定迁移哪一个 DB 前，应优先做
这一步。

## 本地 DB 的含义与迁移边界

Atuin 18.15.2 默认将 `history.db`、`records.db`、`meta.db` 和 `key` 分开存放
([`settings.rs`](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin-client/src/settings.rs#L1471-L1488))：

| 文件 | 作用 | 对本次迁移的含义 |
| --- | --- | --- |
| `history.db` | 已解密、供搜索使用的 history index | Debian 中仍可搜索的历史保全价值最高；复制一致性快照合理，但不修复云端或 `records.db` 的 key mismatch。 |
| `records.db` | sync v2 的加密 record store，包含密文和 wrapped CEK | 只有 `atuin store verify` 通过时，才有理由把它作为健康 store 一同迁移；否则会把 mismatch 原样带过去。 |
| `meta.db` | host ID、last-sync 和 session/Hub token 等元数据 | 迁移它会克隆 Debian 的 Atuin host identity 和登录 session；如果新机应是新 host，则不迁。它不保存 encryption key/password。 |
| `key` | 唯一的 32-byte encryption key | 已由 secrets/HM 管理时无需从 DB 恢复；但直接部署它不能修复历史上的 mixed-key records。 |

`records.db` 可完整重建 `history.db`，但重建会解密每一条 history record，存在 mismatch 时同样
失败
([`rebuild history`](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin/src/command/client/store/rebuild.rs#L50-L66),
[`HistoryStore::build`](https://github.com/atuinsh/atuin/blob/v18.15.2/crates/atuin-client/src/history/store.rs#L205-L257))。
反过来，只复制 Debian 的 `history.db` 能保住当前可读历史，却不会让远端坏 record 可解密；
在继续启用 record sync 前仍须单独处理 mismatch。

因此，复制 Debian `history.db` 的 SQLite 一致性快照可以作为**非破坏性的历史保全措施**，
但不应描述成 sync 修复。迁移 `records.db` 前先验证；不要仅因 Debian 平时 sync 未报错就假设它
健康。官方 issue 中维护者提供过 `store purge`、`store push --force` 等修复流程
([issue #2096](https://github.com/atuinsh/atuin/issues/2096#issuecomment-2154989475))，
但这些操作会删除无法解密的本地 records并重写远端 store，属于破坏性数据/控制面操作，
不能在本次迁移中擅自执行。

## 本次现场核查

Debian 的完整 `records.db` 中，70,693 条 records（73 个 host）使用当前 secrets module 的
canonical key；另有 532 条 records 使用 28 个其他 key ID，分布在 17 个 host。key ID 直接从
`store.cek` 的 JSON footer 读取，未读取或输出任何 raw key。

两个通过 SSH 映射出的典型 host 都已恢复使用 canonical key，但本地完整 store 验证仍失败：

- `debian42`（Atuin host `019f32de-...`）有 3,515 条 canonical records，只有 idx
  2502–2510 的 9 条 records 在 2026-08-07 22:36–22:55 UTC（CST 次日
  06:36–06:55）使用另一个 key。当前 `/run/user/1001/agenix.d` 只保留一个 canonical-key
  generation，未发现临时 raw key。现有 journal 尚未证明这段窗口与 agenix 激活直接重合。
- `el2`（Atuin host `019fca0b-...`）有 2,596 条 canonical records，另有两段共 47 条
  records 使用两个其他 key；每段之后都恢复 canonical key。第二段 alternate records 的 CST
  时间为 2026-08-07 05:16:56–05:25:06，journal 显示 Home Manager activation 从 05:16:41
  开始、下一次 activation 于 05:26:15 开始，时间边界直接重合；第一段也发生在连续的 Home
  Manager activation 周期之间。当前只保留一个 canonical-key agenix generation。

这证明 mixed-key 状态不是一次账号级“旧 key → 新 key”轮换；`el2` 的 journal 还把 alternate
key 窗口直接关联到 Home Manager activation 生命周期。结合 `load_key` 在 key path 暂时不存在
时自动生成 key 的行为，运行时 agenix secret 可用性是已由现场时间线支持的具体成因。对应的
alternate raw key 当前未在两台主机的 Atuin/agenix 路径中保留。

即使取得全部 raw keys，Atuin 18.15.2 的原生 `store rekey` 也不能直接修复 mixed store：它只
接受一把 current key 和一把 new key，并在一个事务中尝试重包裹全部 records；遇到另一 `kid`
会在事务开始前失败。理论上可写一个基于相同 Atuin record library 的修复器，按每条 record 的
`kid` 选择 raw key，只重新包裹 CEK 到 canonical key。修复后的本地 store 必须先通过完整
`store verify`。普通 record upload 在服务端使用 `ON CONFLICT DO NOTHING`，不会覆盖已有 rows；
Atuin 提供的覆盖路径是 `store push --force`，它会先清空该账号整个远端 store，再上传本地全部
records。因此真正回传修复需要所有客户端暂停同步、远端和本地完整备份、离线验证，以及明确的
破坏性操作授权。

原始主机的 plaintext `history.db` 仍保留大量对应时间段的数据：`debian42` 的 9 条 alternate
records 窗口内有 8 条本机明文 history，向前扩一小时有 35 条；`el2` 的两段 39/8 条
alternate records 窗口内分别有 32/7 条本机明文，向前扩一小时为 44/78 条。源码在命令结束时
先更新 `history.db`，再创建 encrypted record，所以 locally-created records 原本必有明文；
数量不能严格按同一时间窗口相等，因为 history timestamp 是命令开始时间，而 record timestamp
是结束后创建 record 的时间，且 record 也可能是 delete。

若已知每个 alternate key 的 raw value，精确修复不需要从 plaintext 猜测：按 record footer 的
`kid` 选择对应 key，调用 Atuin 的 `PASETO_V4::re_encrypt` unwrap/rewrap CEK，即可保留原 payload、
record ID、host、idx、timestamp 和 create/delete 语义。若 raw key 已丢失，只能从
`history.db` 生成新的 canonical-key create records；这不能可靠重建 delete records，也无法在
不解密原 record 的情况下做一一映射，因此只是有损恢复而非精确修复。

## 服务端删除与空状态验证

生产 Atuin v18.11.0 使用 SQLite/WAL，数据库位于 `debian20.ts.gaof.net` 的
`/srv/docker/atuin/atuin.db`。修改前做了两次 SQLite native backup；最新 cold backup 同时保存在：

- 服务端 `/srv/backups/atuin/20260826T194028Z-pre-delete/`
- 控制端 `/Users/yifan/backups/atuin/20260826T194028Z-pre-delete/`

两份 DB 的 SHA-256 均为
`d4837fd8164977cb86a4ef678b0f5d5cafc55d415b92ceec32043ed3a4567a1b`，源/备份
`integrity_check=ok` 且全部表行数一致。

离线分析确认 17 条受影响 `(host, history)` stream 的 alternate records 全都位于 stream 中间；
每条 stream 的 tail 都是 canonical record，没有整条 stream 全坏或 alternate tail。生产容器停服
期间，在一个事务中删除 `kid != canonical` 的 532 rows：总数从 71,243 变为 70,711，所有
74 条 stream 的 `max(idx)` 不变，foreign key rows 归零，数据库 integrity 通过。

删除后的备份副本和生产服务端都通过真正空 client 验证。生产验证结果为 70,711 encrypted
records、70,695 plaintext history rows、foreign kids=0，且 `atuin store verify` 明确输出
`Local store encryption verified OK`。中间 idx 缺口会令 v18.11/18.15 的 `idx >= start` 分页
重复下载部分 rows，但 client 唯一约束正确去重，最终没有遗漏 stream tail。

另用仍保留 1,380 foreign local rows 的 debian20 现有 client 对修复后的服务端执行普通 sync：
结果只下载 6 条新 canonical records，上传为 0；服务端仍为 70,711/0 foreign rows。原因是此次
删除未改变任何 stream head，head-only diff 判定为 Noop，普通客户端不会重传中间缺失 rows。
这些旧客户端的本地 `store verify` 仍会失败，后续应单独通过 fresh pull 或本地 purge 清理，
但不会自动重新污染服务端。

## 最终迁移状态

生产服务恢复后新增了 4 条 canonical records。最终服务端与真正空状态恢复的
`nixos-orbstack` 客户端均为 70,715 records、foreign key rows 为 0；目标
`atuin store verify` 明确输出 `Local store encryption verified OK`。

Home Manager 的 Atuin package wrapper 会在 agenix key 不存在或为空时拒绝启动 Atuin，避免
原始客户端自动生成临时 key。交互式命令和 `atuin-login` 服务均通过同一 wrapper 入口。正常 key
与缺失 key 两条路径都已验证。

目标迁移前的部分 store 保留在
`/home/yifan/.local/share/atuin.pre-server-repair-20260826T194828Z`，用于短期审计与回滚；它不是
当前 Atuin 数据目录。

# Multi-Agent Memory Mesh

> **基于 Tailscale 的多 Agent 分布式组网与云端共享记忆方案**
> Distributed multi-agent networking & shared cloud memory over a Tailscale mesh.

**状态 / Status:** `Working Prototype`（核心已在真实 4 台设备 + 3 个 AI 助手上跑通） + `Design Draft`（检索层 / 调用层待实现）

---

## 0. 一句话说明

把分散在**云服务器、笔记本、办公电脑、手机**上的多个 AI 助手，用 **Tailscale** 拉进同一个私有加密内网，再给它们一个**云端共享记忆中心（Memory Hub）**：每个 agent 保留自己的本地记忆，同时把带来源标识的记忆同步到中心，其他 agent 可读、可校验、可纠错——**记忆分档不混池，互通但不互污**。

---

## 1. 问题：AI 助手的"记忆孤岛"

同时使用多个 AI 助手（不同厂商、不同设备、不同终端）时会出现：

| 问题 | 表现 |
|------|------|
| **记忆孤岛** | 在 A 助手讲过的架构，B 助手完全不知道，用户被迫重复交代 |
| **重复劳动** | 同一件事在三台设备上解释三遍 |
| **事实漂移** | 各助手记忆版本不一致，谁也不知道哪份是对的 |
| **无交叉校验** | 单个助手记错了，没有第二双眼睛发现 |
| **隐私失控** | 敏感信息（真实姓名、密码、密钥）在多份记忆里到处扩散 |

---

## 2. 架构总览

```
                        ┌──────────────────────────────┐
                        │   Tailscale 私有加密网络      │
                        │  (WireGuard mesh, 设备身份)   │
                        └──────────────┬───────────────┘
                                       │
        ┌───────────────┬──────────────┼───────────────┬───────────────┐
        │               │              │               │               │
   ┌────▼────┐    ┌─────▼─────┐  ┌─────▼─────┐   ┌─────▼─────┐   ┌────▼────┐
   │ 云服务器 │    │  笔记本    │  │ 办公电脑   │   │ 家庭云 VM  │   │  手机   │
   │  Agent-A│    │  Agent-B  │  │  Agent-C  │   │ (无人值守) │   │ (只读端) │
   │ 常驻/定时│    │ 本地记忆   │  │ 本地记忆   │   │  执行节点  │   │         │
   └────┬────┘    └─────┬─────┘  └─────┬─────┘   └─────┬─────┘   └─────────┘
        │               │              │               │
        │  push/pull（带来源标识的记忆条目，非全量混写）  │
        └───────────────┴──────┬───────┴───────────────┘
                               │
                    ┌──────────▼───────────┐
                    │   Memory Hub (云端)   │
                    │  Git 裸库 + deploy key│
                    │  memories/            │
                    │    agent-a.md         │
                    │    agent-b.md         │
                    │    agent-c.md         │
                    │  coordination/  ← 跨助手协调/纠错
                    │  PRIVACY_RULES.md ← 全局隐私红线
                    └──────────────────────┘
```

**为什么用 Git 裸库做 Hub（而不是数据库）？**

- 天生带**版本历史**：每条记忆改动可追溯、可回滚、可 diff（"谁在什么时候改了什么"）
- 天生**分布式**：每个 agent clone 一份就是完整备份，Hub 挂了不丢数据
- **零额外服务**：不用维护数据库/API 进程，SSH + Git 即可，攻击面最小
- Markdown 文本 = **人和 LLM 都能直接读**，不需要中间层翻译

---

## 3. 五条核心设计原则

### 3.1 按来源分档，不混池（Per-Source Partitioning）

**每个 agent 一个独立文件**，写自己的、读所有人的：

```
memories/
├── agent-a_MEMORY.md     # 云端助手写
├── agent-b_MEMORY.md     # 笔记本助手写
├── agent-c_USER.md       # 办公电脑助手写
├── notion_map.md         # 共享的外部知识索引
└── privacy_rules.md      # 共享的隐私规则
```

- ✅ 谁说的话一眼可辨，**责任可追溯**
- ✅ 一个 agent 记错，不会污染其他 agent 的记忆
- ❌ 反面做法：所有 agent 往同一份 `MEMORY.md` 里追加 → 冲突、覆盖、无法归因

### 3.2 检索式访问，不全量灌入（Pull, Don't Push-All）

其他 agent 的记忆**不自动进 context**。需要时才按标签/关键词/来源检索片段。
原因：全量拉取会瞬间吃满上下文窗口，还会把别人的错误当事实吸收。

### 3.3 隐私规则前置（Privacy-First Gate）

`PRIVACY_RULES.md` 是**所有 agent 必读的第一份文件**，写死红线：

```markdown
- 用户真实姓名一律不得写入任何记忆/笔记/共享中心，只用代称
- 密码、密钥、订阅链接只留在原始密码库，禁止进记忆
- 任何信息入库前先自检：是否含真名？是否含凭据？
```

新信息入库前**先过规则**，而不是入库后再清理（清理漏一处就永久泄露）。

### 3.4 交叉校验（Cross-Validation）

这是共享记忆**最大的意外收益**：

> 实测案例：助手 A 把一台设备的局域网地址记错了。助手 B 在读共享中心时发现与自己记录的不一致，主动提出质疑并给出正确值 → 用户确认 → A 修正记忆并推送更新。
> **一个助手的错误，被另一个助手抓住了。**

因此 Hub 里专设 `coordination/` 目录，存放跨助手的纠错/协商记录：

```
coordination/
└── 2026-08-28-device-address-correction.md
```

### 3.5 最小权限同步（Least-Privilege Sync）

- 同步用**专用 deploy key**，不用主 SSH 密钥
- Hub 端用 `git-shell` + 命令白名单，该账号**只能收发 Git，不能开 shell**
- Hub 只在 Tailscale 内网可达，**不暴露公网端口**

---

## 4. 记忆条目数据结构

Markdown 为主（人机可读），每条记忆建议带元信息头。机器可读版见 [`schema/memory-entry.json`](schema/memory-entry.json)。

```jsonc
{
  "id": "mem_20260828_001",
  "agent_id": "agent-a",              // 谁写的（来源标识，必填）
  "device": "cloud-vps",              // 在哪台设备产生
  "created_at": "2026-08-28T18:00:00+08:00",
  "content": "服务 X 的反代规则：子路径需给前端打 base 前缀",
  "tags": ["infra", "nginx"],
  "scope": "shared",                  // private | shared | public
  "confidence": "verified",           // verified | reported | guess
  "verified_by": ["agent-b"],         // 交叉校验记录
  "supersedes": "mem_20260820_004"    // 取代哪条旧记忆（事实漂移治理）
}
```

关键字段说明：

| 字段 | 作用 |
|------|------|
| `agent_id` / `device` | **来源标识**，实现"分档不混池"和责任追溯 |
| `scope` | 决定是否离开本机（`private` 永不上传） |
| `confidence` | 区分"已验证事实"和"某助手声称"，防止把猜测当真理 |
| `verified_by` | 交叉校验痕迹，被多个 agent 确认过的记忆权重更高 |
| `supersedes` | 显式取代旧记忆，避免新旧矛盾同时存在 |

---

## 5. 同步机制

**当前实现：定时单向汇聚 + 手动拉取。**

```bash
# 每个 agent 所在设备上：把本地记忆推到 Hub 的自己那一档
sync.sh "/path/to/local/MEMORY.md:agent-a_MEMORY.md"
```

脚本逻辑（完整脱敏版见 [`scripts/sync.sh`](scripts/sync.sh)）：

1. 用 deploy key `clone` Hub 到临时工作目录
2. 把本地记忆文件复制到 `memories/<自己的档名>`
3. `commit`（提交信息带主机名 + 时间戳）
4. `push` 回 Hub
5. 打印当前 Hub 里的全部记忆档，便于核对

定时任务（每 6 小时一次）：

```cron
0 */6 * * * /path/to/shared-memory/sync.sh /path/to/local/MEMORY.md:agent-a_MEMORY.md >> sync.log 2>&1
```

**为什么是 6 小时而不是实时？** 记忆是"沉淀下来的结论"而非流式日志，高频同步只会制造噪声提交和冲突。紧急更新手动跑一次即可。

---

## 6. 安全模型

| 层 | 措施 |
|----|------|
| **网络层** | Tailscale（WireGuard）端到端加密 + 设备身份认证，Hub 不开公网端口 |
| **传输层** | Git over SSH，专用 deploy key，`StrictHostKeyChecking` 受控 |
| **账号层** | Hub 侧使用 `git-shell` 受限 shell + 命令白名单，无法交互登录 |
| **内容层** | `PRIVACY_RULES.md` 硬红线：真名 / 密码 / 密钥 / 订阅链接禁止入库 |
| **审计层** | Git 历史 = 完整审计日志，任何记忆改动可 diff、可归因、可回滚 |
| **权限层（设计中）** | 记忆条目级 `scope` + 读取白名单，实现细粒度访问控制 |

---

## 7. 已落地 vs 设计中

### ✅ Phase 1 — 已跑通（Working）

- [x] Tailscale 组网：云服务器 + 笔记本 + 办公电脑 + 家庭云 VM + 手机
- [x] 云端 Memory Hub（Git 裸库）+ deploy key + `git-shell` 受限账号
- [x] 三个异构 AI 助手各自本地记忆 + 按来源分档汇聚
- [x] 每 6 小时定时同步 + 同步日志
- [x] 全局隐私规则（`PRIVACY_RULES.md`）并同步进三个助手的系统级配置
- [x] `coordination/` 跨助手协调与纠错记录（已产生真实纠错案例）
- [x] 知识库留档（笔记系统）作为人类可读的第二副本

### 🚧 Phase 2 — 检索层（Design Draft）

- [ ] 记忆条目结构化（落地 `schema/memory-entry.json`）
- [ ] `memory-query` CLI：按 `tags` / `agent_id` / 时间窗 / 关键词检索，只返回片段
- [ ] 向量检索可选后端（本地 embedding，不出内网）
- [ ] 冲突检测：同一事实多来源不一致时自动标记待裁决
- [ ] `supersedes` 链路自动维护，过期记忆自动降权

### 🔮 Phase 3 — 调用层（Design Draft）

- [ ] Agent 间任务请求协议（A 请求 B 在其所在设备执行动作）
- [ ] **必须显式授权**：每类跨 agent 调用需用户单独批准，默认全部拒绝
- [ ] 调用审计流水，与记忆同源存储

---

## 8. 快速复现

> 前提：一台常驻云服务器（或任意长期在线主机）+ 已安装 Tailscale 的若干设备。

```bash
# ── 1. 所有设备加入同一 Tailscale 网络 ──
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up          # 每台设备用同一账号登录

# ── 2. 在云服务器上建 Memory Hub（Git 裸库）──
git init --bare ~/shared-memory.git
git clone ~/shared-memory.git ~/shared-memory
cd ~/shared-memory
mkdir -p memories coordination
cp /path/to/PRIVACY_RULES.example.md PRIVACY_RULES.md   # 先立隐私红线
git add -A && git commit -m "init memory hub" && git push origin master

# ── 3. 生成同步专用 deploy key（不要用主密钥）──
ssh-keygen -t ed25519 -f ~/shared-memory/.deploy/deploy_key -N ""
cat ~/shared-memory/.deploy/deploy_key.pub >> ~/.ssh/authorized_keys
# 建议给该 key 加 command="git-shell" 限制

# ── 4. 装同步脚本 + 定时任务 ──
cp scripts/sync.sh ~/shared-memory/sync.sh && chmod +x ~/shared-memory/sync.sh
crontab -e
# 加一行：0 */6 * * * ~/shared-memory/sync.sh <本地记忆路径>:<你的档名>.md >> ~/shared-memory/sync.log 2>&1

# ── 5. 其他设备上的 agent 同样 clone + 定时推自己那一档 ──
```

---

## 9. 设计取舍（Trade-offs）

| 选择 | 换来了什么 | 放弃了什么 |
|------|-----------|-----------|
| Git 裸库而非数据库 | 版本历史、零运维、天然备份、纯文本可读 | 实时性、复杂查询、并发写性能 |
| 定时同步而非实时 | 低噪声、少冲突、省资源 | 最长 6 小时的记忆延迟 |
| 分档而非合池 | 可归因、可交叉校验、错误隔离 | 需要检索层来做跨档聚合 |
| Markdown 为主 | 人和 LLM 都能直接读改 | 结构化程度弱，需 schema 约束 |
| Tailscale 内网 | 无公网暴露、设备身份可信 | 依赖第三方控制平面（可自建 Headscale 替换） |

---

## 10. English Summary

**Multi-Agent Memory Mesh** connects heterogeneous AI agents running on different devices (cloud VPS, laptop, office desktop, home-lab VM, phone) into one private encrypted Tailscale network, backed by a **cloud Memory Hub** implemented as a bare Git repository.

Core ideas:

1. **Per-source partitioning** — every agent owns one memory file; writes its own, reads all. No shared append-only pool, so errors stay isolated and attributable.
2. **Pull-based retrieval** — peers' memories are queried by tag/source/time, never bulk-loaded into context.
3. **Privacy-first gate** — a global `PRIVACY_RULES.md` is the first file every agent loads; real names and credentials never enter the mesh.
4. **Cross-validation** — with multiple agents reading the same hub, one agent catches another's factual errors (already observed in practice).
5. **Least-privilege sync** — dedicated deploy key, `git-shell` restricted account, hub reachable only inside the tailnet.

Git-as-hub gives free versioning, attribution, rollback and offline replicas with zero extra services. Phase 2 adds a structured retrieval CLI; Phase 3 adds explicitly-authorized inter-agent task invocation.

---

## License

MIT — see [LICENSE](LICENSE).

*本仓库为架构方案与参考实现，非开箱即用软件。所有示例均已脱敏：不含真实主机名、IP、域名、账号或密钥。*

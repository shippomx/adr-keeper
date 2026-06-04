# ADR Keeper 设计方案

- **状态**：Approved（待实现）
- **日期**：2026-05-22
- **作者**：bmtaka + Claude
- **目标受众**：实现者（下一阶段进入 writing-plans 后由实现 agent 阅读）

---

## 1. 背景简介

### 1.1 设计目标

用户使用 superpowers 工作流时面临一个核心痛点：**长对话中产生的设计决策在上下文压缩（compact）后大量丢失**，导致后续会话需要重新讨论已经定下来的事情，浪费时间和 token。

本方案目标：

1. **零丢失**：所有重要设计决策在 compact 前被自动持久化到磁盘
2. **零打扰**：自动化触发，不需要用户手动喊「记一下」
3. **可追溯**：被否决的方案、决策理由（不仅仅是结论）一并保存
4. **可召回**：新会话开始时 Claude 自动知道已有的决策

### 1.2 功能范围

**包含**：

- 项目级 ADR（Architecture Decision Record）的自动生成、索引、查询
- 三个 hook 触发点：SessionStart（注入索引）/ PreCompact（强制保存）/ UserPromptSubmit（频率门控扫描）
- 配套 skill 提供手动 list / view / search / new / supersede / deprecate 命令
- 跨 ADR 引用语法 `[[NNNN]]`

**不包含**：

- 全局跨项目 ADR 同步（已否决，见「备选方案」）
- LLM 驱动的 SessionEnd 写入（技术上 SessionEnd 没有 Claude 回合，不可行）
- 自动从 git diff 推断决策（超出本期范围）
- Web 可视化界面

---

## 2. 整体架构

### 2.1 系统框架

```
项目根目录/
└── docs/decisions/
    ├── INDEX.md                       ← 脚本自动维护的索引
    ├── 0001-use-event-sourcing.md     ← 单条 ADR
    ├── 0002-postgres-over-mysql.md
    ├── 0003-no-redis-cache.md
    └── .lock                          ← 并发锁文件

~/.claude/
├── settings.json                      ← 加 3 个 hook 配置（追加，非覆盖）
└── skills/adr-keeper/
    ├── SKILL.md                       ← skill 元数据
    ├── SPEC.md                        ← 本文档
    ├── templates/
    │   └── adr.md                     ← ADR 文件骨架
    └── scripts/
        ├── session-start.sh           ← SessionStart hook
        ├── precompact.sh              ← PreCompact hook
        ├── prompt-counter.sh          ← UserPromptSubmit hook
        ├── new-adr.sh                 ← 生成下一个 ADR 文件
        ├── update-index.sh            ← 重建 INDEX.md
        └── is-project-dir.sh          ← 项目目录判定（被多个脚本共用）
```

**职责划分：**

| 层 | 谁 | 职责 |
|---|---|---|
| 自动化 | Hooks | 触发时机、注入指令、维护计数器 |
| 工具 | Scripts | 编号生成、索引重建、项目判定（纯 shell，无 LLM） |
| 手动入口 | Skill | 用户主动调用：list/view/search/new/supersede/deprecate |
| 数据 | Markdown 文件 | 单一事实源，存于项目目录跟代码走 |

### 2.2 技术架构

外部依赖：

- **Claude Code hooks 系统**：通过 stdout 输出 JSON `{"additionalContext": "..."}` 向 Claude 注入指令
- **shell 工具**：`bash`、`sort`、`grep`、`sed`、`flock`（macOS 上用 `shlock` 或 `mkdir` 锁替代）
- **`rg`（ripgrep）**：用于 `adr search`（macOS 通常已装，否则降级到 `grep -r`）

无 Python / Node / 数据库依赖。完全 shell 实现，便于审计和移植。

---

## 3. 核心流程

### 3.1 状态流转

ADR 的生命周期：

```
              用户/Claude 创建
                   │
                   ▼
              Proposed (可选)
                   │
              ┌────┴────┐
              │ 采纳     │ 否决
              ▼         │
          Accepted      ▼
              │      （文件删除或归档）
        ┌─────┴─────┐
        │ 时间推移   │ 新决策取代
        ▼           ▼
    Deprecated   Superseded by NNNN
```

四个状态：

- **Proposed**：在讨论中（很少用，hook 默认抓「已定」的）
- **Accepted**：已采纳、当前生效（默认状态）
- **Deprecated**：已过时，无替代品
- **Superseded by NNNN**：被新决策取代，老决策保留作历史

### 3.2 详细流程

#### 流程 A：新会话启动 → 加载 ADR 索引

```
用户 → 启动 claude code
      │
      ▼
SessionStart hook 触发
      │
      ▼
session-start.sh 执行：
  1. is-project-dir.sh 判定当前目录是项目目录吗？
     不是 → 静默退出
     是 → 继续
  2. docs/decisions/INDEX.md 存在吗？
     不存在 → 静默退出
     存在 → 读入内容
  3. 输出 JSON：
     {"additionalContext": "<system-reminder>本项目已有 ADR:\n{INDEX 内容}\n引用时用编号</system-reminder>"}
      │
      ▼
Claude 从第一句对话起就知道历史决策
```

#### 流程 B：用户讨论中 → PreCompact 触发保存

```
对话进行中... Claude 与用户讨论多个方案，达成共识
      │
      ▼
上下文接近压缩阈值，Claude Code 即将 compact
      │
      ▼
PreCompact hook 触发（compact 之前）
      │
      ▼
precompact.sh 执行：
  1. is-project-dir.sh 判定 → 不是项目目录则静默退出
  2. 输出 JSON 包含 additionalContext：
     "扫描本次对话中产生的设计决策，对每个新决策：
       - 调用 new-adr.sh <slug> 拿到文件路径
       - 按 templates/adr.md 模板填充
       - 写完后调用 update-index.sh 重建索引
     若无新决策，回复『无新决策』即可。"
      │
      ▼
Claude 在 compact 发生前的最后一个回合：
  扫描对话 → 识别决策 → 调用 new-adr.sh → 写文件 → 调用 update-index.sh
      │
      ▼
Compact 发生，对话上下文丢失，但 ADR 文件已落盘
```

**异常路径**：

- Claude 误判，把非决策内容当决策写了 → 用户可用 `adr deprecate NNNN` 标记或直接删文件
- new-adr.sh 编号冲突（并发会话）→ flock 锁保证串行
- 磁盘写入失败 → Claude 报错给用户，用户介入

#### 流程 C：每 10 条消息 → 兜底扫描

```
用户每次发消息
      │
      ▼
UserPromptSubmit hook 触发
      │
      ▼
prompt-counter.sh 执行：
  1. is-project-dir.sh 判定 → 不是则退出
  2. 读 .claude/.adr-counter，自增写回
  3. N % 10 == 0 ？
     否 → 静默退出（绝大部分时候走这条）
     是 → 输出 additionalContext：
       "已过 10 条消息，扫描近期对话有无未保存决策，有就写到 docs/decisions/，无就忽略此提示。"
      │
      ▼
Claude 偶尔触发的轻量自检
```

#### 流程 D：用户手动操作

```
用户：「列一下所有 ADR」
      │
      ▼
Claude 匹配 adr-keeper skill → 调用 adr list
      │
      ▼
执行：cat docs/decisions/INDEX.md
      │
      ▼
显示给用户
```

其他手动命令同理（view / search / new / supersede / deprecate）。

---

## 4. 对外能力

### 4.1 接口说明

**Hooks（系统级触发）：**

| Hook | 命令 | 输入（stdin） | 输出（stdout） |
|---|---|---|---|
| SessionStart | `bash ~/.claude/skills/adr-keeper/scripts/session-start.sh` | 无 | `{"additionalContext": "..."}` 或空 |
| PreCompact | `bash ~/.claude/skills/adr-keeper/scripts/precompact.sh` | hook payload JSON | `{"additionalContext": "..."}` 或空 |
| UserPromptSubmit | `bash ~/.claude/skills/adr-keeper/scripts/prompt-counter.sh` | hook payload JSON | `{"additionalContext": "..."}` 或空（多数时候空） |

**Skill 子命令（用户级调用）：**

| 命令 | 参数 | 行为 |
|---|---|---|
| `adr list` | 无 | 显示 INDEX.md |
| `adr view <id>` | id（4 位编号或前缀） | 显示对应 ADR 全文 |
| `adr search <keyword>` | 关键词 | rg/grep 跨所有 ADR |
| `adr new <title>` | 标题 | 调用 new-adr.sh 创建并交由 Claude 引导填充 |
| `adr supersede <old-id> <new-id>` | 新旧编号 | 修改 old 的 Status 为 `Superseded by <new-id>`，更新 INDEX |
| `adr deprecate <id> <reason>` | 编号 + 原因 | 修改 Status 为 Deprecated 并追加 reason |

### 4.2 消息队列

不涉及。

---

## 5. 数据结构

### 5.1 领域模型

**单条 ADR 文件结构**（`docs/decisions/{NNNN}-{slug}.md`）：

```markdown
# 0007. 取消 Redis 缓存层，改用 Postgres 内置缓存

- **Status**: Accepted
- **Date**: 2026-05-22
- **Tags**: 架构, 数据模型

## Context（背景）

为什么需要这个决策？面临什么约束？

## Decision（结论）

具体决定做什么。

## Alternatives Considered（备选方案）

- **方案 X**：为什么没选
- **方案 Y**：为什么没选

## Consequences（影响）

- 正面：...
- 负面：...
- 后续待办：...

## References（可选）

- 相关 ADR：[[0003]] [[0005]]
- 外部链接：...
- 相关代码：`src/cache/redis.go`
```

字段约束：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| Status | enum | 是 | Accepted / Proposed / Deprecated / Superseded by NNNN |
| Date | YYYY-MM-DD | 是 | 创建日期，由 new-adr.sh 自动填 |
| Tags | 逗号分隔字符串 | 否 | 架构 / 接口 / 数据模型 / 业务规则 / 工程实践 / 自定义 |
| Context | markdown | 是 | 背景与约束，未来回看最重要的字段 |
| Decision | markdown | 是 | 结论 |
| Alternatives | markdown | 否 | 被否决的方案（强烈建议填） |
| Consequences | markdown | 否 | 影响与待办 |
| References | markdown | 否 | 关联链接 |

**INDEX.md 结构**（由 `update-index.sh` 重建，禁止手编辑）：

```markdown
# ADR Index

> 本文件由 update-index.sh 自动生成，请勿手动编辑。

| ID | 标题 | 状态 | 日期 | 标签 |
|---|---|---|---|---|
| 0001 | 用 event sourcing 而非 CRUD | Accepted | 2026-03-12 | 架构 |
| 0002 | Postgres 替代 MySQL | Accepted | 2026-04-01 | 数据模型 |
| 0003 | 取消 Redis 缓存层 | Superseded by 0007 | 2026-04-15 | 架构 |
| 0007 | 改用 Postgres 内置缓存 | Accepted | 2026-05-22 | 架构, 数据模型 |
```

**计数器文件**（`<project>/.claude/.adr-counter`）：

- 内容：单行整数，UserPromptSubmit 累计次数
- 由 prompt-counter.sh 维护

**锁文件**（`<project>/docs/decisions/.lock`）：

- 由 flock（Linux）或 mkdir 原子操作（macOS 兼容）实现，保证并发安全

### 5.2 参数配置

无运行时配置项。所有行为通过修改 hook 脚本调整，例如：

- 频率门控 `N`：在 `prompt-counter.sh` 中改 `if [ $((N % 10)) -eq 0 ]` 的 10
- 项目目录判定规则：在 `is-project-dir.sh` 中调整匹配条件

**项目目录判定规则**（`is-project-dir.sh` 的默认逻辑）：

当前工作目录满足以下任一条件即视为「项目目录」：

1. 含 `.git/` 目录
2. 已存在 `docs/decisions/` 目录（即使是空的，表示用户主动启用过）
3. 含以下任一标识文件：`package.json`、`pom.xml`、`go.mod`、`Cargo.toml`、`pyproject.toml`、`build.gradle`、`Makefile`、`CMakeLists.txt`

**显式黑名单**（即使满足上述条件也拒绝）：

- `$HOME`（用户根目录）
- `$HOME/Desktop`、`$HOME/Downloads`、`$HOME/Documents`（macOS 常见误用位置）
- `/tmp`、`/var`、`/private` 前缀
- `.claude` 自身的子目录（避免 hook 在 skills 目录里给自己写 ADR）

退出码约定：

- `0`：是项目目录
- 非 `0`：不是，调用方应静默退出

---

## 6. 其他设计

### 6.1 扩展性

未来可能的扩展点：

- **更多状态**：如 `UnderReview`、`Experimental`，只需扩展 update-index.sh 的过滤
- **更多 hook**：如 PostToolUse 后扫描 git diff 提示「这个改动是不是需要 ADR」
- **可视化**：基于 `[[NNNN]]` 引用关系生成关系图，可外挂工具读取 INDEX.md
- **跨项目复用**：未来如需要，可加 `adr export` 子命令导出为通用包

不在本期：刻意不做。

### 6.2 安全性

风险点与缓解：

| 风险 | 缓解 |
|---|---|
| Hook 在非项目目录乱写（如 `~/Desktop`） | `is-project-dir.sh` 严格判定 |
| 不同 claude 会话并发写 ADR 冲突 | `flock`/`mkdir` 锁保证编号唯一 |
| Claude 错把私密对话内容写入 ADR | ADR 文件随项目目录管理，若在 git 项目则用户可在 commit 前 review；用户也可随时手动删除 |
| `update-index.sh` 解析 ADR 失败 | 用 grep 抽字段时失败 fallback 到空字符串，不阻塞索引重建 |
| Hook 性能影响（每条消息触发） | UserPromptSubmit 主分支只做计数+判断，O(1)；99% 情况下纯磁盘操作 |

---

## 7. 测试场景

| 场景描述 | 测试类型 | 测试 case | 是否通过 |
|---|---|---|---|
| 新项目首次启动 | 集成 | 在新目录 `claude code` 启动，SessionStart 应静默退出（无 INDEX） | 待验证 |
| 已有 ADR 项目启动 | 集成 | 项目含 docs/decisions/INDEX.md，SessionStart 应注入索引到 Claude 上下文 | 待验证 |
| PreCompact 写入新 ADR | 集成 | 模拟一段含明确决策的对话，触发 PreCompact，应生成对应 .md 文件 | 待验证 |
| PreCompact 无决策时不硬写 | 集成 | 模拟一段闲聊对话，触发 PreCompact，应不产生 ADR 文件 | 待验证 |
| 每 10 条消息触发自检 | 单元 | 计数器到 10/20/30 时 prompt-counter.sh 应输出 additionalContext | 待验证 |
| 非项目目录静默退出 | 单元 | 在 `~` 触发各 hook，应无任何输出和文件创建 | 待验证 |
| 编号自增 | 单元 | new-adr.sh 应在 0001/0002/0003 后返回 0004 | 待验证 |
| 跳号场景 | 单元 | 若手动删除 0002，new-adr.sh 应仍返回 0004（取 max+1） | 待验证 |
| 并发写入 | 集成 | 两个会话同时调用 new-adr.sh，应得到两个不同编号 | 待验证 |
| INDEX 重建 | 单元 | update-index.sh 应正确解析所有 ADR 并生成表格 | 待验证 |
| supersede 流程 | 集成 | adr supersede 0003 0007 应修改 0003.md 的 Status 并更新 INDEX | 待验证 |
| 手动 adr list | 集成 | 调用 adr list 应输出 INDEX 内容 | 待验证 |
| 跨 ADR 引用 | 单元 | 文件中 `[[0003]]` 不会被脚本错误处理 | 待验证 |

---

## 8. 排期

| 任务 | 负责人 | 工作量 | 备注 |
|---|---|---|---|
| 写 templates/adr.md | 实现 agent | 0.1 人天 | 模板文件 |
| 写 scripts/is-project-dir.sh | 实现 agent | 0.2 人天 | 项目判定逻辑 |
| 写 scripts/new-adr.sh + 锁 | 实现 agent | 0.3 人天 | 编号生成 + 并发安全 |
| 写 scripts/update-index.sh | 实现 agent | 0.3 人天 | INDEX 重建 |
| 写 scripts/session-start.sh | 实现 agent | 0.2 人天 | 注入逻辑 |
| 写 scripts/precompact.sh | 实现 agent | 0.2 人天 | 注入逻辑 |
| 写 scripts/prompt-counter.sh | 实现 agent | 0.2 人天 | 频率门控 |
| 写 SKILL.md | 实现 agent | 0.2 人天 | skill 元数据与子命令文档 |
| 修改 ~/.claude/settings.json | 实现 agent | 0.1 人天 | 追加 hook 配置 |
| 单元测试 | 实现 agent | 0.5 人天 | 上表中所有「待验证」 case |
| 集成验证（真实对话） | 用户 | 0.3 人天 | 跑一两个真实会话验收 |
| **合计** | | **~2.6 人天** | |

---

## 备选方案（被否决的）

| 备选方案 | 否决理由 |
|---|---|
| 全局存储（`~/.claude/decisions/`） | 跨项目可见但与代码脱离，团队成员看不到；用户选了「项目独立存储」 |
| 混合模式（项目本地+全局索引） | 复杂度太高，索引同步易腐烂；用户拒绝 |
| 纯手动 skill，无 hook | 失去自动化优势，回到「会忘记保存」的老问题；用户拒绝 |
| Hook + 草稿模式（手动提交） | 增加用户操作负担；用户选「全自动」 |
| SessionEnd 写入 | 技术上不可行——SessionEnd 阶段无 Claude 回合可调用 LLM 分析；用现实可行的 UserPromptSubmit 频率门控替代 |
| 全局 memory 联动（方案 C） | 与「项目独立存储」选择矛盾，过度设计 |

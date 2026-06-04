# adr-keeper

Claude Code 插件：按项目管理 ADR（Architecture Decision Record），文件存放在 `<project>/docs/decisions/`，由 `INDEX.md` 索引。

## 功能

| 组件 | 作用 |
|---|---|
| **SessionStart hook** | 项目存在 `docs/decisions/INDEX.md` 时，自动把决策索引注入会话上下文 |
| **PreCompact hook** | 上下文压缩前，提示 Claude 扫描本次对话并把新决策落盘为 ADR |
| **UserPromptSubmit hook** | 每 10 条用户消息提醒一次保存未记录的决策 |
| **adr-keeper skill** | 手动操作入口：list / view / search / create / supersede / deprecate |

所有 hook 自带项目检测（git / package.json / pom.xml / go.mod 等标记）与黑名单（`$HOME`、`~/.claude`、`/tmp`、Desktop/Downloads/Documents 等），不在项目目录里不会有任何动作。

## 安装（其它机器）

在 Claude Code 中执行：

```
/plugin marketplace add <git-url-or-owner/repo>
/plugin install adr-keeper@bmtaka-tools
```

更新：

```
/plugin marketplace update bmtaka-tools
```

卸载：

```
/plugin uninstall adr-keeper@bmtaka-tools
```

> 也可以从本地 clone 安装：`/plugin marketplace add /path/to/adr-keeper`

## 使用

正常开发即可，hooks 全自动。手动操作（任意一种说法都会触发 skill）：

- "list ADRs" / "看看有哪些决策"
- "show ADR 0003" / "0003 决策是什么"
- "search ADRs for redis" / "在决策记录里找 redis"
- "create ADR for X" / "记一下这个决策"
- "supersede 0003 with 0007" / "deprecate 0005"

## 仓库结构

```
adr-keeper/
├── .claude-plugin/
│   ├── plugin.json          # 插件元数据
│   └── marketplace.json     # 使本仓库可直接作为 marketplace 安装
├── hooks/
│   └── hooks.json           # 3 个 hook，路径用 ${CLAUDE_PLUGIN_ROOT}
├── skills/
│   └── adr-keeper/
│       ├── SKILL.md
│       ├── scripts/         # hook 与 skill 共用脚本
│       ├── templates/adr.md
│       └── tests/           # bash 测试，bash tests/run-all.sh
├── PLAN.md / SPEC.md        # 设计文档
└── README.md
```

## 测试

```bash
bash skills/adr-keeper/tests/run-all.sh
```

## 从旧的手动安装迁移

如果某台机器之前是手动方式（skill 在 `~/.claude/skills/adr-keeper/` + settings.json 里注册 hooks）：

1. 删除 `~/.claude/settings.json` 中 `SessionStart` / `PreCompact` / `UserPromptSubmit` 下指向 `skills/adr-keeper/scripts/` 的 3 条 hook
2. 删除 `~/.claude/skills/adr-keeper/`
3. 按上文安装插件

项目里已有的 `docs/decisions/` 数据不受影响。

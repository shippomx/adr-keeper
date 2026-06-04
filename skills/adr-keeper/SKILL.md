---
name: adr-keeper
description: Manage per-project ADR (Architecture Decision Record) files in docs/decisions/. Use when the user mentions ADR, 决策记录, 查看历史决策, 新建决策, 搜决策, supersede, deprecate, or asks to see/edit content under docs/decisions.
---

# ADR Keeper

Per-project ADR tooling. Files live in `<project>/docs/decisions/`, indexed by `INDEX.md`.

Three hooks automate saving (SessionStart loads index, PreCompact dumps decisions before context loss, UserPromptSubmit nudges every 10 prompts). This skill is the manual escape hatch.

**Path convention**: this skill ships its own `scripts/` and `templates/` directories next to this SKILL.md. Below, `<skill-dir>` means the directory containing this SKILL.md — resolve it from where this skill was loaded (it is inside the installed plugin, NOT `~/.claude/skills/`).

## Commands

When the user asks for one of these actions, execute the corresponding bash command.

### List all ADRs

User triggers: "list ADRs", "show decisions", "看看有哪些决策".

Run:
```bash
cat docs/decisions/INDEX.md 2>/dev/null || echo "(no ADRs yet)"
```

### View a specific ADR

User triggers: "show ADR 0003", "看一下 0003 决策", "ADR 7 是什么".

Resolve the number to 4 digits, then:
```bash
ls docs/decisions/<4-digit-id>-*.md 2>/dev/null | head -1 | xargs cat
```

### Search ADRs

User triggers: "search ADRs for X", "在决策记录里找 X".

Run (prefer `rg`, fall back to `grep -r`):
```bash
rg "<keyword>" docs/decisions/ 2>/dev/null || grep -rn "<keyword>" docs/decisions/
```

### Create a new ADR manually

User triggers: "create ADR for X", "记一下这个决策".

Steps:
1. Pick a kebab-case slug (e.g. `use-event-sourcing`)
2. Run: `bash "<skill-dir>/scripts/new-adr.sh" "<slug>" "<title>"`
3. Edit the returned file path to fill in Context / Decision / Alternatives / Consequences
4. Run: `bash "<skill-dir>/scripts/update-index.sh"`

### Mark an ADR as superseded

User triggers: "supersede 0003 with 0007", "0003 已经被 0007 替换".

```bash
sed -i.bak 's/^- \*\*Status\*\*:.*$/- **Status**: Superseded by 0007/' docs/decisions/0003-*.md
rm docs/decisions/0003-*.md.bak
bash "<skill-dir>/scripts/update-index.sh"
```

(Substitute the actual old/new IDs each call.)

### Mark an ADR as deprecated

User triggers: "deprecate 0005", "0005 这个决策不用了".

```bash
sed -i.bak 's/^- \*\*Status\*\*:.*$/- **Status**: Deprecated/' docs/decisions/0005-*.md
rm docs/decisions/0005-*.md.bak
bash "<skill-dir>/scripts/update-index.sh"
```

Optionally append a `## Reason for deprecation` section with the user's stated reason.

## File layout reference

```
<project>/docs/decisions/
├── INDEX.md            ← auto-maintained; do not edit by hand
├── 0001-<slug>.md
├── 0002-<slug>.md
├── ...
└── .lock               ← acquired by new-adr.sh; ignore
```

## ADR template

Each ADR file has the same structure. See `<skill-dir>/templates/adr.md` for the exact skeleton. Required fields: Status, Date, Tags, Context, Decision. Optional but recommended: Alternatives Considered, Consequences, References.

Cross-reference between ADRs using `[[NNNN]]` syntax.

## Status values

- `Accepted` — currently in effect (default)
- `Proposed` — under discussion
- `Deprecated` — obsolete, no replacement
- `Superseded by NNNN` — replaced by ADR NNNN

## Hook coordination

When the PreCompact hook fires, Claude will be instructed to scan the conversation and write ADRs. The user does not need to invoke this skill manually for normal use; this skill exists for queries and manual fixes.

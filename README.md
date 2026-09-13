# ZoeyMemory - a Claude Code working toolkit shared across all projects

Three tools combined, one job each, no overlap:

| Job | Tool | Source |
|---|---|---|
| Memory across sessions and machines | **ZoeyMemory** (plugin in this repo) | `plugins/zoey-memory/` |
| Specs, design, reasoning behind decisions, history | **OpenSpec** | [Fission-AI/openspec](https://github.com/Fission-AI/openspec) |
| TDD, debugging, verification, code review | **superpowers** | [obra/superpowers](https://github.com/obra/superpowers) |

Plugin details: [`plugins/zoey-memory/README.md`](plugins/zoey-memory/README.md).

## Install (once per machine)

```bash
bash setup.sh
```

The script installs all three: the superpowers marketplace + plugin, the ZoeyMemory marketplace +
plugin, and the openspec CLI (needs Node 20.19+). Safe to re-run.

Manual install:

```bash
claude plugin marketplace add obra/superpowers-marketplace
claude plugin install superpowers@superpowers-marketplace
claude plugin marketplace add tuandda98/ZoeyMemory      # or a local path to this repo
claude plugin install zoey-memory@zoey-memory
npm i -g @fission-ai/openspec@latest
```

## Enable in a repo (once per repo)

Open Claude Code in the repo and type:

```
/zoey-memory:init
```

It runs `openspec init`, creates `.claude/zoey-memory.json` and `docs/memory/`, appends the workflow
block to `CLAUDE.md`, then commits. From the next session on, the hooks journal and load context.

## A working day

1. Open a machine -> the hook auto-pulls and loads context. Switched machines? Also run `/zoey-memory:start`.
2. New work worth remembering -> `/opsx:propose <name>` -> `/opsx:apply` (superpowers TDD/verification trigger themselves).
3. Done -> `/opsx:archive <name>`.
4. Leaving -> `/zoey-memory:handoff`.

## Developing this plugin

Edit files under `plugins/zoey-memory/`, then:

```bash
claude plugin marketplace update zoey-memory
claude plugin install zoey-memory@zoey-memory      # reinstall the new version
```

Try the hooks without opening Claude:

```bash
export CLAUDE_PROJECT_DIR=/path/to/test-repo
echo '{"hook_event_name":"UserPromptSubmit","prompt":"journal test"}' | bash plugins/zoey-memory/hooks/log-prompt.sh
bash plugins/zoey-memory/hooks/session-start.sh | python3 -m json.tool
```

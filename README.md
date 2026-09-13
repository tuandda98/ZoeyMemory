# ZoeyMemory - a Claude Code working toolkit shared across all projects

Three tools combined, one job each, no overlap:

| Job | Tool | Source |
|---|---|---|
| Memory across sessions and machines | **ZoeyMemory** (plugin in this repo) | `plugins/zoey-memory/` |
| Specs, design, reasoning behind decisions, history | **OpenSpec** | [Fission-AI/openspec](https://github.com/Fission-AI/openspec) |
| TDD, debugging, verification, code review | **superpowers** | [obra/superpowers](https://github.com/obra/superpowers) |

Plugin details, language support and the update/drift policy: [`plugins/zoey-memory/README.md`](plugins/zoey-memory/README.md).

## Install (once per machine)

ZoeyMemory declares **superpowers as a plugin dependency**, so one install pulls both in. The only
prerequisite is that the superpowers marketplace is known to Claude Code (a security rule: Claude
Code never auto-adds a marketplace you have not reviewed).

```bash
claude plugin marketplace add obra/superpowers-marketplace   # once; makes the dependency resolvable
claude plugin marketplace add tuandda98/ZoeyMemory            # or a local path to this repo
claude plugin install zoey-memory@zoey-memory                 # installs zoey-memory + superpowers
```

The openspec CLI (needs Node 20.19+) is installed by `/zoey-memory:init` the first time it is
missing, or by `npm i -g @fission-ai/openspec@latest`.

`bash setup.sh` does all of the above in one go and is safe to re-run.

Because of the dependency, `claude plugin disable superpowers@...` is refused while ZoeyMemory is
enabled; disable both together with the chained command Claude Code prints, or just disable
ZoeyMemory. `claude plugin uninstall zoey-memory --prune` removes superpowers too if nothing else
needs it.

## Enable in a repo (once per repo)

Open Claude Code in the repo and type:

```
/zoey-memory:init          # English
/zoey-memory:init vi       # Vietnamese journals, context and CLAUDE.md block
```

It runs `openspec init`, creates `.claude/zoey-memory.json` and `docs/memory/`, appends the workflow
block to `CLAUDE.md`, then commits. From the next session on, the hooks journal and load context.

## A working day

1. Open a machine -> the hook auto-pulls and loads context. Switched machines? Also run `/zoey-memory:start`.
2. New work worth remembering -> `/opsx:propose <name>` -> `/opsx:apply` (superpowers TDD/verification trigger themselves).
3. Done -> `/opsx:archive <name>`.
4. Leaving -> `/zoey-memory:handoff`.

## Keeping the three tools current

```
/zoey-memory:update        # updates superpowers, ZoeyMemory, openspec CLI; regenerates this repo's OpenSpec files
/zoey-memory:doctor        # read-only drift check; run in each repo after an update
```

## Developing this plugin

Edit files under `plugins/zoey-memory/`, bump `version` in both `.claude-plugin/*.json`, then:

```bash
claude plugin validate .
claude plugin marketplace update zoey-memory
claude plugin install zoey-memory@zoey-memory      # reinstall the new version
```

Run the regression suite (throwaway repos in a temp dir, no network, ~1 minute):

```bash
bash tests/run.sh
```

Try the hooks by hand without opening Claude:

```bash
export CLAUDE_PROJECT_DIR=/path/to/test-repo
echo '{"hook_event_name":"UserPromptSubmit","prompt":"journal test"}' | bash plugins/zoey-memory/hooks/log-prompt.sh
echo '{"hook_event_name":"SessionStart","source":"startup"}' | bash plugins/zoey-memory/hooks/session-start.sh | python3 -m json.tool
bash plugins/zoey-memory/scripts/doctor.sh /path/to/test-repo
```

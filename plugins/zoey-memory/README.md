# ZoeyMemory - memory across sessions and machines

This plugin solves exactly one problem: **Claude's memory does not travel across sessions or
machines.** It does not write specs and it does not do TDD - those jobs go to OpenSpec and superpowers.

| Job | Owner | What you use |
|---|---|---|
| Memory: what was asked, what is in progress, what the other machine did | **ZoeyMemory** (this plugin) | 2 hooks + 3 commands |
| Specs, design, reasoning behind decisions, dated history | **OpenSpec** | `/opsx:explore` `propose` `apply` `archive` |
| TDD, systematic debugging, verification before claiming done, code review | **superpowers** | skills that trigger themselves |

## What is inside

**2 hooks** (exit silently if the repo has no `.claude/zoey-memory.json`):

| Hook | When | What |
|---|---|---|
| `log-prompt.sh` | session start + **every prompt you send** | Appends to `docs/memory/PROMPTS.md` (committed -> the other machine can read it) |
| `session-start.sh` | session start | `git fetch` -> auto `pull --ff-only` when safe -> **loads into context**: last 30 prompts - latest session note - open OpenSpec changes with task progress - git log |

**3 commands** (`/zoey-memory:<name>`):

| Command | Job |
|---|---|
| `/zoey-memory:init` | **Enable in a repo** - openspec init, `.claude/zoey-memory.json`, `docs/memory/`, workflow block in CLAUDE.md, commit |
| `/zoey-memory:start` | Start of day: sync code + dependencies + things outside git, summarize what the other machine did |
| `/zoey-memory:handoff` | End of day: tick OpenSpec tasks, write the session note, commit WIP, push |

## Four journals, never merged

| File | Answers | Written by |
|---|---|---|
| `docs/memory/PROMPTS.md` | *what did the user ask, in what order* | hook, automatic |
| `docs/memory/SESSIONS.md` | *what is in progress, why we stopped, who decides what* | Claude, `/zoey-memory:handoff` |
| `openspec/changes/<name>/` and `archive/` | *what, why, is it done* | OpenSpec |
| `git log` | *which lines of code changed* | commits |

## Enable in a repo

```
/zoey-memory:init
```

Or run only the mechanical part by hand: `bash <plugin>/scripts/init.sh [repo path]`.

## Config: `.claude/zoey-memory.json`

Full template with inline docs: [`templates/zoey-memory.json`](templates/zoey-memory.json). Summary:

- `journal.prompts` / `journal.sessions` - paths of the two journals. `journal.enabled=false` turns automatic logging off.
- `context.enabled` / `context.recentPrompts` - whether to load context at session start, and how many prompts.
- `git.autoPull` / `allowCommit` / `allowPush` / `workingBranch`.
- `outsideGit.items` - things that do not travel with git; `/zoey-memory:start` checks them.
- `forbidden.items` - things Claude must never do on its own.

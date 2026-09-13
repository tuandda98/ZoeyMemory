# ZoeyMemory - memory across sessions and machines

This plugin solves exactly one problem: **Claude's memory does not travel across sessions or
machines.** It does not write specs and it does not do TDD - those jobs go to OpenSpec and superpowers.

| Job | Owner | What you use |
|---|---|---|
| Memory: what was asked, what is in progress, what the other machine did | **ZoeyMemory** (this plugin) | 2 hooks + 5 commands |
| Specs, design, reasoning behind decisions, dated history | **OpenSpec** | `/opsx:explore` `propose` `apply` `archive` |
| TDD, systematic debugging, verification before claiming done, code review | **superpowers** | skills that trigger themselves |

## What is inside

```
hooks/      hooks.json, session-start.sh, log-prompt.sh      thin bash: git + call into lib/
lib/        common.sh, zoey.py, log_prompt.py, session_start.py
            the ONE place that knows the config schema, defaults, i18n, CLAUDE.md block
scripts/    init.sh, doctor.sh, update.sh
commands/   init.md, start.md, handoff.md, doctor.md, update.md   -> /zoey-memory:<name>
templates/  zoey-memory.json, CLAUDE.<lang>.md, i18n/<lang>.json
tests/      run.sh (in the marketplace repo) - regression suite, no network
```

**2 hooks** (exit silently if the repo has no `.claude/zoey-memory.json`; the repo root is the git
top level of the directory Claude was launched in, so launching in a subdirectory still works):

| Hook | When | What |
|---|---|---|
| `session-start.sh` | session start (startup, resume, clear) | **1.** `git fetch` (8 s limit) -> if behind, clean and not ahead: `pull --ff-only` (20 s limit); every other case only warns. **2.** writes the session marker to the prompt journal - *after* the pull, so the journal never blocks it. **3.** loads into context: last 30 prompts - latest session note - open OpenSpec changes with task progress - git log |
| `log-prompt.sh` | **every prompt you send** | Appends to `docs/memory/PROMPTS.md` (committed -> the other machine can read it). Machine-generated prompts are skipped; long prompts are truncated to 600 chars |

SessionStart deliberately runs **one** hook: hooks on the same event run concurrently, and the
marker must be written after the pull.

**5 commands** (`/zoey-memory:<name>`):

| Command | Job |
|---|---|
| `/zoey-memory:init [vi]` | **Enable in a repo** - openspec init, `.claude/zoey-memory.json`, `docs/memory/`, workflow block in CLAUDE.md, commit. Optional language code. |
| `/zoey-memory:start` | Start of day: sync code + dependencies + things outside git, summarize what the other machine did |
| `/zoey-memory:handoff` | End of day: tick OpenSpec tasks, write the session note, commit WIP, push |
| `/zoey-memory:doctor` | Health check: detect drift after ZoeyMemory, OpenSpec or superpowers is updated. Read-only, offline |
| `/zoey-memory:update` | Update all three on this machine, regenerate this repo's OpenSpec files, run the doctor. The only thing that touches the network |

## Four journals, never merged

| File | Answers | Written by |
|---|---|---|
| `docs/memory/PROMPTS.md` | *what did the user ask, in what order* | hook, automatic |
| `docs/memory/SESSIONS.md` | *what is in progress, why we stopped, who decides what* | Claude, `/zoey-memory:handoff` |
| `openspec/changes/<name>/` and `archive/` | *what, why, is it done* | OpenSpec |
| `git log` | *which lines of code changed* | commits |

## Language

Plugin **source** is English only. Everything the **user reads** follows `language` in
`.claude/zoey-memory.json`: journal headers, the session marker, the context loaded at session
start, the CLAUDE.md block, and the language Claude uses for session notes and reports. The same
code is passed to `openspec init --language`.

- Pick it at enable time: `/zoey-memory:init vi` (or `bash scripts/init.sh --language vi`).
- Switch later: re-run `init.sh --language <code>`. It updates the config and refreshes the CLAUDE.md
  block; existing journal entries are left as they are. Edit the `Language:` line in
  `openspec/config.yaml` yourself.
- An unknown code **aborts** `init.sh` before it writes anything; it never silently falls back.
  At runtime a missing translation file or a broken string falls back to English per key.
- Add a language: copy `templates/i18n/en.json` to `<code>.json` and `templates/CLAUDE.en.md` to
  `CLAUDE.<code>.md`, translate. Keep `{placeholders}` as they are and keep the example entry in
  `sessions_header` indented.

## Staying up to date with OpenSpec and superpowers

ZoeyMemory depends on the two loosely, on purpose:

- The hook reads `openspec/changes/*/tasks.md` from the **filesystem**, never the CLI, so a CLI
  change cannot break session start. If OpenSpec moved its folders, the section would just say
  "no open changes".
- superpowers is referenced only **by skill name in the CLAUDE.md block**. If a skill is renamed,
  the rule goes stale but nothing breaks.

What can drift, and what catches it:

| Upstream change | Effect | Caught by |
|---|---|---|
| New openspec CLI | `.claude/commands/opsx/*` and `.claude/skills/openspec-*` in your repo are outdated | `update.sh` runs `openspec update`; `doctor.sh` checks the four commands exist |
| OpenSpec renames `/opsx:*` | CLAUDE.md block and context hint point to old names | `doctor.sh` (missing commands) - then edit `templates/i18n/*.json` and `CLAUDE.<lang>.md` |
| superpowers renames a skill | CLAUDE.md block names a skill that no longer exists | `doctor.sh` looks the install path up with `claude plugin list --json` and checks each skill |
| ZoeyMemory template changes | Your repo's CLAUDE.md block is the old wording | `doctor.sh` diffs the block; `init.sh` refreshes it |

Routine: `/zoey-memory:update` on each machine now and then, `/zoey-memory:doctor` in each repo
after that. Both are safe to run any time.

## Failure policy

- No config file -> both hooks exit silently (the plugin never bothers repos that did not opt in).
- Invalid config -> no journaling, no sync, and one warning line in the loaded context.
- A bad translation -> that string falls back to English; a crash while rendering -> an English
  fallback that still carries the git warnings. The hook never blocks a session.
- Network slow or down -> `FETCH_SLOW` / `FETCH_FAILED`, no pull attempted, hook returns well inside
  its 45 s budget. A pull that fails or stalls says so (`PULL_FAILED` / `PULL_SLOW`), it is never
  reported as a diverged branch.

## Enable in a repo

```
/zoey-memory:init
```

Or run only the mechanical part by hand: `bash <plugin>/scripts/init.sh [--language <code>] [repo path]`.

## Config: `.claude/zoey-memory.json`

Full template with inline docs: [`templates/zoey-memory.json`](templates/zoey-memory.json). Summary:

- `language` - `en` (default) or `vi`; any code with a `templates/i18n/<code>.json` file.
- `journal.prompts` / `journal.sessions` - paths of the two journals. `journal.enabled=false` turns automatic logging off.
- `context.enabled` / `context.recentPrompts` - whether to load context at session start, and how many prompts.
- `git.autoPull` / `allowCommit` / `allowPush` / `workingBranch`.
- `outsideGit.items` - things that do not travel with git; `/zoey-memory:start` checks them.
- `forbidden.items` - things Claude must never do on its own.

Keys of the wrong type fall back to their defaults.
